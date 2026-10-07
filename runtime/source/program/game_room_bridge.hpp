#pragma once

#include <cstddef>
#include <cstdint>

namespace isaac_port::game_room {

using MappedRange = bool (*)(std::uintptr_t address, std::size_t size,
                             bool require_write);
using ReadPointer = bool (*)(std::uintptr_t address, void** value);

/* Resolve Game's non-owning Room member without dereferencing through the
 * resolver itself. Injected callbacks keep the address policy unit-testable
 * on a host while the production caller supplies Horizon memory checks. */
inline bool Resolve(std::uintptr_t game_global, std::size_t room_offset,
                    MappedRange mapped, ReadPointer read, void** room_out) {
    if (room_out)
        *room_out = nullptr;
    if (!room_out || !mapped || !read || game_global == 0 ||
        (game_global % alignof(void*)) != 0 ||
        !mapped(game_global, sizeof(void*), false))
        return false;

    void* game = nullptr;
    if (!read(game_global, &game) || !game)
        return false;
    const auto game_address = reinterpret_cast<std::uintptr_t>(game);
    if ((game_address % alignof(void*)) != 0 ||
        room_offset > static_cast<std::uintptr_t>(-1) - game_address)
        return false;

    const auto room_field = game_address + room_offset;
    if ((room_field % alignof(void*)) != 0 ||
        !mapped(room_field, sizeof(void*), false))
        return false;

    void* room = nullptr;
    if (!read(room_field, &room) || !room)
        return false;
    const auto room_address = reinterpret_cast<std::uintptr_t>(room);
    if ((room_address % alignof(void*)) != 0 ||
        !mapped(room_address, sizeof(void*), false))
        return false;

    *room_out = room;
    return true;
}

} // namespace isaac_port::game_room
