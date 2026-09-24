#include "lib.hpp"
#include "generated/embedded_lua.hpp"
#include "generated/mod_ids.hpp"
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
}

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <span>

namespace {

/* The NSO build-id is recorded in the update ExeFS header.  The loader does
 * not expose that header to an injected module, so the first safe gate also
 * checks the three mapped main-module segment sizes that belong to this
 * build-id.  Keeping the build-id beside the gate prevents accidentally
 * reusing this injector for another game revision. */
constexpr char kExpectedMainBuildId[] =
    "b6e5bdb9dc12e1d1a25cbfda17f4be24b4754ef5";
constexpr std::size_t kExpectedTextSize = 552944;
constexpr std::size_t kExpectedRodataSize = 523280;
constexpr std::size_t kExpectedDataSize = 31904;
constexpr unsigned int kExpectedTextCrc32 = 0x3d0b721b;

/* Pinned update call chain:
 *   main+0x558 -> main PLT+0x863b0 -> Repentance.nro+0x4c0840
 *
 * Only the direct BL in nnMain is replaced.  The original PLT/GOT entry is
 * deliberately left untouched, so the wrapper can always chain to the game. */
constexpr std::uintptr_t kRunRepentanceCallsite = 0x558;
constexpr std::uint32_t kExpectedRunRepentanceCall = 0x94021796;
constexpr std::uintptr_t kRunRepentancePlt = 0x863b0;
constexpr std::uintptr_t kRunRepentanceGot = 0x10cc78;
constexpr std::uintptr_t kRunRepentanceNroRva = 0x4c0840;
constexpr char kExpectedRepentanceBuildId[] =
    "91c73fdd575061318d68886316afeac72388b2ab";
constexpr std::uint8_t kExpectedRepentanceBuildIdBytes[32] = {
    0x91, 0xc7, 0x3f, 0xdd, 0x57, 0x50, 0x61, 0x31,
    0x8d, 0x68, 0x88, 0x63, 0x16, 0xaf, 0xea, 0xc7,
    0x23, 0x88, 0xb2, 0xab, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
constexpr std::uintptr_t kNroMagicOffset = 0x10;
constexpr std::uintptr_t kNroBuildIdOffset = 0x40;
constexpr std::uint32_t kExpectedRunRepentancePrologue[] = {
    0xd103c3ff, 0x6d072beb, 0x6d0823e9, 0xa9097bfd,
};
constexpr std::uintptr_t kManagerUpdateRva = 0x3f8db8;
constexpr std::uint32_t kExpectedManagerUpdatePrologue[] = {
    0xd10143ff, 0xa9017bfd, 0x910043fd, 0xf90013f7,
};
constexpr std::uintptr_t kModManagerListModsRva = 0x41fb0c;
constexpr std::uint32_t kExpectedModManagerListModsPrologue[] = {
    0xa9ba7bfd, 0xa9016ffc, 0x910003fd, 0xa90267fa,
};
constexpr std::uintptr_t kModManagerLoadConfigsRva = 0x41e388;
constexpr std::uint32_t kExpectedModManagerLoadConfigsPrologue[] = {
    0xd102c3ff, 0xa9057bfd, 0x910143fd, 0xa9066ffc,
};
constexpr std::uintptr_t kManagerGameSelectorGameIdRva = 0x3fb550;
constexpr std::uint32_t kExpectedManagerGameSelectorGameId[] = {
    0xb9400400, 0xd65f03c0,
};
constexpr std::uintptr_t kGameUpdateRva = 0x351884;
constexpr std::uint32_t kExpectedGameUpdatePrologue[] = {
    0xd107c3ff, 0xa9197bfd, 0x910643fd, 0xf900d3fc,
};
constexpr std::uintptr_t kGameGlobalRva = 0xabb448;
constexpr std::uintptr_t kManagerGlobalRva = 0xabcce0;
constexpr std::uintptr_t kModManagerOffset = 0x36800;
constexpr std::uintptr_t kSoundEffectsOffset = 0x364a8;
constexpr std::uintptr_t kItemConfigOffset = 0x36538;
constexpr std::uintptr_t kChallengeVectorOffset = 0x36740;
constexpr std::uintptr_t kCollectibleVectorOffset = 0x00;
constexpr std::uintptr_t kTrinketVectorOffset = 0x18;
constexpr std::uintptr_t kCardVectorOffset = 0x48;
constexpr std::uintptr_t kPillEffectVectorOffset = 0x60;
constexpr std::size_t kSoundEffectStride = 0x1f0;
constexpr std::size_t kChallengeStride = 0xf0;
constexpr std::uintptr_t kModdingDataPathRva = 0xabbc04;
constexpr std::uintptr_t kModdingSaveDataPathRva = 0xabc004;
constexpr std::size_t kModdingPathCapacity = 0x400;
constexpr std::uintptr_t kGameFrameCountOffset = 0x24f99c;
constexpr std::uintptr_t kRngSetSeedRva = 0x44e3c0;
constexpr std::uintptr_t kRngRandomIntRva = 0x44e3e8;
constexpr std::uintptr_t kRngNextRva = 0x44e464;
constexpr std::uintptr_t kRngRandomFloatRva = 0x44e4c0;
constexpr std::uintptr_t kAnm2ConstructorRva = 0x6540;
constexpr std::uintptr_t kAnm2DestructorRva = 0x71a4;
constexpr std::uintptr_t kAnm2PlayRva = 0xa1f4;
constexpr std::uintptr_t kAnm2LoadRva = 0xc970;
constexpr std::size_t kAnm2Size = 0x158;
constexpr std::uintptr_t kAnm2ScaleOffset = 0xdc;
constexpr std::uintptr_t kAnm2PlaybackSpeedOffset = 0x144;
constexpr std::uint32_t kExpectedRngSetSeedPrologue[] = {
    0xb9000001, 0xf00032e8, 0xf9416508, 0x52800189,
};
constexpr std::uint32_t kExpectedRngRandomIntPrologue[] = {
    0xa9be7bfd, 0xa9014ff4, 0x910003fd, 0xb9400008,
};
constexpr std::uint32_t kExpectedRngNextPrologue[] = {
    0xa9be7bfd, 0xf9000bf3, 0x910003fd, 0xb9400008,
};
constexpr std::uint32_t kExpectedAnm2ConstructorPrologue[] = {
    0xa9be7bfd, 0xf9000bf3, 0x910003fd, 0xaa0003f3,
};
constexpr std::uint32_t kExpectedAnm2DestructorPrologue[] = {
    0xa9be7bfd, 0xf9000bf3, 0x910003fd, 0xaa0003f3,
};
constexpr std::uint32_t kExpectedAnm2PlayPrologue[] = {
    0xa9bd7bfd, 0xa90157f6, 0x910003fd, 0xa9024ff4,
};
constexpr std::uint32_t kExpectedAnm2LoadPrologue[] = {
    0xa9ba7bfd, 0xf9000bfb, 0x910003fd, 0xa90267fa,
};
constexpr std::uintptr_t kMainMallocRva = 0x7d2b0;
constexpr std::uintptr_t kMainFreeRva = 0x7d300;
constexpr std::uintptr_t kMainReallocRva = 0x7d3a0;

std::uintptr_t g_repentance_base = 0;
lua_State* g_lua_state = nullptr;
bool g_post_update_enabled = false;
bool g_mod_manager_config_ready = false;
bool g_repentance_plus_started = false;

struct LuaRng {
    std::uint32_t seed;
    std::uint32_t shift[3];
};
static_assert(sizeof(LuaRng) == 16);

struct LuaVector2 {
    float x;
    float y;
};
static_assert(sizeof(LuaVector2) == 8);

struct NativeVector {
    std::uintptr_t begin;
    std::uintptr_t end;
    std::uintptr_t capacity;
};
static_assert(sizeof(NativeVector) == 24);

struct NativeLuaCallback {
    std::int32_t callback;
    std::uint32_t padding;
    std::uintptr_t arguments[8];
};
static_assert(sizeof(NativeLuaCallback) == 72);

struct MainFingerprint {
    std::size_t text;
    std::size_t rodata;
    std::size_t data;
};

MainFingerprint GetMainFingerprint() {
    const auto& main = exl::util::GetMainModuleInfo();
    return {main.m_Text.m_Size, main.m_Rodata.m_Size, main.m_Data.m_Size};
}

unsigned int GetMainTextCrc32(const MainFingerprint& fingerprint) {
    const auto* text = reinterpret_cast<const char*>(
        exl::util::GetMainModuleInfo().m_Text.m_Start);
    return exl::util::Crc32::Hash(
        std::span<const char>(text, fingerprint.text));
}

bool MatchesTargetBuild(const MainFingerprint& fingerprint,
                        unsigned int text_crc32) {
    return fingerprint.text == kExpectedTextSize &&
           fingerprint.rodata == kExpectedRodataSize &&
           fingerprint.data == kExpectedDataSize &&
           text_crc32 == kExpectedTextCrc32;
}

using RunRepentanceFn = void (*)();

RunRepentanceFn GetOriginalRunRepentancePlt() {
    const auto main_base = exl::util::GetMainModuleInfo().m_Total.m_Start;
    return reinterpret_cast<RunRepentanceFn>(main_base + kRunRepentancePlt);
}

bool ValidateLoadedRepentance(std::uintptr_t target,
                              std::uintptr_t* module_base_out) {
    if (target < kRunRepentanceNroRva)
        return false;

    /* exlaunch snapshots static modules during its own startup, before Isaac
     * loads the DLC NRO. Query Horizon's current mappings instead of relying
     * on that intentionally stale module table. */
    MemoryInfo memory{};
    u32 page_info = 0;
    if (R_FAILED(svcQueryMemory(&memory, &page_info, target)) ||
        memory.perm != Perm_Rx || target < memory.addr ||
        target + sizeof(kExpectedRunRepentancePrologue) < target ||
        target + sizeof(kExpectedRunRepentancePrologue) >
            memory.addr + memory.size)
        return false;

    if (std::memcmp(reinterpret_cast<const void*>(target),
                    kExpectedRunRepentancePrologue,
                    sizeof(kExpectedRunRepentancePrologue)) != 0)
        return false;

    const auto base = target - kRunRepentanceNroRva;
    if (base < memory.addr || base >= memory.addr + memory.size)
        return false;

    const std::uint32_t expected_magic = 0x304f524e; // "NRO0"
    if (base + kNroBuildIdOffset + sizeof(kExpectedRepentanceBuildIdBytes) <
            base ||
        base + kNroBuildIdOffset + sizeof(kExpectedRepentanceBuildIdBytes) >
            memory.addr + memory.size ||
        std::memcmp(reinterpret_cast<const void*>(base + kNroMagicOffset),
                    &expected_magic, sizeof(expected_magic)) != 0 ||
        std::memcmp(reinterpret_cast<const void*>(base + kNroBuildIdOffset),
                    kExpectedRepentanceBuildIdBytes,
                    sizeof(kExpectedRepentanceBuildIdBytes)) != 0)
        return false;

    *module_base_out = base;
    return true;
}

bool MatchesCode(std::uintptr_t address, const void* expected,
                 std::size_t expected_size) {
    MemoryInfo memory{};
    u32 page_info = 0;
    return R_SUCCEEDED(svcQueryMemory(&memory, &page_info, address)) &&
           memory.perm == Perm_Rx && address >= memory.addr &&
           address + expected_size >= address &&
           address + expected_size <= memory.addr + memory.size &&
           std::memcmp(reinterpret_cast<const void*>(address), expected,
                       expected_size) == 0;
}

bool IsMappedDataRange(std::uintptr_t address, std::size_t size,
                       bool require_write) {
    MemoryInfo memory{};
    u32 page_info = 0;
    if (address + size < address ||
        R_FAILED(svcQueryMemory(&memory, &page_info, address)) ||
        address < memory.addr || address + size > memory.addr + memory.size)
        return false;
    return require_write ? memory.perm == Perm_Rw
                         : (memory.perm == Perm_Rw || memory.perm == Perm_R);
}

void* GetLiveManager() {
    if (!g_repentance_base)
        return nullptr;
    const auto address = g_repentance_base + kManagerGlobalRva;
    if (address < g_repentance_base ||
        !IsMappedDataRange(address, sizeof(void*), false))
        return nullptr;
    return *reinterpret_cast<void* const*>(address);
}

bool NativeStringEquals(const void* object, const char* expected) {
    if (!object || !expected ||
        !IsMappedDataRange(reinterpret_cast<std::uintptr_t>(object), 24,
                           false))
        return false;

    const auto* bytes = reinterpret_cast<const std::uint8_t*>(object);
    const bool is_long = (bytes[0] & 1) != 0;
    std::size_t size = 0;
    const char* data = nullptr;
    if (is_long) {
        std::memcpy(&size, bytes + 8, sizeof(size));
        std::memcpy(&data, bytes + 16, sizeof(data));
    } else {
        size = bytes[0] >> 1;
        data = reinterpret_cast<const char*>(bytes + 1);
    }

    const std::size_t expected_size = std::strlen(expected);
    return size == expected_size && size <= 4096 && data &&
           IsMappedDataRange(reinterpret_cast<std::uintptr_t>(data), size,
                             false) &&
           std::memcmp(data, expected, size) == 0;
}

bool ReadNativeVector(std::uintptr_t address, std::size_t stride,
                      NativeVector* vector, std::size_t* count) {
    if (!vector || !count || stride == 0 ||
        !IsMappedDataRange(address, sizeof(*vector), false))
        return false;
    std::memcpy(vector, reinterpret_cast<const void*>(address),
                sizeof(*vector));
    if (vector->end < vector->begin ||
        (vector->end - vector->begin) % stride != 0)
        return false;
    *count = (vector->end - vector->begin) / stride;
    return *count <= 65536 &&
           (*count == 0 || IsMappedDataRange(
                               vector->begin, *count * stride, false));
}

int LookupPointerConfigVector(std::uintptr_t vector_address,
                              std::size_t id_offset, const char* name) {
    NativeVector vector{};
    std::size_t count = 0;
    if (!ReadNativeVector(vector_address, sizeof(void*), &vector, &count))
        return 0;

    const auto* entries = reinterpret_cast<void* const*>(vector.begin);
    for (std::size_t index = 0; index < count; ++index) {
        const auto entry = reinterpret_cast<std::uintptr_t>(entries[index]);
        if (!entry || !IsMappedDataRange(entry, id_offset + sizeof(int),
                                         false) ||
            !NativeStringEquals(reinterpret_cast<const void*>(entry + 8),
                                name))
            continue;
        return *reinterpret_cast<const int*>(entry + id_offset);
    }
    return 0;
}

int LookupInlineConfigVector(std::uintptr_t vector_address,
                             std::size_t stride, std::size_t name_offset,
                             std::size_t id_offset, const char* name) {
    NativeVector vector{};
    std::size_t count = 0;
    if (!ReadNativeVector(vector_address, stride, &vector, &count))
        return 0;
    for (std::size_t index = 0; index < count; ++index) {
        const auto entry = vector.begin + index * stride;
        if (NativeStringEquals(
                reinterpret_cast<const void*>(entry + name_offset), name))
            return *reinterpret_cast<const int*>(entry + id_offset);
    }
    return 0;
}

bool InitializeStockModManager(void* hook_manager) {
    const auto manager_global = g_repentance_base + kManagerGlobalRva;
    const auto data_path = g_repentance_base + kModdingDataPathRva;
    const auto save_path = g_repentance_base + kModdingSaveDataPathRva;
    if (manager_global < g_repentance_base || data_path < g_repentance_base ||
        save_path < g_repentance_base ||
        !IsMappedDataRange(manager_global, sizeof(void*), false) ||
        !IsMappedDataRange(data_path, kModdingPathCapacity, true) ||
        !IsMappedDataRange(save_path, kModdingPathCapacity, true))
        return false;

    auto* live_manager = *reinterpret_cast<void* const*>(manager_global);
    if (!live_manager || live_manager != hook_manager)
        return false;

    const auto mod_manager_address =
        reinterpret_cast<std::uintptr_t>(live_manager) + kModManagerOffset;
    if (mod_manager_address < reinterpret_cast<std::uintptr_t>(live_manager) ||
        !IsMappedDataRange(mod_manager_address, 3 * sizeof(void*), true))
        return false;

    /* IContentManager paths are relative to the game's RomFS mounts.  Keep
     * the secondary path inside the same read-only tree until the native mod
     * save API is restored; ListMods uses it to form ModEntry paths. */
    constexpr char kModPath[] = "mods/";
    std::memset(reinterpret_cast<void*>(data_path), 0, kModdingPathCapacity);
    std::memset(reinterpret_cast<void*>(save_path), 0, kModdingPathCapacity);
    std::memcpy(reinterpret_cast<void*>(data_path), kModPath,
                sizeof(kModPath));
    std::memcpy(reinterpret_cast<void*>(save_path), kModPath,
                sizeof(kModPath));

    using ModManagerFn = void (*)(void*);
    const auto list_mods = reinterpret_cast<ModManagerFn>(
        g_repentance_base + kModManagerListModsRva);
    const auto load_configs = reinterpret_cast<ModManagerFn>(
        g_repentance_base + kModManagerLoadConfigsRva);
    auto* mod_manager = reinterpret_cast<void*>(mod_manager_address);

    Logging.Log(
        "[isaac-port] MOD_MANAGER_SCAN_BEGIN manager=%p path=%s",
        mod_manager, kModPath);
    list_mods(mod_manager);
    Logging.Log("[isaac-port] MOD_MANAGER_LIST_READY");
    load_configs(mod_manager);
    Logging.Log("[isaac-port] MOD_MANAGER_CONFIG_READY");
    return true;
}

bool ReadGameFrameCount(int* frame_out) {
    if (!g_repentance_base)
        return false;

    const auto game_global = g_repentance_base + kGameGlobalRva;
    if (game_global < g_repentance_base)
        return false;

    MemoryInfo global_memory{};
    u32 global_page_info = 0;
    if (R_FAILED(svcQueryMemory(&global_memory, &global_page_info,
                                game_global)) ||
        (global_memory.perm != Perm_Rw && global_memory.perm != Perm_R) ||
        game_global < global_memory.addr ||
        game_global + sizeof(void*) < game_global ||
        game_global + sizeof(void*) >
            global_memory.addr + global_memory.size)
        return false;

    auto* game = *reinterpret_cast<void* const*>(game_global);
    if (!game)
        return false;

    const auto address = reinterpret_cast<std::uintptr_t>(game) +
                         kGameFrameCountOffset;
    MemoryInfo memory{};
    u32 page_info = 0;
    if (R_FAILED(svcQueryMemory(&memory, &page_info, address)) ||
        (memory.perm != Perm_Rw && memory.perm != Perm_R) ||
        address < memory.addr || address + sizeof(int) < address ||
        address + sizeof(int) > memory.addr + memory.size)
        return false;

    *frame_out = *reinterpret_cast<const int*>(address);
    return true;
}

const isaac_port::embedded_lua::LuaFile* FindEmbeddedLua(const char* path) {
    if (!path)
        return nullptr;
    for (std::size_t i = 0; i < isaac_port::embedded_lua::kFileCount; ++i) {
        const auto& file = isaac_port::embedded_lua::kFiles[i];
        if (std::strcmp(file.path, path) == 0)
            return &file;
    }
    return nullptr;
}

const isaac_port::embedded_lua::LuaFile* ResolveEmbeddedInclude(
    const char* requested, char* normalized, std::size_t normalized_size) {
    if (const auto* exact = FindEmbeddedLua(requested))
        return exact;

    constexpr char kModPrefix[] = "mods/repentanceplus/";
    const std::size_t requested_size = std::strlen(requested);
    const bool has_lua_suffix =
        requested_size >= 4 &&
        std::strcmp(requested + requested_size - 4, ".lua") == 0;
    const std::size_t suffix_size = has_lua_suffix ? 0 : 4;
    if (sizeof(kModPrefix) - 1 + requested_size + suffix_size + 1 >
        normalized_size)
        return nullptr;

    std::size_t cursor = 0;
    std::memcpy(normalized, kModPrefix, sizeof(kModPrefix) - 1);
    cursor += sizeof(kModPrefix) - 1;
    for (std::size_t i = 0; i < requested_size; ++i)
        normalized[cursor++] =
            (!has_lua_suffix && requested[i] == '.') ? '/' : requested[i];
    if (!has_lua_suffix) {
        std::memcpy(normalized + cursor, ".lua", 4);
        cursor += 4;
    }
    normalized[cursor] = '\0';
    return FindEmbeddedLua(normalized);
}

int LuaInclude(lua_State* state) {
    const char* path = luaL_checkstring(state, 1);
    char normalized[256]{};
    const auto* file =
        ResolveEmbeddedInclude(path, normalized, sizeof(normalized));
    if (!file)
        return luaL_error(state, "embedded include not found: %s", path);

    char chunk_name[320] = "@";
    const std::size_t path_size = std::strlen(file->path);
    if (path_size >= sizeof(chunk_name) - 1)
        return luaL_error(state, "embedded include path too long: %s", path);
    std::memcpy(chunk_name + 1, file->path, path_size + 1);

    if (luaL_loadbuffer(state, reinterpret_cast<const char*>(file->bytes),
                        file->size, chunk_name) != 0)
        return lua_error(state);
    lua_call(state, 0, LUA_MULTRET);
    return lua_gettop(state) - 1;
}

void* GameLuaAllocator(void*, void* old_ptr, std::size_t,
                       std::size_t new_size) {
    const auto main_base = exl::util::GetMainModuleInfo().m_Total.m_Start;
    const auto game_malloc = reinterpret_cast<void* (*)(std::size_t)>(
        main_base + kMainMallocRva);
    const auto game_free = reinterpret_cast<void (*)(void*)>(
        main_base + kMainFreeRva);
    const auto game_realloc = reinterpret_cast<void* (*)(void*, std::size_t)>(
        main_base + kMainReallocRva);

    if (new_size == 0) {
        game_free(old_ptr);
        return nullptr;
    }
    return old_ptr ? game_realloc(old_ptr, new_size) : game_malloc(new_size);
}

void* GameAllocate(std::size_t size) {
    const auto main_base = exl::util::GetMainModuleInfo().m_Total.m_Start;
    return reinterpret_cast<void* (*)(std::size_t)>(
        main_base + kMainMallocRva)(size);
}

void GameFree(void* pointer) {
    const auto main_base = exl::util::GetMainModuleInfo().m_Total.m_Start;
    reinterpret_cast<void (*)(void*)>(main_base + kMainFreeRva)(pointer);
}

/* libc++'s AArch64 std::string uses a 24-byte object.  The engine only keeps
 * this value for the duration of ANM2::Load, whose copy assignment owns the
 * resulting path.  Supplying a valid long-string view avoids importing the
 * title's C++ ABI into subsdk9. */
struct LibcppStringView {
    std::uint64_t capacity_and_long_flag;
    std::uint64_t size;
    const char* data;
};
static_assert(sizeof(LibcppStringView) == 24);

LibcppStringView MakeLibcppStringView(const char* value) {
    const std::size_t size = value ? std::strlen(value) : 0;
    return {static_cast<std::uint64_t>((size + 1) | 1),
            static_cast<std::uint64_t>(size), value ? value : ""};
}

bool RunLuaChunk(lua_State* state, const char* bytes, std::size_t size,
                 const char* chunk_name, int expected_results) {
    int status = luaL_loadbuffer(state, bytes, size, chunk_name);
    if (status == 0)
        status = lua_pcall(state, 0, expected_results, 0);
    if (status == 0)
        return true;

    const char* error = lua_tostring(state, -1);
    Logging.Log("[isaac-port] LUA_CHUNK_FAIL name=%s status=%d error=%s",
                chunk_name, status, error ? error : "unknown");
    lua_settop(state, 0);
    return false;
}

bool PreloadEmbeddedJson(lua_State* state) {
    const auto* json = FindEmbeddedLua("json.lua");
    if (!json ||
        !RunLuaChunk(state, reinterpret_cast<const char*>(json->bytes),
                     json->size, "@scripts_v2/json.lua", 1))
        return false;

    lua_getglobal(state, "package");
    lua_getfield(state, -1, "loaded");
    lua_pushvalue(state, -3);
    lua_setfield(state, -2, "json");
    lua_pop(state, 3);
    return true;
}

bool ValidateEmbeddedModScripts(lua_State* state, std::size_t* count_out) {
    constexpr char kPrefix[] = "mods/repentanceplus/";
    std::size_t count = 0;
    for (std::size_t i = 0; i < isaac_port::embedded_lua::kFileCount; ++i) {
        const auto& file = isaac_port::embedded_lua::kFiles[i];
        if (std::strncmp(file.path, kPrefix, sizeof(kPrefix) - 1) != 0)
            continue;

        char chunk_name[320] = "@";
        const std::size_t path_size = std::strlen(file.path);
        if (path_size >= sizeof(chunk_name) - 1)
            return false;
        std::memcpy(chunk_name + 1, file.path, path_size + 1);
        const int status = luaL_loadbuffer(
            state, reinterpret_cast<const char*>(file.bytes), file.size,
            chunk_name);
        if (status != 0) {
            const char* error = lua_tostring(state, -1);
            Logging.Log(
                "[isaac-port] MOD_SOURCE_FAIL name=%s status=%d error=%s",
                file.path, status, error ? error : "unknown");
            lua_settop(state, 0);
            return false;
        }
        lua_pop(state, 1);
        ++count;
    }
    lua_gc(state, LUA_GCCOLLECT, 0);
    *count_out = count;
    return count != 0;
}

bool InstallBootstrapCompatibility(lua_State* state) {
    static constexpr char kCompatibility[] = R"LUA(
local ffi = require('ffi')
ffi.cdef[[
void* IsaacPort_ANM2_Create(void);
void IsaacPort_ANM2_Destroy(void*);
void IsaacPort_ANM2_Load(void*, const char*, bool);
void IsaacPort_ANM2_Play(void*, const char*, bool);
void IsaacPort_ANM2_SetScale(void*, const Vector2*);
void IsaacPort_ANM2_GetScale(void*, Vector2*);
void IsaacPort_ANM2_SetPlaybackSpeed(void*, float);
float IsaacPort_ANM2_GetPlaybackSpeed(void*);
]]

local hud = {}
function hud:ShowItemText(...) end
function hud:ShowFortuneText(...) end
function hud:IsVisible() return true end
Game.GetHUD = function() return hud end
setmetatable(Game, { __call = function(self) return self end })

local methods = {}
function methods:Load(path, loadGraphics)
  if loadGraphics == nil then loadGraphics = true end
  ffi.C.IsaacPort_ANM2_Load(rawget(self, '__native'), path, loadGraphics)
end
function methods:Play(animation, force)
  ffi.C.IsaacPort_ANM2_Play(rawget(self, '__native'), animation, not not force)
end

local spriteMeta = {
  __index = function(self, key)
    local method = methods[key]
    if method then return method end
    local native = rawget(self, '__native')
    if key == 'Scale' then
      local value = ffi.new('Vector2')
      ffi.C.IsaacPort_ANM2_GetScale(native, value)
      return value
    elseif key == 'PlaybackSpeed' then
      return ffi.C.IsaacPort_ANM2_GetPlaybackSpeed(native)
    end
  end,
  __newindex = function(self, key, value)
    local native = rawget(self, '__native')
    if key == 'Scale' then
      ffi.C.IsaacPort_ANM2_SetScale(native, value)
    elseif key == 'PlaybackSpeed' then
      ffi.C.IsaacPort_ANM2_SetPlaybackSpeed(native, value)
    else
      rawset(self, key, value)
    end
  end,
}

function Sprite()
  local native = ffi.C.IsaacPort_ANM2_Create()
  if native == ffi.NULL then error('ANM2 allocation failed', 2) end
  native = ffi.gc(native, ffi.C.IsaacPort_ANM2_Destroy)
  return setmetatable({ __native = native }, spriteMeta)
end

-- The retail Switch script accidentally keys every API-v1 callback by the
-- callback ID, replacing earlier handlers.  Route v1 mods through the sound
-- API-v2 registry with unique keys while preserving the leading mod argument.
local stockRegisterMod = RegisterMod
local stockIsaac = Isaac
local nextCompatCallback = 0
function RegisterMod(name, apiVersion)
  local mod = stockRegisterMod(name, apiVersion)
  if apiVersion == 1 then
    -- stockRegisterMod changed this wrapper's environment to COMPAT_ENV;
    -- propagate it to the actual mod chunk as retail Isaac does directly.
    setfenv(2, getfenv(1))
    local wrappedCallbacks = {}
    function mod:AddCallback(callbackId, fn, entityId)
      local wrapped = function(...) return fn(self, ...) end
      wrappedCallbacks[fn] = wrapped
      stockIsaac.AddCallback(callbackId,
        'isaac-port-v1-' .. tostring(nextCompatCallback), wrapped,
        entityId, self)
      nextCompatCallback = nextCompatCallback + 1
    end
    function mod:AddPriorityCallback(callbackId, priority, fn, entityId)
      self:AddCallback(callbackId, fn, entityId)
    end
    function mod:RemoveCallback(callbackId, fn)
      local wrapped = wrappedCallbacks[fn]
      if wrapped then
        stockIsaac.RemoveCallback(callbackId, wrapped)
        wrappedCallbacks[fn] = nil
      end
    end
  end
  return mod
end
)LUA";
    return RunLuaChunk(state, kCompatibility, sizeof(kCompatibility) - 1,
                       "@isaac-port/bootstrap-compat.lua", 0);
}

bool RunEmbeddedRepentancePlus() {
    if (!g_lua_state || !g_mod_manager_config_ready ||
        g_repentance_plus_started)
        return false;

    g_repentance_plus_started = true;
    const auto* script =
        FindEmbeddedLua("mods/repentanceplus/main.lua");
    if (!script) {
        Logging.Log("[isaac-port] REPENTANCE_PLUS_FAIL source_missing");
        return false;
    }

    const bool ok = RunLuaChunk(
        g_lua_state, reinterpret_cast<const char*>(script->bytes),
        script->size, "@mods/repentanceplus/main.lua", 0);
    Logging.Log("[isaac-port] REPENTANCE_PLUS_%s", ok ? "READY" : "FAIL");
    return ok;
}

void DispatchLuaCallback(std::int32_t callback_id) {
    if (!g_lua_state)
        return;

    const int stack_base = lua_gettop(g_lua_state);
    lua_getglobal(g_lua_state, "__ProcessCallback");
    if (!lua_isfunction(g_lua_state, -1)) {
        lua_settop(g_lua_state, stack_base);
        return;
    }

    NativeLuaCallback callback{};
    callback.callback = callback_id;
    lua_pushlightuserdata(g_lua_state, &callback);
    const int status = lua_pcall(g_lua_state, 1, 0, 0);
    if (status != 0) {
        const char* error = lua_tostring(g_lua_state, -1);
        Logging.Log(
            "[isaac-port] LUA_CALLBACK_FAIL id=%d status=%d error=%s",
            callback_id, status, error ? error : "unknown");
    }
    lua_settop(g_lua_state, stack_base);
}

} // namespace

