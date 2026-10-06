#pragma once

#include <cstddef>
#include <cstdio>
#include <cstring>

namespace isaac_port::mod_persistence {

constexpr std::size_t kMaxModIdentity = 96;
constexpr std::size_t kMaxPath = 160;

/* Build the single-file layout used by the alpha backend.  Mod.Path is the
 * engine's `mods/<name>/` identity, not a bare folder name. */
inline bool BuildSavePath(const char* identity, char* out, std::size_t out_size) {
    if (!identity || !out || out_size < 2)
        return false;
    constexpr char kPrefix[] = "mods/";
    if (std::strncmp(identity, kPrefix, sizeof(kPrefix) - 1) != 0)
        return false;
    const char* name = identity + sizeof(kPrefix) - 1;
    char safe[kMaxModIdentity + 1]{};
    std::size_t used = 0;
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(name);
         *p && *p != '/' && used < kMaxModIdentity; ++p) {
        const bool allowed = (*p >= 'a' && *p <= 'z') ||
                             (*p >= 'A' && *p <= 'Z') ||
                             (*p >= '0' && *p <= '9') || *p == '_' || *p == '-';
        if (!allowed)
            return false;
        safe[used++] = static_cast<char>(*p);
    }
    const char* tail = name + used;
    if (used == 0 || (*tail != '\0' && !(tail[0] == '/' && tail[1] == '\0')))
        return false;
    const int written = std::snprintf(out, out_size, "data/%s/save1.dat", safe);
    return written > 0 && static_cast<std::size_t>(written) < out_size;
}

} // namespace isaac_port::mod_persistence
