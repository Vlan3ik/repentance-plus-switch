#pragma once

#include <cstddef>
#include <cstdint>

namespace isaac_port::entity_player {

/* Entity_Player::pendingCacheFlags in the pinned Repentance.nro.  This is
 * deliberately kept beside the narrow operation helper so host tests can
 * validate the 32-bit operation without fabricating an engine object. */
constexpr std::size_t kPendingCacheFlagsOffset = 0x1958;

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