HOOK_DEFINE_TRAMPOLINE(ManagerUpdateHook) {
    static void Callback(void* manager) {
        Orig(manager);

        static bool mod_manager_attempted = false;
        if (!mod_manager_attempted && g_repentance_base) {
            const auto manager_global =
                g_repentance_base + kManagerGlobalRva;
            if (IsMappedDataRange(manager_global, sizeof(void*), false) &&
                *reinterpret_cast<void* const*>(manager_global) == manager) {
                mod_manager_attempted = true;
                if (!InitializeStockModManager(manager)) {
                    Logging.Log("[isaac-port] MOD_MANAGER_SCAN_FAIL");
                } else {
                    g_mod_manager_config_ready = true;
                    RunEmbeddedRepentancePlus();
                }
            }
        }

        static bool engine_smoke_logged = false;
        if (engine_smoke_logged || !g_repentance_base)
            return;

        int frame = 0;
        if (!ReadGameFrameCount(&frame))
            return;

        using GetGameIdFn = int (*)(void*);
        const auto get_game_id = reinterpret_cast<GetGameIdFn>(
            g_repentance_base + kManagerGameSelectorGameIdRva);
        const int game_id = get_game_id(manager);
        engine_smoke_logged = true;
        Logging.Log(
            "[isaac-port] ENGINE_SMOKE_READY frame=%d game_selector_id=%d",
            frame, game_id);
    }
};

