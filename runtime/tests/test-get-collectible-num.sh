#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/get_collectible_num_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
int Native(void*, unsigned int id, bool ignore_modifiers) {
    return (!ignore_modifiers && id == 123u) ? 7 : -1;
}
}

int main() {
    using namespace isaac_port::entity_player;
    alignas(void*) std::uint8_t player[kGetCollectibleNumRequiredBytes]{};
    auto native = static_cast<GetCollectibleNumNative>(&Native);
    constexpr std::uintptr_t base = 0x100000u;
    static_assert(kGetCollectibleNumRva == 0x29164cu);
    static_assert(kGetCollectibleNumSize == 0x570u);
    static_assert(kGetCollectibleNumRequiredBytes == 0x27e0u);

    // Stock Lua ABI supplies only the id; helper forwards false by contract.
    assert(InvokeGetCollectibleNum(player, 123, base, native, true) == 7);
    assert(InvokeGetCollectibleNum(player, 124, base, native, true) == -1);

    // Resolver gates fail closed without calling stale native code.
    assert(InvokeGetCollectibleNum(nullptr, 123, base, native, true) == 0);
    assert(InvokeGetCollectibleNum(player, 123, base, native, false) == 0);
    assert(InvokeGetCollectibleNum(player, 123, 0, native, true) == 0);
    assert(InvokeGetCollectibleNum(
        player, 123, static_cast<std::uintptr_t>(-1) -
        kGetCollectibleNumRva + 1, native, true) == 0);
    assert(InvokeGetCollectibleNum(player, 123, base, nullptr, true) == 0);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/get_collectible_num_test.cpp" -o "$TMP_DIR/get_collectible_num_test"
"$TMP_DIR/get_collectible_num_test"

rg -q 'LC_Entity_Player__GetCollectibleNum' "$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity_Player__GetCollectibleNum' \
    "$ROOT_DIR/../../switch-port/reference/stock-lua/dlc/resources/scripts_v2/cdefs.lua"
printf 'GET_COLLECTIBLE_NUM_HOST_READY rva=0x29164c size=0x570 required_bytes=0x27e0 default_ignore_modifiers=false\n'
