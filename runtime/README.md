# Repentance Switch runtime injector

This is the first-stage `subsdk9` loader for title `010021C000B6A000`.  It does
not patch gameplay yet.  On load it initializes exlaunch, checks the
main-module fingerprint belonging to Build ID
`b6e5bdb9dc12e1d1a25cbfda17f4be24b4754ef5`, and emits the
`[isaac-port] SAFE_INIT_READY subsdk9` debug marker.  It then replaces only the
direct `BL` at `main+0x558`, immediately before the original call to the
Repentance entry point.  A mismatched main module or call-site instruction
causes an immediate no-op.

The late wrapper reads the already-relocated target from `main+0x10cc78`, checks
the `run_repentance` prologue at Repentance NRO RVA `0x4c0840` (pinned Build ID
`91c73fdd575061318d68886316afeac72388b2ab`), runs the Lua/FFI smoke once, and
then calls the untouched original PLT entry at `main+0x863b0`.  If NRO
validation or the smoke fails, it skips port initialization but still chains to
the original game entry point.

After validating the loaded NRO, the wrapper also checks and installs a
trampoline at `Manager::Update` RVA `0x3f8db8`.  On the first update where
`g_Game` is live, it reads the engine frame counter at `g_Game+0x24f99c` and
calls the pinned read-only `Manager::GameSelectorGameId()` at RVA `0x3fb550`.
Success emits `ENGINE_SMOKE_READY`; this deliberately waits for a real game
tick instead of dereferencing engine state before `run_repentance` initializes
it.

The same pinned gate installs a trampoline at `Game::Update` RVA `0x351884`.
After the original update returns, callback ID 1 (`MC_POST_UPDATE`) is passed to
the stock `__ProcessCallback` dispatcher whenever Lua called
`L_EnableCallback(1)`. Thus the embedded micro mod is exercised once manually
during bootstrap and then from a real engine update point. On that first real
dispatch it calls stock `Isaac.GetFrameCount()` through the implemented
`LL_Isaac__GetFrameCount` FFI symbol and asserts that live engine state is
available.

On the first live `Manager::Update`, the injector also verifies the exported
`g_Manager`, derives its embedded `ModManager` at offset `0x36800`, assigns the
RomFS-relative mod paths to `mods/`, and calls the surviving stock
`ModManager::ListMods()` and `ModManager::LoadConfigs()`. Both entry points are
covered by the same pinned code-signature gate. The hardware log markers are
`MOD_MANAGER_SCAN_BEGIN`, `MOD_MANAGER_LIST_READY`, and
`MOD_MANAGER_CONFIG_READY`.  Only after that point the runtime executes the
real embedded `mods/repentanceplus/main.lua`, so dynamically assigned config
IDs already exist. `REPENTANCE_PLUS_READY` confirms the complete top-level
chunk; `REPENTANCE_PLUS_FAIL` is accompanied by the exact Lua error.

The bootstrap now includes direct, signature-gated ARM64 bridges for the
engine RNG and ANM2 constructor/load/play/destructor path. Item, trinket, card,
pill, sound and challenge names are resolved from the live vectors populated
by `LoadConfigs`; explicit entity IDs are generated deterministically from the
mod's `entities2.xml`. The retail API-v1 callback overwrite bug is also avoided
with unique registrations. Callback dispatch beyond `MC_POST_UPDATE` remains
the main incomplete runtime area.

The Switch loader does not expose the NSO header's Build ID directly to an
injected module.  Therefore the runtime gate logs the pinned Build ID and
verifies its associated mapped text/rodata/data sizes.  This is deliberately a
conservative first gate; a later loader integration can add a true NSO-header
query if the target runtime exposes one.

## Build in the official container

The image is `devkitpro/devkita64:20260219`:

```sh
podman pull docker.io/devkitpro/devkita64:20260219
./runtime/build-container.sh
```

For a native devkitPro shell, set `DEVKITPRO` and run:

```sh
./runtime/build.sh
```

Only `runtime/out/subsdk9` and its ready-to-copy Atmosphere tree are
copied out; the generated NPDM is an
internal build input and is not a production artifact.  The build deterministically
embeds all 15 stock `scripts_v2` files and all 53 Repentance Plus Lua files. At
late init the persistent state uses
the game's initialized `malloc`/`realloc`/`free`, opens standard libraries, loads
`ffi`, resolves the whitelisted `IsaacPortSmoke` C function and checks `40 + 2 == 42`.
It then installs an embedded `include`, loads stock `main.lua`, and runs a micro
mod through `RegisterMod`, `AddCallback`, and `__ProcessCallback`. The first real
ABI functions are `L_DebugString`, `L_EnableCallback`, and
`LL_Isaac__GetFrameCount`; success emits
`STOCK_API_READY embedded_files=68 micro_mod=ok`. Every embedded Repentance
Plus Lua file is also compiled (without executing gameplay code yet), and
success emits `MOD_SOURCES_READY count=53`.

The same build packages the runtime mod inputs in two RomFS layouts. The full
loose mod is placed under
`romfs/mods/repentanceplus/` for the surviving stock `ModManager`, while
`resources/` and `resources-dlc3/` are mirrored into
`romfs/rp_patch/resources/`, a mount point referenced directly by this
Repentance build. This duplicates resource files intentionally: the first tree
preserves normal mod-relative lookup and the second exposes assets through the
stock content mount before Lua script loading has been restored.

Deploy the resulting `out/atmosphere/` tree to the SD root. Keep the existing
`subsdk0`, `subsdk1` and the game's original `main.npdm` untouched.

The reproducible container build currently produces:

```text
sha256  42dcabc77f62a8169ff8ccae9f4132fd30a88f57dd689c1000acd526fe27472a  out/subsdk9
```

Do **not** deploy the `main.npdm` temporarily generated inside
`.build/exlaunch-stage/deploy/`. It comes from exlaunch's qlaunch template and
has applet/service permissions that do not match Isaac. The original Isaac
NPDM already allows the SVCs used by this stage, debug output and debug SD-card
access, so the release output intentionally contains only `subsdk9`.

The pinned exlaunch source is vendored at
`runtime/vendor/exlaunch` (commit `f9f4b0dd07b68f97958cb9c79228bbca22ca80d5`).