HOOK_DEFINE_TRAMPOLINE(GameUpdateHook) {
    static void Callback(void* game) {
        Orig(game);
        if (g_post_update_enabled)
            DispatchLuaCallback(1); // MC_POST_UPDATE
    }
};

/* Exported Horizon SDK symbol already imported by the title's main module. */
namespace nn::os {
void GenerateRandomBytes(void* buffer, std::size_t size);
}

extern "C" int luaJIT_nx_getentropy(void* buffer, std::size_t size) {
    if (buffer == nullptr || size == 0 || size > 0x10000)
        return -1;
    nn::os::GenerateRandomBytes(buffer, size);
    return 0;
}

extern "C" int IsaacPortSmoke(int left, int right) {
    return left + right;
}

extern "C" void L_DebugString(const char* message) {
    Logging.Log("[isaac-lua] %s", message ? message : "(null)");
}

extern "C" void L_EnableCallback(unsigned int callback_id) {
    if (callback_id == 1)
        g_post_update_enabled = true;
    Logging.Log("[isaac-port] LUA_CALLBACK_ENABLED id=%u", callback_id);
}

extern "C" int LL_Isaac__GetFrameCount() {
    int frame = -1;
    ReadGameFrameCount(&frame);
    return frame;
}

int LookupItemConfigName(std::uintptr_t vector_offset, std::size_t id_offset,
                         const char* name) {
    auto* manager = GetLiveManager();
    if (!manager || !g_mod_manager_config_ready || !name)
        return 0;
    return LookupPointerConfigVector(
        reinterpret_cast<std::uintptr_t>(manager) + kItemConfigOffset +
            vector_offset,
        id_offset, name);
}

