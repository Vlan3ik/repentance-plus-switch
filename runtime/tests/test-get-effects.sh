#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/get_effects_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>
#include <cstring>

int main() {
    using namespace isaac_port::entity_player;
    constexpr std::size_t offset = kTemporaryEffectsOffset;
    constexpr std::size_t size = kTemporaryEffectsSize;
    alignas(void*) std::uint8_t first[kTemporaryEffectsRequiredBytes]{};
    alignas(void*) std::uint8_t second[kTemporaryEffectsRequiredBytes]{};

    void* first_owner = first;
    void* second_owner = second;
    std::memcpy(first + offset + kTemporaryEffectsOwnerOffset,
                &first_owner, sizeof(first_owner));
    std::memcpy(second + offset + kTemporaryEffectsOwnerOffset,
                &second_owner, sizeof(second_owner));

    auto* first_effects = GetBorrowedTemporaryEffects(
        first, true, true, true, first_owner);
    auto* second_effects = GetBorrowedTemporaryEffects(
        second, true, true, true, second_owner);
    assert(first_effects == first + offset);
    assert(second_effects == second + offset);
    assert(first_effects != second_effects);

    // Borrowed means identity only: this helper never allocates or owns the
    // returned address.  The full embedded range must be mapped.
    assert(GetBorrowedTemporaryEffects(first, false, true, true,
                                       first_owner) == nullptr);
    assert(GetBorrowedTemporaryEffects(first, true, false, true,
                                       first_owner) == nullptr);
    assert(GetBorrowedTemporaryEffects(nullptr, true, true, true,
                                       first_owner) == nullptr);
    assert(GetBorrowedTemporaryEffects(first + 1, true, true, true,
                                       first_owner) == nullptr);
    assert(GetBorrowedTemporaryEffects(first, true, true, true,
                                       second_owner) == nullptr);
    // Construction can briefly expose a null back-pointer; do not break the
    // accessor solely because the owner slot has not been initialized yet.
    assert(GetBorrowedTemporaryEffects(first, true, true, true, nullptr) ==
           first + offset);

    static_assert(offset == 0x18d8);
    static_assert(size >= 0x30);
    static_assert(kTemporaryEffectsRequiredBytes == 0x1908);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/get_effects_test.cpp" -o "$TMP_DIR/get_effects_test"
"$TMP_DIR/get_effects_test"

MAIN="$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity_Player__GetEffects' "$MAIN"
rg -q 'kTemporaryEffectsOffset = 0x18D8' \
    "$ROOT_DIR/source/program/entity_player_bridge.hpp"
rg -q 'ffi.gc' "$MAIN"
printf 'GET_EFFECTS_HOST_READY offset=0x18d8 size=0x30 required=0x1908 borrowed=non-owning\n'
