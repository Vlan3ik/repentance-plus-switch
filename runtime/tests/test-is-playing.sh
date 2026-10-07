#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/is_playing_test.cpp" <<'CPP'
#include "program/anm2_bridge.hpp"
#include <cassert>
#include <cstring>

struct FakeAnm2 {
    bool playing;
    const char* animation;
    int calls;
};

static bool MockIsPlaying(void* raw, const char* requested) {
    auto* sprite = static_cast<FakeAnm2*>(raw);
    ++sprite->calls;
    if (!sprite->playing) return false;
    return requested && std::strcmp(requested, sprite->animation) == 0;
}

int main() {
    FakeAnm2 active{true, "Idle", 0};
    FakeAnm2 stopped{false, "Idle", 0};
    assert(isaac_port::anm2::InvokeIsPlaying(
        &active, "Idle", MockIsPlaying, true, true));
    assert(!isaac_port::anm2::InvokeIsPlaying(
        &active, "Walk", MockIsPlaying, true, true));
    assert(!isaac_port::anm2::InvokeIsPlaying(
        &active, "", MockIsPlaying, true, true));
    assert(!isaac_port::anm2::InvokeIsPlaying(
        &stopped, "Idle", MockIsPlaying, true, true));
    assert(!isaac_port::anm2::InvokeIsPlaying(
        &active, nullptr, MockIsPlaying, true, true));
    assert(!isaac_port::anm2::InvokeIsPlaying(
        &active, "Idle", MockIsPlaying, false, true));
    assert(!isaac_port::anm2::InvokeIsPlaying(
        &active, "Idle", MockIsPlaying, true, false));
    assert(active.calls == 4);
    assert(stopped.calls == 1);
    /* The helper only reads the opaque pointer.  Ownership is represented by
     * the Lua metatables: no destructor callback is part of this call. */
    static_assert(sizeof(FakeAnm2) > 0);
    return 0;
}
CPP

g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/is_playing_test.cpp" -o "$TMP_DIR/is_playing_test"
"$TMP_DIR/is_playing_test"

rg -q 'function methods:IsPlaying\(animation\)' \
    "$ROOT_DIR/source/program/main.cpp"
rg -q 'IsaacPort_ANM2_IsPlaying' "$ROOT_DIR/source/program/main.cpp"
rg -q '__borrowed = true' "$ROOT_DIR/source/program/main.cpp"
if rg -q 'borrowedSprite.*ffi\.gc|ffi\.gc.*borrowedSprite' \
    "$ROOT_DIR/source/program/main.cpp"; then
    echo 'borrowed Sprite unexpectedly owns a finalizer' >&2
    exit 1
fi
printf 'IS_PLAYING_HOST_READY active=1 stopped=0 names=empty/match/mismatch ownership=unchanged\n'