extern "C" int LL_Isaac__GetItemIdByName(const char* name) {
    return LookupItemConfigName(kCollectibleVectorOffset, 4, name);
}

extern "C" int LL_Isaac__GetTrinketIdByName(const char* name) {
    return LookupItemConfigName(kTrinketVectorOffset, 4, name);
}

extern "C" int LL_Isaac__GetCardIdByName(const char* name) {
    return LookupItemConfigName(kCardVectorOffset, 0, name);
}

extern "C" int LL_Isaac__GetPillEffectByName(const char* name) {
    return LookupItemConfigName(kPillEffectVectorOffset, 0, name);
}

extern "C" int LL_Isaac__GetSoundIdByName(const char* name) {
    auto* manager = GetLiveManager();
    if (!manager || !g_mod_manager_config_ready || !name)
        return 0;
    return LookupInlineConfigVector(
        reinterpret_cast<std::uintptr_t>(manager) + kSoundEffectsOffset,
        kSoundEffectStride, 8, 0, name);
}

extern "C" int LL_Isaac__GetChallengeIdByName(const char* name) {
    auto* manager = GetLiveManager();
    if (!manager || !g_mod_manager_config_ready || !name)
        return 0;
    const auto vector_address = reinterpret_cast<std::uintptr_t>(manager) +
                                kChallengeVectorOffset;
    NativeVector vector{};
    std::size_t count = 0;
    if (!ReadNativeVector(vector_address, kChallengeStride, &vector, &count))
        return 0;
    for (std::size_t index = 0; index < count; ++index) {
        const auto entry = vector.begin + index * kChallengeStride;
        if (NativeStringEquals(reinterpret_cast<const void*>(entry), name))
            return static_cast<int>(index);
    }
    return 0;
}

