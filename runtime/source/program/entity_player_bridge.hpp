#pragma once

#include <cstddef>
#include <cstdint>

namespace isaac_port::entity_player {

/* Entity_Player::pendingCacheFlags in the pinned Repentance.nro.  This is
 * deliberately kept beside the narrow operation helper so host tests can
 * validate the 32-bit operation without fabricating an engine object. */
constexpr std::size_t kPendingCacheFlagsOffset = 0x1958;

/* Entity_Player::babySkin in the pinned Repentance.nro.  The field is a
 * signed 32-bit value at Entity_Player+0x20E8.  A failed/unsafe read uses
 * -1, matching the Lua-facing integer sentinel used by this bridge. */
constexpr std::size_t kBabySkinOffset = 0x20E8;

/* Entity_Player::temporaryEffects in the pinned Repentance.nro.  The
 * object is embedded in the player, not allocated by the Lua bridge.  Lua
 * must receive the address of this live object as a borrowed opaque pointer;
 * it must never attach an __gc finalizer or otherwise take ownership. */
constexpr std::size_t kTemporaryEffectsOffset = 0x18D8;
constexpr std::size_t kTemporaryEffectsSize = 0x30;
constexpr std::size_t kTemporaryEffectsOwnerOffset = 0x28;
constexpr std::size_t kTemporaryEffectsRequiredBytes =
    kTemporaryEffectsOffset + kTemporaryEffectsSize;

/* Keep pointer arithmetic and the host-testable identity policy separate
 * from Horizon's mapping query.  A null owner is tolerated during object
 * construction; a mapped, non-null owner must identify the player that owns
 * the embedded TemporaryEffects object. */
inline void* GetBorrowedTemporaryEffects(void* player, bool player_mapped,
                                         bool effects_mapped,
                                         bool owner_mapped, void* owner) {
    if (!player || !player_mapped || !effects_mapped)
        return nullptr;
    const auto address = reinterpret_cast<std::uintptr_t>(player);
    if ((address & (alignof(void*) - 1)) != 0 ||
        address > static_cast<std::uintptr_t>(-1) -
                      kTemporaryEffectsRequiredBytes)
        return nullptr;
    if (owner_mapped && owner && owner != player)
        return nullptr;
    return reinterpret_cast<void*>(address + kTemporaryEffectsOffset);
}

/* Entity_Player::HasTrinket(const eTrinketType, bool) in the pinned
 * Repentance.nro.  The two inventory slots are compared by the native
 * routine after masking the golden modifier bit; the actual engine call is
 * intentionally kept behind the checked resolver in main.cpp. */
constexpr std::uintptr_t kHasTrinketRva = 0x28D3B8;
constexpr std::uint32_t kGoldenTrinketFlag = 0x8000u;
constexpr std::uint32_t kTrinketIdMask = 0x7FFFu;
constexpr std::size_t kHasTrinketFirstSlotOffset = 0x1AB0;
constexpr std::size_t kHasTrinketSecondSlotOffset = 0x1AB4;
constexpr std::size_t kHasTrinketRequiredBytes =
    kHasTrinketSecondSlotOffset + sizeof(std::uint32_t);

/* Entity_Player::HasCollectible(eCollectibleType, bool) in the pinned
 * Repentance.nro.  The native routine reads several direct fields while
 * handling special collectible cases; the highest direct player access is
 * Entity_Player+0x27dc (one byte).  Safety of any pointee reached by the
 * native routine remains native/hardware behavior; this bridge guarantees
 * only that the player object is mapped through every direct access used by
 * the symbol. */
constexpr std::uintptr_t kHasCollectibleRva = 0x27D3F4;
constexpr std::size_t kHasCollectibleRequiredBytes = 0x27DD;

using HasCollectibleNative = bool (*)(void*, unsigned int, bool);

inline bool InvokeHasCollectible(void* player, unsigned int collectible,
                                 bool ignore_modifiers,
                                 std::uintptr_t module_base,
                                 HasCollectibleNative native,
                                 bool player_mapped, bool target_mapped) {
    if (!player || !module_base || !native || !player_mapped ||
        !target_mapped || module_base > static_cast<std::uintptr_t>(-1) -
                               kHasCollectibleRva)
        return false;
    return native(player, collectible, ignore_modifiers);
}

/* TemporaryEffects::HasEffect(eCollectibleType) const in the pinned
 * Repentance.nro.  This is the Lua-facing HasCollectibleEffect method.  The
 * symbol is a 0x64-byte AArch64 function at RVA 0x4a6d60 and takes the
 * borrowed TemporaryEffects object in x0 plus the collectible id in w1. */
constexpr std::uintptr_t kHasCollectibleEffectRva = 0x4A6D60;
constexpr std::size_t kHasCollectibleEffectSize = 0x64;

using HasCollectibleEffectNative = bool (*)(void*, unsigned int);

inline bool InvokeHasCollectibleEffect(
    void* effects, unsigned int collectible, std::uintptr_t module_base,
    HasCollectibleEffectNative native, bool effects_mapped) {
    if (!effects ||
        (reinterpret_cast<std::uintptr_t>(effects) & (alignof(void*) - 1)) !=
            0 ||
        !module_base || !native || !effects_mapped ||
        module_base > static_cast<std::uintptr_t>(-1) -
                           kHasCollectibleEffectRva)
        return false;
    return native(effects, collectible);
}

using HasTrinketNative = bool (*)(void*, unsigned int, bool);

/* Keep the ABI gate independent from Horizon's memory-query implementation.
 * This is the host-testable part of the wrapper: all four runtime checks are
 * supplied by main.cpp after it has verified the live NRO mapping. */
inline bool InvokeHasTrinket(void* player, unsigned int trinket,
                             bool ignore_modifiers,
                             std::uintptr_t module_base,
                             HasTrinketNative native, bool player_mapped,
                             bool target_mapped) {
    if (!player || !module_base || !native || !player_mapped ||
        !target_mapped || module_base > static_cast<std::uintptr_t>(-1) -
                               kHasTrinketRva)
        return false;
    return native(player, trinket, ignore_modifiers);
}

inline std::int32_t ReadBabySkin(void* player, bool player_mapped,
                                 bool field_mapped) {
    if (!player || !player_mapped || !field_mapped)
        return -1;
    const auto address = reinterpret_cast<std::uintptr_t>(player);
    if ((address & (alignof(void*) - 1)) != 0 ||
        address > static_cast<std::uintptr_t>(-1) - kBabySkinOffset -
                                                    sizeof(std::int32_t))
        return -1;
    const auto field = address + kBabySkinOffset;
    return *reinterpret_cast<const std::int32_t*>(field);
}

/* Entity::sprite is an embedded ANM2 object in the pinned Switch layout.  A
 * Lua GetSprite result borrows this embedded object; it must never be passed
 * to the allocating ANM2 destructor.  The host-facing helper keeps the
 * pointer calculation independent from Horizon's memory-query API so the
 * offset and null/mapping policy can be tested with a fake Entity buffer. */
constexpr std::size_t kSpritePointerOffset = 0x48;

inline void* GetBorrowedSprite(void* entity, bool entity_mapped,
                               bool sprite_mapped) {
    if (!entity || !entity_mapped || !sprite_mapped)
        return nullptr;
    const auto address = reinterpret_cast<std::uintptr_t>(entity);
    if ((address & (alignof(void*) - 1)) != 0)
        return nullptr;
    if (address > static_cast<std::uintptr_t>(-1) -
                      kSpritePointerOffset - sizeof(void*))
        return nullptr;
    return reinterpret_cast<void*>(address + kSpritePointerOffset);
}

inline void OrPendingCacheFlags(std::uint32_t* pending_flags,
                                std::uint32_t flags) {
    if (pending_flags)
        *pending_flags |= flags;
}

using EvaluateItemsNative = void (*)(void*);

/* Keep the call contract small enough to exercise on the host.  The Switch
 * wrapper supplies the two mapping results after checking Horizon memory;
 * this helper owns the null/base/target guards and guarantees one opaque
 * `this` call with no fabricated return value. */
inline bool InvokeEvaluateItems(void* player, std::uintptr_t module_base,
                                std::uintptr_t rva,
                                EvaluateItemsNative native,
                                bool player_mapped, bool target_mapped) {
    if (!player || !module_base || !native || !player_mapped ||
        !target_mapped || module_base > static_cast<std::uintptr_t>(-1) - rva)
        return false;
    native(player);
    return true;
}

} // namespace isaac_port::entity_player
