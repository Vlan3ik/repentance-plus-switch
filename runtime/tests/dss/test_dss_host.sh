#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
stock_root="${1:-${repo_root}/../switch-port/reference/stock-lua/dlc/resources/scripts_v2}"
mod_root="${2:-${repo_root}/../repentanceplus}"
luajit_bin="${LUAJIT_BIN:-$(command -v luajit)}"

[[ -x "${luajit_bin}" ]] || { echo "luajit not found" >&2; exit 1; }
output="$(${luajit_bin} "${repo_root}/runtime/tests/dss/bootstrap_dss.lua" "${stock_root}" "${mod_root}")"
case "${output}" in
  DSS_BOOTSTRAP_READY\ callbacks=*)
    printf '%s\n' "${output}"
    printf '%s\n' "DSS_HOST_FIXTURE_READY"
    ;;
  DSS_FIRST_MISSING\ *)
    printf '%s\n' "${output}"
    printf '%s\n' "DSS_HOST_FIXTURE_BLOCKED"
    ;;
  *)
    printf '%s\n' "${output}" >&2
    echo "DSS_HOST_FIXTURE_FAILED" >&2
    exit 1
    ;;
esac