const isaac_port::mod_ids::EntityId* LookupEmbeddedEntity(const char* name) {
    if (!name)
        return nullptr;
    for (std::size_t index = 0;
         index < isaac_port::mod_ids::kEntityCount; ++index) {
        const auto& entity = isaac_port::mod_ids::kEntities[index];
        if (std::strcmp(entity.name, name) == 0)
            return &entity;
    }
    return nullptr;
}

extern "C" int LL_Isaac__GetEntityTypeByName(const char* name) {
    const auto* entity = LookupEmbeddedEntity(name);
    return entity ? entity->type : 0;
}

extern "C" int LL_Isaac__GetEntityVariantByName(const char* name) {
    const auto* entity = LookupEmbeddedEntity(name);
    return entity ? entity->variant : 0;
}

extern "C" int LL_Isaac__GetCostumeIdByPath(const char* path) {
    /* The only eager lookup in Repentance Plus is its first mod costume.
     * LoadCostumes assigns it slot zero within this ModEntry.  This keeps the
     * bootstrap moving until the full ItemConfig costume vector is exposed. */
    return path && std::strcmp(
                       path,
                       "gfx/characters/costume_004_birdofhope.anm2") == 0
               ? 0
               : -1;
}

extern "C" void LC_RNG__SetSeed(LuaRng* rng, unsigned int seed,
                                  unsigned int shift_index) {
    if (!rng || !g_repentance_base)
        return;
    reinterpret_cast<void (*)(LuaRng*, unsigned int, unsigned int)>(
        g_repentance_base + kRngSetSeedRva)(rng, seed, shift_index);
}

