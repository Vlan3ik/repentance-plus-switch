#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/evaluate_items_test.cpp" <<'CPP'
#include "program/entity_player_bridge.hpp"
#include <cassert>
#include <cstdint>

namespace {
int calls = 0;
void NativeEvaluateItems(void* object) {
    assert(object == reinterpret_cast<void*>(0x1234u));
    ++calls;
}
}

int main() {
    using isaac_port::entity_player::InvokeEvaluateItems;
    using isaac_port::entity_player::EvaluateItemsNative;
    constexpr std::uintptr_t base = 0x100000u;
    constexpr std::uintptr_t rva = 0x280804u;
    auto native = static_cast<EvaluateItemsNative>(&NativeEvaluateItems);

    assert(InvokeEvaluateItems(reinterpret_cast<void*>(0x1234u), base, rva,
                               native, true, true));
    assert(calls == 1);
    assert(!InvokeEvaluateItems(nullptr, base, rva, native, true, true));
    assert(!InvokeEvaluateItems(reinterpret_cast<void*>(0x1234u), base, rva,
                                native, false, true));
    assert(!InvokeEvaluateItems(reinterpret_cast<void*>(0x1234u), base, rva,
                                native, true, false));
    // A mapped address with a mismatching BuildID-specific prologue is still
    // rejected by the production wrapper's target-verified gate.
    const bool mismatching_prologue = false;
    assert(!InvokeEvaluateItems(reinterpret_cast<void*>(0x1234u), base, rva,
                                native, true, mismatching_prologue));
    assert(calls == 1);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/evaluate_items_test.cpp" -o "$TMP_DIR/evaluate_items_test"
"$TMP_DIR/evaluate_items_test"

rg -q 'LC_Entity_Player__EvaluateItems' \
    "$ROOT_DIR/source/program/main.cpp"
rg -q 'LC_Entity_Player__EvaluateItems' \
    "$ROOT_DIR/../../switch-port/reference/stock-lua/dlc/resources/scripts_v2/cdefs.lua"
rg -q '0x280804' "$ROOT_DIR/source/program/main.cpp"
rg -q '0x6db63bef.*0x6d0133ed.*0x6d022beb.*0x6d0323e9' \
    "$ROOT_DIR/source/program/main.cpp"
printf 'EVALUATE_ITEMS_HOST_READY rva=0x280804 opaque_this=one_call\n'
