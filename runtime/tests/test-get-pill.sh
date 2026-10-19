#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/get_pill_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
unsigned int Native(void*, int slot) {
    return slot == 0 ? 12u : static_cast<unsigned int>(20 + slot);
}
}

int main() {
    using namespace isaac_port::entity_player;
    alignas(void*) std::uint8_t player[kGetPillRequiredBytes]{};
    constexpr std::uintptr_t base = 0x100000u;
    static_assert(kGetPillRva == 0x2e8d80u);
    static_assert(kGetPillSize == 0x24u);
    static_assert(kGetPillRequiredBytes == 0x1c30u);
    auto native = static_cast<GetPillNative>(&Native);
    assert(InvokeGetPill(player, 0, base, native, true) == 12u);
    assert(InvokeGetPill(player, 3, base, native, true) == 23u);
    assert(InvokeGetPill(player, 4, base, native, true) == 0u);
    assert(InvokeGetPill(nullptr, 0, base, native, true) == 0u);
    assert(InvokeGetPill(player, 0, base, native, false) == 0u);
    assert(InvokeGetPill(player, 0, 0, native, true) == 0u);
    assert(InvokeGetPill(player, 0, base, nullptr, true) == 0u);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/get_pill_test.cpp" -o "$TMP_DIR/get_pill_test"
"$TMP_DIR/get_pill_test"
rg -q 'LC_Entity_Player__GetPill' "$ROOT_DIR/source/program/main.cpp"
printf 'GET_PILL_HOST_READY rva=0x2e8d80 size=0x24 required_bytes=0x1c30 slots=4 default_slot=0\n'
