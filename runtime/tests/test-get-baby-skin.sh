#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/baby_skin_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

int main() {
    constexpr std::size_t offset =
        isaac_port::entity_player::kBabySkinOffset;
    alignas(void*) std::uint8_t first[offset + sizeof(std::int32_t)]{};
    alignas(void*) std::uint8_t second[offset + sizeof(std::int32_t)]{};
    auto* first_field = reinterpret_cast<std::int32_t*>(first + offset);
    auto* second_field = reinterpret_cast<std::int32_t*>(second + offset);

    *first_field = -1;
    *second_field = 59;
    assert(isaac_port::entity_player::ReadBabySkin(first, true, true) == -1);
    assert(isaac_port::entity_player::ReadBabySkin(second, true, true) == 59);

    *first_field = 0;
    assert(isaac_port::entity_player::ReadBabySkin(first, true, true) == 0);
    *first_field = 59;
    assert(isaac_port::entity_player::ReadBabySkin(first, true, true) == 59);
    assert(isaac_port::entity_player::ReadBabySkin(first, false, true) == -1);
    assert(isaac_port::entity_player::ReadBabySkin(first, true, false) == -1);
    assert(isaac_port::entity_player::ReadBabySkin(nullptr, true, true) == -1);

    static_assert(offset == 0x20E8);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/baby_skin_test.cpp" -o "$TMP_DIR/baby_skin_test"
"$TMP_DIR/baby_skin_test"

rg -q 'LC_Entity_Player__GetBabySkin' \
    "$ROOT_DIR/source/program/main.cpp"
rg -q 'GetBabySkin' "$ROOT_DIR/source/program/main.cpp"
printf 'GET_BABY_SKIN_HOST_READY offset=0x20e8 signed_int32=sentinels(-1,0,59)\n'
