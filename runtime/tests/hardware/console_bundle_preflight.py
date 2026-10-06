#!/usr/bin/env python3
"""Preflight and package a Repentance Plus Switch console test bundle.

The normal invocation is read-only apart from the requested manifest.  A
hardware persistence acceptance mod is copied only when ``--test-bundle`` is
given; it is never added to the release tree under ``runtime/out``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import sys
from typing import Iterable


TITLE_ID = "010021C000B6A000"
ACCEPTANCE_NAME = "rplus-persistence-acceptance"
ACCEPTANCE_RELATIVE = pathlib.PurePosixPath(
    "atmosphere",
    "contents",
    TITLE_ID,
    "romfs",
    "mods",
    ACCEPTANCE_NAME,
    "main.lua",
)
TEXT_SUFFIXES = {
    ".cfg",
    ".conf",
    ".ini",
    ".json",
    ".lua",
    ".md",
    ".txt",
    ".xml",
}
FORBIDDEN_SUFFIXES = {".elf", ".nca", ".nsp", ".nsz", ".keys"}
FORBIDDEN_NAMES = {"prod.keys", "title.keys"}
ABSOLUTE_TEXT = (
    re.compile(rb"(?:^|[\"'\s=])/(?:home|root|tmp|mnt|media|opt|var)/"),
    re.compile(rb"(?:^|[\"'\s=])[A-Za-z]:[\\/]"),
)


class PreflightError(RuntimeError):
    pass


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def files_under(root: pathlib.Path) -> Iterable[tuple[pathlib.Path, pathlib.Path]]:
    for path in sorted(root.rglob("*")):
        if path.is_file():
            yield path, path.relative_to(root)


def reject_unsafe_tree(root: pathlib.Path) -> None:
    failures: list[str] = []
    for path, relative in files_under(root):
        name = path.name.lower()
        suffix = path.suffix.lower()
        if name in FORBIDDEN_NAMES or suffix in FORBIDDEN_SUFFIXES:
            failures.append(f"forbidden artifact: {relative.as_posix()}")
        if suffix in TEXT_SUFFIXES:
            payload = path.read_bytes()
            if any(pattern.search(payload) for pattern in ABSOLUTE_TEXT):
                failures.append(f"absolute path in text file: {relative.as_posix()}")
    if failures:
        raise PreflightError("\n".join(failures))


def check_tree(root: pathlib.Path, *, acceptance: bool) -> dict:
    if not root.is_dir():
        raise PreflightError(f"missing Atmosphere tree: {root}")
    contents = root / "atmosphere" / "contents" / TITLE_ID
    if not contents.is_dir():
        raise PreflightError(f"missing title directory: {contents}")

    exefs = contents / "exefs"
    nso = exefs / "subsdk9"
    if not nso.is_file():
        raise PreflightError(f"missing NSO payload: {nso}")
    if nso.read_bytes()[:4] != b"NSO0":
        raise PreflightError(f"payload is not an NSO (missing NSO0 header): {nso}")
    exefs_files = [path for path, _ in files_under(exefs)]
    if exefs_files != [nso]:
        names = ", ".join(str(path.relative_to(root)) for path in exefs_files)
        raise PreflightError(f"unexpected exefs payload(s): {names}")

    mod = contents / "romfs" / "mods" / "repentanceplus"
    required_mod_files = (mod / "main.lua", mod / "metadata.xml")
    for path in required_mod_files:
        if not path.is_file():
            raise PreflightError(f"missing Repentance Plus file: {path}")
    resource_patch = contents / "romfs" / "rp_patch" / "resources"
    if not resource_patch.is_dir() or not any(resource_patch.rglob("*")):
        raise PreflightError(f"missing or empty resource patch: {resource_patch}")

    acceptance_path = root / pathlib.Path(*ACCEPTANCE_RELATIVE.parts)
    if acceptance and not acceptance_path.is_file():
        raise PreflightError(f"test bundle is missing acceptance mod: {acceptance_path}")
    if not acceptance and acceptance_path.exists():
        raise PreflightError("release tree unexpectedly contains persistence acceptance mod")

    reject_unsafe_tree(root)
    entries = []
    for path, relative in files_under(root):
        entries.append(
            {
                "path": relative.as_posix(),
                "size": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    return {
        "title_id": TITLE_ID,
        "root": "atmosphere",
        "nso": {
            "path": f"atmosphere/contents/{TITLE_ID}/exefs/subsdk9",
            "type": "Nintendo Switch NSO",
            "header": "NSO0",
            "sha256": sha256(nso),
        },
        "checks": {
            "repentanceplus_mod": True,
            "resource_patch": True,
            "persistence_acceptance_mod": acceptance,
            "forbidden_artifacts_absent": True,
            "absolute_paths_absent_from_text": True,
        },
        "files": entries,
    }


def copy_test_bundle(source: pathlib.Path, destination: pathlib.Path, acceptance_source: pathlib.Path) -> None:
    if destination.exists():
        raise PreflightError(f"refusing to overwrite existing test bundle: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination)
    acceptance_destination = destination / pathlib.Path(*ACCEPTANCE_RELATIVE.parts)
    acceptance_destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(acceptance_source, acceptance_destination)


def write_manifest(path: pathlib.Path, manifest: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, required=True, help="release root containing atmosphere/")
    parser.add_argument("--manifest", type=pathlib.Path, help="write a relative-path hash manifest")
    parser.add_argument(
        "--test-bundle",
        type=pathlib.Path,
        help="create a new standalone bundle containing the acceptance mod",
    )
    parser.add_argument(
        "--acceptance-mod",
        type=pathlib.Path,
        default=pathlib.Path(__file__).with_name("persistence_acceptance.lua"),
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args(argv)
    try:
        source_manifest = check_tree(args.out, acceptance=False)
        root_for_manifest = args.out
        if args.test_bundle:
            if not args.acceptance_mod.is_file():
                raise PreflightError(f"missing acceptance mod source: {args.acceptance_mod}")
            copy_test_bundle(args.out, args.test_bundle, args.acceptance_mod)
            source_manifest = check_tree(args.test_bundle, acceptance=True)
            root_for_manifest = args.test_bundle
        if args.manifest:
            write_manifest(args.manifest, source_manifest)
        print("CONSOLE_BUNDLE_PREFLIGHT_OK")
        print(f"title_id={TITLE_ID}")
        print(f"nso_sha256={source_manifest['nso']['sha256']}")
        print(f"persistence_acceptance={str(source_manifest['checks']['persistence_acceptance_mod']).lower()}")
        if args.test_bundle:
            print(f"test_bundle={root_for_manifest}")
        if args.manifest:
            print(f"manifest={args.manifest}")
        return 0
    except (OSError, PreflightError) as exc:
        print(f"CONSOLE_BUNDLE_PREFLIGHT_FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
