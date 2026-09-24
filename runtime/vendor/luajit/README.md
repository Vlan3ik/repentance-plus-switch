# LuaJIT 2.1 / Horizon ARM64 PoC

This directory pins LuaJIT upstream commit `c6ffc141a8762b41703f9287d63d93622a13dd8f` and builds a static AArch64 library with:

- LuaJIT FFI enabled;
- JIT disabled (`-DLUAJIT_DISABLE_JIT`), so the first runtime does not need writable executable memory;
- Horizon/NX OS selection (`-DLJ_TARGET_NX -DLUAJIT_OS=LUAJIT_OS_OTHER`);
- devkitA64 system allocator (`-DLUAJIT_USE_SYSMALLOC`).

Run from this directory:

```sh
./build.sh
```

The script uses the official `devkitpro/devkita64:20260219` Podman image, verifies the pinned source archive SHA-256, applies `patches/0001-nx-entropy-hook.patch`, builds `libluajit.a`, and compiles/links `smoke/nx_smoke.c` for AArch64. Artifacts are written under `build/`.

## Horizon entropy hook

Upstream LuaJIT has an NX branch in `lj_prng.c` that calls `getentropy()`. Newlib in the tested image leaves `_getentropy_r` unresolved when linking an application. The patch changes only that call to an explicit C hook:

```c
int luaJIT_nx_getentropy(void *buf, size_t len);
```

The final injected runtime must implement this hook using the Horizon/libnx CSRNG service. The smoke target supplies a link-only stub; it is not a cryptographically valid production implementation.

## ffi.C resolver

LuaJIT FFI's `ffi.C` is not a substitute for Horizon's missing POSIX `dlsym`. The final runtime should register a resolver table/bridge before executing `scripts_v2/main.lua`, with C-ABI functions such as `L_EnableCallback`, `L_Mod_SaveData`, `LL_Isaac__GetPlayer`, and `LC_Entity_Player__AddCollectible`. The stock NRO contains no literal exports with those names, so the bridge must point to validated RVA/trampoline implementations. This PoC deliberately does not fake game symbols: `smoke/nx_smoke.c` only proves that LuaJIT's static API and FFI library link for ARM64.

The pinned NX patch makes `ffi.C` call an external `luaJIT_nx_resolve(const char*)` table and makes `ffi.load(...)` fail explicitly. The smoke target maps `nx_answer` to a C function, executes `ffi.cdef`, calls `ffi.C.nx_answer(1)`, and asserts `42`; this is a real FFI call, not only a link test. The resolver must be replaced by the game bridge table, and must not depend on host `dlopen`/`dlsym`.
