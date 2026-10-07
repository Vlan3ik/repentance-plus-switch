#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cat >"$TMP_DIR/path_test.cpp" <<'CPP'
#include "program/mod_persistence.hpp"
#include <cassert>
#include <cstring>
int main() {
    char path[160]{};
    assert(isaac_port::mod_persistence::BuildSavePath("mods/repentanceplus/", path, sizeof(path)));
    assert(std::strcmp(path, "data/repentanceplus/save1.dat") == 0);
    assert(isaac_port::mod_persistence::BuildSavePath("mods/repentanceplus", path, sizeof(path)));
    assert(!isaac_port::mod_persistence::BuildSavePath("mods/../escape", path, sizeof(path)));
    assert(!isaac_port::mod_persistence::BuildSavePath("mods/a/b", path, sizeof(path)));
    assert(!isaac_port::mod_persistence::BuildSavePath("../escape", path, sizeof(path)));
    assert(!isaac_port::mod_persistence::BuildSavePath("", path, sizeof(path)));
    assert(!isaac_port::mod_persistence::IsSdmcMountName(nullptr));
    assert(!isaac_port::mod_persistence::IsSdmcMountName("romfs:/"));
    assert(isaac_port::mod_persistence::IsSdmcMountName("sdmc"));
    assert(isaac_port::mod_persistence::IsSdmcMountName("sdmc:/"));
    assert(!isaac_port::mod_persistence::IsSdmcMountName("sdmcc:/"));
    assert(isaac_port::mod_persistence::CommitSucceeded(0));
    assert(!isaac_port::mod_persistence::CommitSucceeded(1));
    return 0;
}
CPP
g++ -std=c++17 -Wall -Wextra -Werror -I"$ROOT_DIR/source" \
    "$TMP_DIR/path_test.cpp" -o "$TMP_DIR/path_test"
"$TMP_DIR/path_test"
echo MOD_PERSISTENCE_PATH_HOST_READY
