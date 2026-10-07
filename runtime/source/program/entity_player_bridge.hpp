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
