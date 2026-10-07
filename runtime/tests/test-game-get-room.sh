#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
MAIN="$ROOT_DIR/source/program/main.cpp"
EVIDENCE="$ROOT_DIR/../analysis/abi/game-get-room-evidence.json"

grep -F 'kGameRoomOffset = 0x21550' "$MAIN" >/dev/null
grep -F 'void* LL_Game__GetRoom()' "$MAIN" >/dev/null
grep -F 'std::strcmp(name, "LL_Game__GetRoom")' "$MAIN" >/dev/null
grep -F 'typedef struct { void *_; } IsaacPortRoom;' "$MAIN" >/dev/null
grep -F 'function Game.GetRoom()' "$MAIN" >/dev/null
test -s "$EVIDENCE"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cat >"$TMP_DIR/room_identity.cpp" <<'CPP'
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include "program/game_room_bridge.hpp"

namespace {
alignas(void*) std::uint8_t global_slot[sizeof(void*)];
alignas(void*) std::uint8_t game_object[0x80];
alignas(void*) std::uint8_t room_object[0x40];
void* stale_room = reinterpret_cast<void*>(0x70000000u);

bool in_range(std::uintptr_t address, std::size_t size, std::uintptr_t start,
              std::size_t length) {
    return address >= start && address - start <= length &&
           size <= length - (address - start);
}

bool mapped(std::uintptr_t address, std::size_t size, bool) {
    return in_range(address, size, reinterpret_cast<std::uintptr_t>(global_slot),
                    sizeof(global_slot)) ||
           in_range(address, size, reinterpret_cast<std::uintptr_t>(game_object),
                    sizeof(game_object)) ||
           in_range(address, size, reinterpret_cast<std::uintptr_t>(room_object),
                    sizeof(room_object));
}

bool read_pointer(std::uintptr_t address, void** value) {
    if (!value || !mapped(address, sizeof(void*), false)) return false;
    std::memcpy(value, reinterpret_cast<const void*>(address), sizeof(void*));
    return true;
}

void set_pointer(std::uint8_t* slot, void* value) {
    std::memcpy(slot, &value, sizeof(value));
}
} // namespace

int main() {
    constexpr std::size_t offset = 0x20;
    set_pointer(global_slot, game_object);
    set_pointer(game_object + offset, room_object);
    void* first = nullptr;
    assert(isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), offset, mapped,
        read_pointer, &first));
    void* second = nullptr;
    assert(isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), offset, mapped,
        read_pointer, &second));
    assert(first == room_object && first == second);

    set_pointer(global_slot, nullptr);
    assert(!isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), offset, mapped,
        read_pointer, &first));
    set_pointer(global_slot, game_object);
    assert(!isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot) + 1, offset, mapped,
        read_pointer, &first));
    set_pointer(global_slot, game_object + 1);
    assert(!isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), offset, mapped,
        read_pointer, &first));
    set_pointer(global_slot, game_object);
    assert(!isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), sizeof(game_object),
        mapped, read_pointer, &first));
    set_pointer(game_object + offset, stale_room);
    assert(!isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), offset, mapped,
        read_pointer, &first));
    set_pointer(global_slot, reinterpret_cast<void*>(UINTPTR_MAX - 0x10));
    assert(!isaac_port::game_room::Resolve(
        reinterpret_cast<std::uintptr_t>(global_slot), offset, mapped,
        read_pointer, &first));
    return 0;
}
CPP
g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" "$TMP_DIR/room_identity.cpp" \
    -o "$TMP_DIR/room_identity"
"$TMP_DIR/room_identity"

python3 - "$EVIDENCE" "$MAIN" <<'PY'
import json, re, sys
evidence = json.load(open(sys.argv[1], encoding="utf-8"))
main = open(sys.argv[2], encoding="utf-8").read()
assert evidence["build_id"] == re.search(
    r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"', main, re.S).group(1)
assert evidence["offset"] == "0x21550"
assert len(evidence["uses"]) == 4
assert all(item["rva"].startswith("0x") for item in evidence["uses"])
print("GAME_GET_ROOM_HOST_READY identity=stable ownership=non-owning verification=hardware_required")
PY
