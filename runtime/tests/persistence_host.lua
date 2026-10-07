local ffi = require('ffi')
ffi.cdef[[
void L_Free(char*);
void L_Mod_SaveData(const char*, const char*, int);
char* L_Mod_LoadData(const char*, int*);
bool L_Mod_HasData(const char*);
void L_Mod_RemoveData(const char*);
]]

local path = 'mods/repentanceplus/'
assert(not ffi.C.L_Mod_HasData(path))
local value = 'alpha\\0omega'
ffi.C.L_Mod_SaveData(path, value, #value)
assert(ffi.C.L_Mod_HasData(path))
local length = ffi.new('int[1]')
local data = ffi.C.L_Mod_LoadData(path, length)
assert(data ~= ffi.NULL and length[0] == #value)
assert(ffi.string(data, length[0]) == value)
ffi.C.L_Free(data)
local resized = 'a-longer-save-payload'
ffi.C.L_Mod_SaveData(path, resized, #resized)
local resized_data = ffi.C.L_Mod_LoadData(path, length)
assert(resized_data ~= ffi.NULL and length[0] == #resized)
assert(ffi.string(resized_data, length[0]) == resized)
ffi.C.L_Free(resized_data)
ffi.C.L_Mod_SaveData(path, '', 0)
assert(ffi.C.L_Mod_HasData(path))
local empty = ffi.C.L_Mod_LoadData(path, length)
assert(empty ~= ffi.NULL and length[0] == 0)
assert(ffi.string(empty, length[0]) == '')
ffi.C.L_Free(empty)
ffi.C.L_Mod_RemoveData(path)
assert(not ffi.C.L_Mod_HasData(path))
assert(ffi.C.L_Mod_LoadData(path, length) == ffi.NULL and length[0] == 0)
print('MOD_PERSISTENCE_HOST_READY')
