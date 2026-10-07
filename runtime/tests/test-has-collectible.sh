#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/has_collectible_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
bool Native(void*, unsigned int id, bool ignore_modifiers) {
    return ignore_modifiers && id == 123u;
}
}

int main() {
    using isaac_port::entity_player::HasCollectibleNative;
    using isaac_port::entity_player::InvokeHasCollectible;
    alignas(void*) std::uint8_t player[0x27dd]{};
    auto native = static_cast<HasCollectibleNative>(&Native);
    constexpr std::uintptr_t base = 0x100000u;
    static_assert(isaac_port::entity_player::kHasCollectibleRva == 0x27d3f4u);
    static_assert(isaac_port::entity_player::kHasCollectibleRequiredBytes ==
                  0x27ddu);

    // Host helper forwards the native ABI including the optional flag.
    assert(InvokeHasCollectible(player, 123, true, base, native, true, true));
    assert(!InvokeHasCollectible(player, 123, false, base, native, true, true));
    assert(!InvokeHasCollectible(player, 124, true, base, native, true, true));

    // Every resolver gate is fail-closed and must not call a stale target.
    assert(!InvokeHasCollectible(nullptr, 123, true, base, native, true, true));
    assert(!InvokeHasCollectible(player, 123, true, base, native, false, true));
    assert(!InvokeHasCollectible(player, 123, true, base, native, true, false));
    assert(!InvokeHasCollectible(player, 123, true, 0, native, true, true));
    assert(!InvokeHasCollectible(
        player, 123, true, static_cast<std::uintptr_t>(-1) -
        isaac_port::entity_player::kHasCollectibleRva + 1,
        native, true, true));
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/has_collectible_test.cpp" -o "$TMP_DIR/has_collectible_test"
"$TMP_DIR/has_collectible_test"

rg -q 'LC_Entity_Player__HasCollectible' \
    "$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity_Player__HasCollectible' \
    "$ROOT_DIR/../../switch-port/reference/stock-lua/dlc/resources/scripts_v2/cdefs.lua"
printf 'HAS_COLLECTIBLE_HOST_READY rva=0x27d3f4 required_bytes=0x27dd default_ignore_modifiers=false\n'
