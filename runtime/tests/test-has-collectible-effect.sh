#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/has_collectible_effect_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
bool Native(void*, unsigned int id) { return id == 777u; }
}

int main() {
    using namespace isaac_port::entity_player;
    alignas(void*) std::uint8_t effects[kTemporaryEffectsSize]{};
    auto native = static_cast<HasCollectibleEffectNative>(&Native);
    constexpr std::uintptr_t base = 0x100000u;
    static_assert(kHasCollectibleEffectRva == 0x4a6d60u);
    static_assert(kHasCollectibleEffectSize == 0x64u);

    assert(InvokeHasCollectibleEffect(effects, 777, base, native, true));
    assert(!InvokeHasCollectibleEffect(effects, 778, base, native, true));

    // All host-visible resolver guards fail closed and do not call Native.
    assert(!InvokeHasCollectibleEffect(nullptr, 777, base, native, true));
    assert(!InvokeHasCollectibleEffect(effects, 777, base, native, false));
    assert(!InvokeHasCollectibleEffect(effects, 777, 0, native, true));
    assert(!InvokeHasCollectibleEffect(
        effects, 777,
        static_cast<std::uintptr_t>(-1) - kHasCollectibleEffectRva + 1,
        native, true));
    assert(!InvokeHasCollectibleEffect(effects, 777, base, nullptr, true));
    assert(!InvokeHasCollectibleEffect(effects + 1, 777, base, native, true));
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/has_collectible_effect_test.cpp" \
    -o "$TMP_DIR/has_collectible_effect_test"
"$TMP_DIR/has_collectible_effect_test"

MAIN="$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_TemporaryEffects__HasCollectibleEffect' "$MAIN"
rg -q 'kTemporaryEffectsHasCollectibleEffectRva = 0x4a6d60' "$MAIN"
rg -q 'kTemporaryEffectsHasCollectibleEffectSize = 0x64' "$MAIN"
rg -q 'HasCollectibleEffect = function' "$MAIN"
printf 'HAS_COLLECTIBLE_EFFECT_HOST_READY rva=0x4a6d60 size=0x64 borrowed=checked\n'