extern "C" unsigned int LC_RNG__RandomInt(LuaRng* rng,
                                            unsigned int maximum) {
    if (!rng || !g_repentance_base)
        return 0;
    return reinterpret_cast<unsigned int (*)(LuaRng*, unsigned int)>(
        g_repentance_base + kRngRandomIntRva)(rng, maximum);
}

extern "C" float LC_RNG__RandomFloat(LuaRng* rng) {
    if (!rng || !g_repentance_base)
        return 0.0f;
    return reinterpret_cast<float (*)(LuaRng*)>(
        g_repentance_base + kRngRandomFloatRva)(rng);
}

extern "C" unsigned int LC_RNG__Next(LuaRng* rng) {
    if (!rng || !g_repentance_base)
        return 0;
    return reinterpret_cast<unsigned int (*)(LuaRng*)>(
        g_repentance_base + kRngNextRva)(rng);
}

extern "C" void* IsaacPort_ANM2_Create() {
    if (!g_repentance_base)
        return nullptr;
    void* object = GameAllocate(kAnm2Size);
    if (!object)
        return nullptr;
    std::memset(object, 0, kAnm2Size);
    return reinterpret_cast<void* (*)(void*)>(
        g_repentance_base + kAnm2ConstructorRva)(object);
}

extern "C" void IsaacPort_ANM2_Destroy(void* object) {
    if (!object)
        return;
    if (g_repentance_base)
        reinterpret_cast<void (*)(void*)>(
            g_repentance_base + kAnm2DestructorRva)(object);
    GameFree(object);
}

extern "C" void IsaacPort_ANM2_Load(void* object, const char* path,
                                      bool load_graphics) {
    if (!object || !path || !g_repentance_base)
        return;
    const auto path_view = MakeLibcppStringView(path);
    reinterpret_cast<void (*)(void*, const LibcppStringView*, bool)>(
        g_repentance_base + kAnm2LoadRva)(object, &path_view, load_graphics);
}

extern "C" void IsaacPort_ANM2_Play(void* object, const char* animation,
                                      bool force) {
    if (!object || !animation || !g_repentance_base)
        return;
    reinterpret_cast<void (*)(void*, const char*, bool)>(
        g_repentance_base + kAnm2PlayRva)(object, animation, force);
}

extern "C" void IsaacPort_ANM2_SetScale(void* object,
                                         const LuaVector2* scale) {
    if (object && scale)
        std::memcpy(reinterpret_cast<std::uint8_t*>(object) +
                        kAnm2ScaleOffset,
                    scale, sizeof(*scale));
}

extern "C" void IsaacPort_ANM2_GetScale(void* object, LuaVector2* scale) {
    if (object && scale)
        std::memcpy(scale, reinterpret_cast<const std::uint8_t*>(object) +
                               kAnm2ScaleOffset,
                    sizeof(*scale));
}

extern "C" void IsaacPort_ANM2_SetPlaybackSpeed(void* object, float speed) {
    if (object)
        std::memcpy(reinterpret_cast<std::uint8_t*>(object) +
                        kAnm2PlaybackSpeedOffset,
                    &speed, sizeof(speed));
}

extern "C" float IsaacPort_ANM2_GetPlaybackSpeed(void* object) {
    float speed = 0.0f;
    if (object)
        std::memcpy(&speed, reinterpret_cast<const std::uint8_t*>(object) +
                                kAnm2PlaybackSpeedOffset,
                    sizeof(speed));
    return speed;
}

