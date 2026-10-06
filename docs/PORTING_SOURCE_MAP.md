# Porting source map (audit 2026-10-06)

This document is the operational map for the local reference material. The
checkouts under `../porting-reference-repositories` are analysis inputs only;
none is a runtime or release dependency.

## Kept repositories

| Repository | Use now | Next use | Excluded from build/release |
|---|---|---|---|
| `REPENTOGON` | Read `libzhl/functions/*.zhl` and callback/Lua engine descriptions for ABI evidence | Generate callback map and resolve the first frontier blocker | PC hook/patch implementation and the checkout itself |
| `repentogxm` | Compare the recording-proxy startup strategy and ARM Lua bridge notes | Validate our exact Repentance Plus startup transcript | Vita/recomp backend and binaries |
| `TestMod` | Behavioral reference for selected vanilla API checks | Rewrite small original smoke tests | Upstream test source and assets |
| `isaacscript` | Names, enums and typed definitions from both definition trees | Add evidence to unified ABI coverage | TypeScript runtime, npm tree and generated package |
| `IsaacDocs` | Human-readable behavior and edge-case reference | Resolve ambiguous API semantics | Copied prose |
| `isaac-chapi` | Compare CHAPI workload/save-load/damage behavior | Isolated CHAPI 0.946 fixture | Upstream implementation and 0.967 replacement |
| `ghidra` | Source/docs reference only | Install a separate pinned binary and create BSim database | Source checkout and databases |
| `Ghidra-Switch-Loader` | Loader and `Dump*.java` scripts | Import target ELF/NRO and produce local dumps | Extension and dump artifacts |
| `sys-gdbstub` | Debugger workflow | Verify unresolved ARM64 ABI/layout questions on hardware | sysmodule/debugger in release |

Pinned commits are recorded in the parent
[`porting-reference-repositories/README.md`](../../porting-reference-repositories/README.md).

## Current outputs and provenance

- `analysis/api-usage/api-usage.json`: static census from `repentanceplus/**/*.lua`.
- `analysis/api-usage/native-bridge.json` and `.md`: closure of the stock
  Switch Lua `cdefs.lua`/FFI boundary.
- `runtime/tests/oracle/recording_oracle.lua` plus
  `runtime/tests/test-recording-oracle.sh`: host recording harness; it writes
  `analysis/api-usage/runtime-frontier.json`. The current host run reaches
  `host_bootstrap_complete`, observes 123 callbacks and 391 operations, and
  produces a frontier of about 60 KB. This remains host evidence only;
  `switch_readiness: not_claimed` and it does not prove console compatibility.
- `analysis/abi/coverage.json`: generated work queue merging usage, frontier,
  REPENTOGON ZHL and IsaacScript evidence. Unresolved Switch status is
  intentional until an RVA or hardware observation exists.
- `analysis/abi/status.json`: generated inventory of current resolver,
  wrappers, hooks, markers, build IDs and verification levels.

The first `Isaac.LoadModData`/`SaveModData` blocker is currently covered by a
session-only backend. It unblocks the host startup path, but durable save/load
semantics are still unresolved and must not be presented as complete.

Planned outputs are `analysis/abi/callback-map.json`,
`analysis/abi/switch-matches.json`, `runtime/tests/vanilla_smoke.lua` and
`runtime/tests/chapi/`. They must not be described as complete until their
generators/tests exist. Local ELF/NRO/NSO, PC executable, Ghidra databases,
NSP/NSZ, dump files and absolute local paths are never public release inputs.

## Execution boundary

The next implementation loop is: keep the `host_bootstrap_complete` recorder result
as a regression baseline, select the next unresolved frontier/API blocker,
implement the smallest compatibility boundary, run host regression, then
record again. Durable save/load remains an explicit follow-up blocker, separate
from the session-only backend. CHAPI and vanilla smoke tests remain separate
fixtures. Ghidra/BSim and sys-gdbstub are deferred until a blocker needs native
evidence; they do not justify copying their large source trees into the public
repo.

## Already discarded / safe cleanup guidance

The old duplicate material under `switch-port/reference/upstream/` has been
removed in favor of the canonical checkouts. `repentogon-luajit`,
`switchidaproloader`, `SaltyNX`, `skyline-rs` and `switch-homebrew` were
inspected and intentionally not retained because they duplicate the current
LuaJIT/exlaunch/Ghidra path or are not relevant to an injected module.

Do not delete parts of the nine Git checkouts, game directories, mods, NSP/NSZ
or supplied PC assets. If disk cleanup is needed, first get explicit approval
for local build caches or Ghidra databases only; no such deletion was performed
by this audit.

## Licensing boundary

REPENTOGON and repentogxm are GPLv2; IsaacScript is GPLv3. TestMod, IsaacDocs
and isaac-chapi have no clear license in these checkouts. Use all of them as
factual/behavioral references and independently rewrite code/tests/prose used
in the public project. Ghidra is Apache-2.0, Ghidra-Switch-Loader is
permissive, and sys-gdbstub is MIT; all remain external development tools.
