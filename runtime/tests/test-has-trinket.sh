#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/has_trinket_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
struct FakePlayer {
    std::uint8_t padding[0x1ab0];
    std::uint32_t first;
    std::uint32_t second;
    int multiplier;
    bool has_collectible_139;
    bool has_collectible_458;
};

bool Native(void* raw, unsigned int id, bool ignore_modifiers) {
    auto* player = static_cast<FakePlayer*>(raw);
    if (!ignore_modifiers)
        return player->multiplier > 0;
    // Matches the pinned NRO's mask and slot-selection behavior: the high
    // bit is the golden modifier.  IDs 139 and 458 are the two special
    // collectibles checked by the native routine before it considers slot 2.
    if ((player->first & 0x7fffu) == id)
        return true;
    if ((player->has_collectible_139 || player->has_collectible_458) &&
        (player->second & 0x7fffu) == id)
        return true;
    return false;
}
}

int main() {
    using isaac_port::entity_player::InvokeHasTrinket;
    using isaac_port::entity_player::HasTrinketNative;
    FakePlayer player{};
    auto native = static_cast<HasTrinketNative>(&Native);
    constexpr std::uintptr_t base = 0x100000u;
    static_assert(isaac_port::entity_player::kGoldenTrinketFlag == 0x8000u);
    static_assert(isaac_port::entity_player::kTrinketIdMask == 0x7fffu);
    static_assert(isaac_port::entity_player::kHasTrinketRequiredBytes ==
                  0x1ab8u);

    // absent/held and the stock default == explicit false contract
    player.multiplier = 0;
    assert(!InvokeHasTrinket(&player, 42, false, base, native, true, true));
    player.multiplier = 1;
    assert(InvokeHasTrinket(&player, 42, false, base, native, true, true));
    assert(InvokeHasTrinket(&player, 42, false, base, native, true, true) ==
           InvokeHasTrinket(&player, 42, false, base, native, true, true));

    // ignoreModifiers=true uses direct inventory, including the golden mask.
    player.multiplier = 0;
    player.first = 42u | 0x8000u;
    assert(InvokeHasTrinket(&player, 42, true, base, native, true, true));
    assert(!InvokeHasTrinket(&player, 43, true, base, native, true, true));

    // Without either special collectible the pinned routine checks slot 1
    // only; either special collectible enables the second slot as well.
    player.first = 0;
    player.second = 77;
    player.has_collectible_139 = false;
    player.has_collectible_458 = false;
    assert(!InvokeHasTrinket(&player, 77, true, base, native, true, true));
    player.has_collectible_139 = true;
    assert(InvokeHasTrinket(&player, 77, true, base, native, true, true));
    player.has_collectible_139 = false;
    player.has_collectible_458 = true;
    assert(InvokeHasTrinket(&player, 77, true, base, native, true, true));

    // null, unmapped player, bad target/prologue and invalid module base are
    // fail-closed and must never call the native function.
    assert(!InvokeHasTrinket(nullptr, 42, false, base, native, true, true));
    assert(!InvokeHasTrinket(&player, 42, false, base, native, false, true));
    assert(!InvokeHasTrinket(&player, 42, false, base, native, true, false));
    assert(!InvokeHasTrinket(&player, 42, false, 0, native, true, true));
    assert(!InvokeHasTrinket(&player, 42, false,
                             static_cast<std::uintptr_t>(-1) - 0x28d3b8u + 1,
                             native, true, true));
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/has_trinket_test.cpp" -o "$TMP_DIR/has_trinket_test"
"$TMP_DIR/has_trinket_test"

rg -q 'IsaacPort_Entity_Player__HasTrinket' \
    "$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity_Player__HasTrinket' \
    "$ROOT_DIR/../../switch-port/reference/stock-lua/dlc/resources/scripts_v2/cdefs.lua"
printf 'HAS_TRINKET_HOST_READY rva=0x28d3b8 golden_flag=0x8000 id_mask=0x7fff\n'