extern "C" void* luaJIT_nx_resolve(const char* name) {
    if (name && std::strcmp(name, "IsaacPortSmoke") == 0)
        return reinterpret_cast<void*>(&IsaacPortSmoke);
    if (name && std::strcmp(name, "L_DebugString") == 0)
        return reinterpret_cast<void*>(&L_DebugString);
    if (name && std::strcmp(name, "L_EnableCallback") == 0)
        return reinterpret_cast<void*>(&L_EnableCallback);
    if (name && std::strcmp(name, "LL_Isaac__GetFrameCount") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetFrameCount);
    if (name && std::strcmp(name, "LL_Isaac__GetItemIdByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetItemIdByName);
    if (name && std::strcmp(name, "LL_Isaac__GetTrinketIdByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetTrinketIdByName);
    if (name && std::strcmp(name, "LL_Isaac__GetCardIdByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetCardIdByName);
    if (name && std::strcmp(name, "LL_Isaac__GetPillEffectByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetPillEffectByName);
    if (name && std::strcmp(name, "LL_Isaac__GetSoundIdByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetSoundIdByName);
    if (name && std::strcmp(name, "LL_Isaac__GetChallengeIdByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetChallengeIdByName);
    if (name && std::strcmp(name, "LL_Isaac__GetEntityTypeByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetEntityTypeByName);
    if (name && std::strcmp(name, "LL_Isaac__GetEntityVariantByName") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetEntityVariantByName);
    if (name && std::strcmp(name, "LL_Isaac__GetCostumeIdByPath") == 0)
        return reinterpret_cast<void*>(&LL_Isaac__GetCostumeIdByPath);
    if (name && std::strcmp(name, "LC_RNG__SetSeed") == 0)
        return reinterpret_cast<void*>(&LC_RNG__SetSeed);
    if (name && std::strcmp(name, "LC_RNG__RandomInt") == 0)
        return reinterpret_cast<void*>(&LC_RNG__RandomInt);
    if (name && std::strcmp(name, "LC_RNG__RandomFloat") == 0)
        return reinterpret_cast<void*>(&LC_RNG__RandomFloat);
    if (name && std::strcmp(name, "LC_RNG__Next") == 0)
        return reinterpret_cast<void*>(&LC_RNG__Next);
    if (name && std::strcmp(name, "IsaacPort_ANM2_Create") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_Create);
    if (name && std::strcmp(name, "IsaacPort_ANM2_Destroy") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_Destroy);
    if (name && std::strcmp(name, "IsaacPort_ANM2_Load") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_Load);
    if (name && std::strcmp(name, "IsaacPort_ANM2_Play") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_Play);
    if (name && std::strcmp(name, "IsaacPort_ANM2_SetScale") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_SetScale);
    if (name && std::strcmp(name, "IsaacPort_ANM2_GetScale") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_GetScale);
    if (name && std::strcmp(name, "IsaacPort_ANM2_SetPlaybackSpeed") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_SetPlaybackSpeed);
    if (name && std::strcmp(name, "IsaacPort_ANM2_GetPlaybackSpeed") == 0)
        return reinterpret_cast<void*>(&IsaacPort_ANM2_GetPlaybackSpeed);
    return nullptr;
}

static bool InitializeLuaRuntime() {
    lua_State* state = lua_newstate(GameLuaAllocator, nullptr);
    if (!state) {
        Logging.Log("[isaac-port] LUA_SMOKE_FAIL newstate");
        return false;
    }

    luaL_openlibs(state);
    const char* smoke_script =
        "local ffi = require('ffi')\n"
        "ffi.cdef[[int IsaacPortSmoke(int, int);]]\n"
        "return ffi.C.IsaacPortSmoke(40, 2)\n";
    const int load_status = luaL_loadbuffer(state, smoke_script,
                                             std::strlen(smoke_script),
                                             "@isaac-port/ffi-smoke.lua");
    const int call_status = load_status == 0 ? lua_pcall(state, 0, 1, 0)
                                             : load_status;
    const bool result_ok = call_status == 0 && lua_isnumber(state, -1) &&
                           lua_tointeger(state, -1) == 42;
    if (!result_ok) {
        const char* error = lua_tostring(state, -1);
        Logging.Log("[isaac-port] LUA_SMOKE_FAIL status=%d error=%s", call_status,
                    error ? error : "unknown");
    }
    if (!result_ok) {
        lua_close(state);
        return false;
    }
    lua_pop(state, 1);

    lua_pushcfunction(state, LuaInclude);
    lua_setglobal(state, "include");

    const auto* main_script = FindEmbeddedLua("main.lua");
    if (!main_script ||
        !RunLuaChunk(state,
                     reinterpret_cast<const char*>(main_script->bytes),
                     main_script->size, "@scripts_v2/main.lua", 0)) {
        Logging.Log("[isaac-port] STOCK_API_FAIL");
        lua_close(state);
        return false;
    }

    if (!PreloadEmbeddedJson(state)) {
        Logging.Log("[isaac-port] JSON_PRELOAD_FAIL");
        lua_close(state);
        return false;
    }

    if (!InstallBootstrapCompatibility(state)) {
        Logging.Log("[isaac-port] BOOTSTRAP_COMPAT_FAIL");
        lua_close(state);
        return false;
    }

    std::size_t mod_script_count = 0;
    if (!ValidateEmbeddedModScripts(state, &mod_script_count)) {
        Logging.Log("[isaac-port] MOD_SOURCES_FAIL");
        lua_close(state);
        return false;
    }
    Logging.Log("[isaac-port] MOD_SOURCES_READY count=%zu",
                mod_script_count);

    const char* micro_mod =
        "local mod = RegisterMod('Isaac Port Smoke', 2)\n"
        "local fired = false\n"
        "local fire_count = 0\n"
        "mod:AddCallback(1, function()\n"
        "  fired = true\n"
        "  fire_count = fire_count + 1\n"
        "  if fire_count == 1 then Isaac.DebugString('micro callback fired') end\n"
        "  if fire_count == 2 then\n"
        "    local frame = Isaac.GetFrameCount()\n"
        "    assert(frame >= 0, 'engine frame unavailable')\n"
        "    Isaac.DebugString('engine callback frame ' .. frame)\n"
        "  end\n"
        "end)\n"
        "local callback = ffi.new('LuaCallback')\n"
        "callback.Callback = 1\n"
        "__ProcessCallback(callback)\n"
        "assert(fired, 'callback did not fire')\n"
        "return true\n";
    if (!RunLuaChunk(state, micro_mod, std::strlen(micro_mod),
                     "@mods/isaac-port-smoke/main.lua", 1) ||
        !lua_toboolean(state, -1)) {
        Logging.Log("[isaac-port] MICRO_MOD_FAIL");
        lua_close(state);
        return false;
    }
    lua_pop(state, 1);

    g_lua_state = state;
    Logging.Log(
        "[isaac-port] STOCK_API_READY embedded_files=%zu micro_mod=ok",
        isaac_port::embedded_lua::kFileCount);
    return true;
}

extern "C" void HookRunRepentance() {
    static bool late_init_attempted = false;
    const auto main_base = exl::util::GetMainModuleInfo().m_Total.m_Start;
    const auto target = *reinterpret_cast<const std::uintptr_t*>(
        main_base + kRunRepentanceGot);

    if (!late_init_attempted) {
        late_init_attempted = true;
        std::uintptr_t repentance_base = 0;
        const bool target_ok =
            ValidateLoadedRepentance(target, &repentance_base);

        Logging.Log(
            "[isaac-port] LATE_INIT run_target=%p repentance_build_id=%s "
            "signature=%s base=%p",
            reinterpret_cast<const void*>(target), kExpectedRepentanceBuildId,
            target_ok ? "ok" : "MISMATCH",
            reinterpret_cast<const void*>(repentance_base));

        if (target_ok) {
            const auto manager_update = repentance_base + kManagerUpdateRva;
            const auto list_mods =
                repentance_base + kModManagerListModsRva;
            const auto load_configs =
                repentance_base + kModManagerLoadConfigsRva;
            const auto get_game_id =
                repentance_base + kManagerGameSelectorGameIdRva;
            const auto game_update = repentance_base + kGameUpdateRva;
            const bool manager_signatures_ok =
                MatchesCode(manager_update, kExpectedManagerUpdatePrologue,
                            sizeof(kExpectedManagerUpdatePrologue)) &&
                MatchesCode(list_mods,
                            kExpectedModManagerListModsPrologue,
                            sizeof(kExpectedModManagerListModsPrologue)) &&
                MatchesCode(load_configs,
                            kExpectedModManagerLoadConfigsPrologue,
                            sizeof(kExpectedModManagerLoadConfigsPrologue)) &&
                MatchesCode(get_game_id,
                            kExpectedManagerGameSelectorGameId,
                            sizeof(kExpectedManagerGameSelectorGameId)) &&
                MatchesCode(game_update, kExpectedGameUpdatePrologue,
                            sizeof(kExpectedGameUpdatePrologue)) &&
                MatchesCode(repentance_base + kRngSetSeedRva,
                            kExpectedRngSetSeedPrologue,
                            sizeof(kExpectedRngSetSeedPrologue)) &&
                MatchesCode(repentance_base + kRngRandomIntRva,
                            kExpectedRngRandomIntPrologue,
                            sizeof(kExpectedRngRandomIntPrologue)) &&
                MatchesCode(repentance_base + kRngNextRva,
                            kExpectedRngNextPrologue,
                            sizeof(kExpectedRngNextPrologue)) &&
                MatchesCode(repentance_base + kRngRandomFloatRva,
                            kExpectedRngNextPrologue,
                            sizeof(kExpectedRngNextPrologue)) &&
                MatchesCode(repentance_base + kAnm2ConstructorRva,
                            kExpectedAnm2ConstructorPrologue,
                            sizeof(kExpectedAnm2ConstructorPrologue)) &&
                MatchesCode(repentance_base + kAnm2DestructorRva,
                            kExpectedAnm2DestructorPrologue,
                            sizeof(kExpectedAnm2DestructorPrologue)) &&
                MatchesCode(repentance_base + kAnm2PlayRva,
                            kExpectedAnm2PlayPrologue,
                            sizeof(kExpectedAnm2PlayPrologue)) &&
                MatchesCode(repentance_base + kAnm2LoadRva,
                            kExpectedAnm2LoadPrologue,
                            sizeof(kExpectedAnm2LoadPrologue));
            if (!manager_signatures_ok) {
                Logging.Log(
                    "[isaac-port] skipping engine hook: Manager signatures "
                    "do not match");
            } else {
                g_repentance_base = repentance_base;
                ManagerUpdateHook::InstallAtPtr(manager_update);
                GameUpdateHook::InstallAtPtr(game_update);
                Logging.Log(
                    "[isaac-port] ENGINE_HOOK_READY Manager::Update=%p "
                    "Game::Update=%p",
                    reinterpret_cast<const void*>(manager_update),
                    reinterpret_cast<const void*>(game_update));
            }

            if (InitializeLuaRuntime())
                Logging.Log("[isaac-port] LUA_SMOKE_READY result=42");
        } else {
            Logging.Log(
                "[isaac-port] skipping late init: loaded Repentance module "
                "does not match the pinned build");
        }
    }

    /* Always preserve the game's original call, even if our validation or
     * Lua smoke failed.  This calls the untouched PLT, not the patched site. */
    GetOriginalRunRepentancePlt()();
}

extern "C" void exl_main(void*, void*) {
    exl::hook::Initialize();

    const auto fingerprint = GetMainFingerprint();
    const unsigned int text_crc32 = GetMainTextCrc32(fingerprint);
    const bool matches = MatchesTargetBuild(fingerprint, text_crc32);

    Logging.Log(
        "[isaac-port] injector init title=010021C000B6A000 "
        "main_build_id=%s fingerprint=%s text=%zu rodata=%zu data=%zu crc32=%08x",
        kExpectedMainBuildId, matches ? "ok" : "MISMATCH", fingerprint.text,
        fingerprint.rodata, fingerprint.data, text_crc32);

    if (!matches) {
        Logging.Log(
            "[isaac-port] refusing hooks: main module is not the pinned "
            "Repentance update");
        return;
    }

    const auto main_base = exl::util::GetMainModuleInfo().m_Total.m_Start;
    const auto original_instruction = *reinterpret_cast<const std::uint32_t*>(
        main_base + kRunRepentanceCallsite);
    if (original_instruction != kExpectedRunRepentanceCall) {
        Logging.Log(
            "[isaac-port] refusing hook: main+0x%lx instruction=%08x "
            "expected=%08x",
            static_cast<unsigned long>(kRunRepentanceCallsite),
            original_instruction, kExpectedRunRepentanceCall);
        return;
    }

    const auto callsite = main_base + kRunRepentanceCallsite;
    const auto hook = reinterpret_cast<std::uintptr_t>(&HookRunRepentance);
    const auto branch_delta = static_cast<std::int64_t>(hook) -
                              static_cast<std::int64_t>(callsite);
    if ((branch_delta & 3) != 0 || branch_delta < -0x08000000ll ||
        branch_delta > 0x07fffffcll) {
        Logging.Log(
            "[isaac-port] refusing hook: BL target out of range delta=%ld",
            static_cast<long>(branch_delta));
        return;
    }

    exl::patch::CodePatcher patcher(kRunRepentanceCallsite);
    patcher.BranchLinkInst(reinterpret_cast<void*>(&HookRunRepentance));
    Logging.Log(
        "[isaac-port] SAFE_INIT_READY subsdk9 late_hook=main+0x%lx",
        static_cast<unsigned long>(kRunRepentanceCallsite));
}

extern "C" NORETURN void exl_exception_entry() {
    EXL_ABORT("isaac-port injector exception");
}
