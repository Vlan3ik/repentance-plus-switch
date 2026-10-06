# Console test bundle

The release tree is checked without adding the persistence acceptance mod:

```sh
cd /home/krl/Документы/isaac/repentance-plus-switch
python3 runtime/tests/hardware/console_bundle_preflight.py \
  --out runtime/out \
  --manifest runtime/out/console-release-manifest.json
```

To create a separate bundle for the two-launch persistence test, use a new
destination. The command refuses to overwrite an existing destination and
does not modify `runtime/out`:

```sh
python3 runtime/tests/hardware/console_bundle_preflight.py \
  --out runtime/out \
  --test-bundle /tmp/repentance-plus-console-test \
  --manifest /tmp/repentance-plus-console-test/manifest.json
```

Copy only the generated bundle's `atmosphere/` directory to the microSD root,
merging the existing `atmosphere/` directory. The expected paths are:

```text
sd:/atmosphere/contents/010021C000B6A000/exefs/subsdk9
sd:/atmosphere/contents/010021C000B6A000/romfs/mods/repentanceplus/
sd:/atmosphere/contents/010021C000B6A000/romfs/rp_patch/resources/
sd:/atmosphere/contents/010021C000B6A000/romfs/mods/rplus-persistence-acceptance/main.lua
```

Do not replace the game's existing `subsdk0`, `subsdk1`, or `main.npdm`.
Enable `rplus-persistence-acceptance` in the mod menu if necessary. Launch
the game, enter a run, and capture the normal Atmosphere/debug output. Exit
the game completely, launch it again, enter another run, and append the
second capture to the same UTF-8 log file. No IP address or network setup is
part of this procedure.

Validate the combined log on the host:

```sh
python3 runtime/tests/hardware/validate_persistence_log.py /path/to/capture.log
```

Only `PERSISTENCE_ACCEPTANCE_VALIDATED` proves the expected two-launch
sequence. The acceptance bundle is deliberately not part of the release
package.
