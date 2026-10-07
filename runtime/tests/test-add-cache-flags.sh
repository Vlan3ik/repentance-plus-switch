#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/cache_flags_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>
#include <cstring>

int main() {
    constexpr std::size_t kOffset =
        isaac_port::entity_player::kPendingCacheFlagsOffset;
    std::uint8_t object[kOffset + sizeof(std::uint32_t)]{};
    auto* field = reinterpret_cast<std::uint32_t*>(object + kOffset);

    *field = 0x00000005u;
    isaac_port::entity_player::OrPendingCacheFlags(field, 0x00000028u);
    assert(*field == 0x0000002du);

    isaac_port::entity_player::OrPendingCacheFlags(field, 0xffffffffu);
    assert(*field == 0xffffffffu);

    isaac_port::entity_player::OrPendingCacheFlags(nullptr, 0xffffffffu);
    assert(*field == 0xffffffffu);

    static_assert(kOffset == 0x1958);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/cache_flags_test.cpp" -o "$TMP_DIR/cache_flags_test"
"$TMP_DIR/cache_flags_test"

# Keep the endpoint and resolver in lockstep with stock cdefs.lua.
rg -q 'LC_Entity_Player__AddCacheFlags' \
    "$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity_Player__AddCacheFlags' \
    "$ROOT_DIR/../../switch-port/reference/stock-lua/dlc/resources/scripts_v2/cdefs.lua"
printf 'ADD_CACHE_FLAGS_HOST_READY offset=0x1958 mask=uint32_or\n'
