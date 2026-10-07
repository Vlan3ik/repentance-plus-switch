#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/get_collectible_effect_num_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
unsigned int Native(void*, unsigned int id) { return id == 777u ? 9u : 0u; }
}

int main() {
    using namespace isaac_port::entity_player;
    alignas(void*) std::uint8_t effects[kTemporaryEffectsSize]{};
    auto native = static_cast<GetCollectibleEffectNumNative>(&Native);
    constexpr std::uintptr_t base = 0x100000u;
    static_assert(kGetCollectibleEffectNumRva == 0x4a7228u);
    static_assert(kGetCollectibleEffectNumSize == 0x68u);

    assert(InvokeGetCollectibleEffectNum(effects, 777, base, native, true) == 9u);
    assert(InvokeGetCollectibleEffectNum(effects, 778, base, native, true) == 0u);
    assert(!InvokeGetCollectibleEffectNum(nullptr, 777, base, native, true));
    assert(!InvokeGetCollectibleEffectNum(effects, 777, base, native, false));
    assert(!InvokeGetCollectibleEffectNum(effects, 777, 0, native, true));
    assert(!InvokeGetCollectibleEffectNum(
        effects, 777,
        static_cast<std::uintptr_t>(-1) - kGetCollectibleEffectNumRva + 1,
        native, true));
    assert(!InvokeGetCollectibleEffectNum(effects, 777, base, nullptr, true));
    assert(!InvokeGetCollectibleEffectNum(effects + 1, 777, base, native, true));
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/get_collectible_effect_num_test.cpp" \
    -o "$TMP_DIR/get_collectible_effect_num_test"
"$TMP_DIR/get_collectible_effect_num_test"

MAIN="$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_TemporaryEffects__GetCollectibleEffectNum' "$MAIN"
rg -q 'kTemporaryEffectsGetCollectibleEffectNumRva = 0x4a7228' "$MAIN"
rg -q 'kTemporaryEffectsGetCollectibleEffectNumSize = 0x68' "$MAIN"
rg -q 'GetCollectibleEffectNum = function' "$MAIN"
printf 'GET_COLLECTIBLE_EFFECT_NUM_HOST_READY rva=0x4a7228 size=0x68 borrowed=checked\n'
