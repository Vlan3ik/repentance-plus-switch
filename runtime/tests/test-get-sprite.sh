#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/get_sprite_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstddef>
#include <cstdint>

int main() {
    constexpr std::size_t offset =
        isaac_port::entity_player::kSpritePointerOffset;
    std::uint8_t entity[offset + 0x158]{};
    void* expected = entity + offset;

    assert(isaac_port::entity_player::GetBorrowedSprite(
               entity, true, true) == expected);
    assert(isaac_port::entity_player::GetBorrowedSprite(
               entity, false, true) == nullptr);
    assert(isaac_port::entity_player::GetBorrowedSprite(
               entity, true, false) == nullptr);
    assert(isaac_port::entity_player::GetBorrowedSprite(
               nullptr, true, true) == nullptr);
    assert(isaac_port::entity_player::GetBorrowedSprite(
               entity + 1, true, true) == nullptr);
    static_assert(offset == 0x48);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/get_sprite_test.cpp" -o "$TMP_DIR/get_sprite_test"
"$TMP_DIR/get_sprite_test"

rg -q 'LC_Entity__GetSprite' "$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity__GetSprite' \
    "$ROOT_DIR/../../switch-port/reference/stock-lua/dlc/resources/scripts_v2/cdefs.lua"
printf 'GET_SPRITE_HOST_READY offset=0x48 borrowed=non_owning\n'
