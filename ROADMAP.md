# Repentance Plus — native Nintendo Switch port

Target title: `010021C000B6A000`  
Target update main Build ID: `b6e5bdb9dc12e1d1a25cbfda17f4be24b4754ef5`

The finished port runs inside the Switch title under Atmosphere. A PC may be
used to build and inspect it, but is never part of the runtime and no video or
input streaming is allowed.

## Confirmed facts

- The actual game is the runtime-loaded `rom:/.nro/Repentance.nro`.
- Switch retains `ModManager`, the Mods menu, `ListMods`, XML configuration and
  resource redirection.
- `RunModScripts` and `RunModScript` are deliberate stubs and the Lua VM is not
  linked into the Switch NRO.
- `RunModScripts`/`RunModScript` also have no direct code xrefs in the pinned
  NRO, so replacing those stubs does not restore callbacks by itself.
- DLC RomFS nevertheless ships a complete `resources/scripts_v2` API layer.
  It expects LuaJIT FFI and a 531-function `L_*`/`LL_*`/`LC_*` C ABI.
- Repentance Plus uses 43 callbacks. Its exact high-level API inventory is in
  `analysis/api-usage/` and will be reduced to the required native ABI closure.

## Milestones

1. **Injector boots**
   - build a pinned exlaunch `subsdk9`;
   - validate the main Build ID before modifying memory;
   - emit an SD/debug log marker and leave the unmodified game bootable.

2. **Lua hello world**
   - embed ARM64 LuaJIT in interpreter mode with FFI enabled;
   - provide a Horizon-compatible `ffi.C` symbol resolver;
   - run a bundled script from the injected module on the game thread.

3. **Stock API bootstrap**
   - expose the core bridge (`L_DebugString`, random, mod storage and callback
     registration);
   - load the shipped `scripts_v2/main.lua`;
   - run a tiny `RegisterMod` test mod.

4. **Game object bridge**
   - implement the native ABI closure actually used by Repentance Plus;
   - call game functions by checked RVAs relative to the loaded Repentance NRO;
   - validate opaque handles and struct layouts at every boundary.

5. **Callbacks and resources**
   - hook the 43 required event points and dispatch on the game thread;
   - reuse `ModManager::ListMods`/`LoadConfigs` for XML and resource merging;
   - mount/load Repentance Plus from the Atmosphere content tree.

6. **Hardware bring-up**
   - boot-test each milestone on the user's Switch;
   - collect crash reports and logs, fix ABI/layout differences;
   - package the final `atmosphere/contents/010021C000B6A000/` tree.

## Current implementation

- Milestone 1 is built: main fingerprint, CRC32 and call-site instruction are
  gated before patching `main+0x558`.
- Milestone 2 is built but still awaits hardware execution: ARM64 LuaJIT with
  JIT disabled and FFI enabled runs at the post-NRO-load boundary.
- The 15 stock `scripts_v2` files are embedded deterministically. Their
  `main.lua` plus a `RegisterMod`/`AddCallback` micro mod are loaded through a
  native `include()` implementation.
- `Manager::Update` and `Game::Update` have pinned trampoline hooks. The former
  performs the first read-only engine smoke; the latter dispatches
  `MC_POST_UPDATE` through stock `__ProcessCallback`.
- The loaded DLC NRO is checked against its `NRO0` header and full 32-byte
  Build ID before any of its RVAs are used.
- All 53 Repentance Plus Lua sources are embedded and syntax-compiled during
  bootstrap. The build also packages the mod's XML/scripts/assets under
  `romfs/mods/repentanceplus/` and mirrors its resources into the stock
  `romfs/rp_patch/resources/` mount.
- The first live `Manager::Update` now invokes the surviving stock
  `ModManager::ListMods` and `LoadConfigs` using the verified
  `g_Manager+0x36800` instance and the packaged `mods/` tree. Hardware must
  confirm the content-manager path and resulting XML ID allocation.
- The ready-to-copy package is generated at
  `runtime/out/atmosphere/contents/010021C000B6A000/`; no generated qlaunch
  NPDM is included.

The PC executable is not currently required. It becomes a blocker only if a
necessary binding or callback contract cannot be reconstructed from the Switch
symbols, stock `scripts_v2`, REPENTOGON and the open ARM reference port.
