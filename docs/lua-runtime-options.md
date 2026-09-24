# Lua runtime на Switch: практическая оценка

## Короткий вывод

Стоковый `resources/scripts_v2` нельзя исполнять обычным Lua 5.3: он прямо требует LuaJIT FFI (`require("ffi")`, `ffi.cdef`, `ffi.C`, `ffi.new`, `ffi.gc`, `ffi.istype`) и Lua 5.1-совместимое окружение (`setfenv`, `getfenv`).

Наиболее короткий рабочий путь — портировать LuaJIT 2.1 на AArch64/devkitA64, оставить FFI включённым, но на первом этапе собрать с отключённым JIT. LuaJIT upstream официально отмечает ARM64, Nintendo Switch, Lua 5.1 API/ABI и FFI как поддерживаемые платформу/возможности. [Документация LuaJIT 2.1](https://github.com/LuaJIT/LuaJIT/blob/v2.1/doc/luajit.html#L843-L877)

JIT включать сразу рискованно: Horizon не разрешает превратить обычную heap/RW-область в executable через `svcSetMemoryPermission` (`Perm_X` запрещён). Для RX-кода нужен отдельный code-memory mapping/loader-путь; официальный `nx-hbloader` сначала вызывает `svcMapProcessCodeMemory`, затем выставляет `Perm_R | Perm_X` для text-сегмента NRO. [libnx SVC API](https://github.com/switchbrew/libnx/blob/master/nx/include/switch/kernel/svc.h#L2955-L2990), [nx-hbloader NRO loader](https://github.com/switchbrew/nx-hbloader/blob/master/source/main.c#L1882-L1918)

Практическая последовательность:

1. LuaJIT interpreter + FFI, `LUAJIT_DISABLE_JIT`, FFI оставить включённым.
2. Зарегистрировать в `ffi.C` только совместимый мост `L_*`, `LL_*`, `LC_*`.
3. Подключить callback pump к игровому циклу.
4. После запуска минимального мода отдельно решать JIT: либо оставить interpreter-only, либо размещать JIT-код через разрешённый code-memory allocator.

## Почему LuaJIT, а не Lua 5.3

`scripts_v2/main.lua` использует `ffi = require("ffi")`, `ffi.cdef`, `ffi.C`, `ffi.new`, `ffi.gc`, `ffi.istype`, `ffi.typeof`, `setfenv` и `getfenv`. Это не просто удобные функции: `bindings.lua` построен вокруг opaque C handles (`Entity*`, `Entity_Player*`, `RoomData*`) и вызывает ABI напрямую.

Вариант с Lua 5.3 потребует либо:

- переписать весь `scripts_v2` на `luaL_newmetatable`/`luaL_setfuncs` и вручную создать сотни wrappers;
- либо добавить самостоятельную FFI-реализацию и Lua 5.1 compatibility layer.

По объёму это существенно больше портирования LuaJIT. Lua 5.3 имеет другой C API/ABI и не понимает ни `ffi.cdef`, ни `setfenv`; поэтому «Lua 5.3 + несколько C wrappers» годится только для нового минимального API, но не для stock `scripts_v2` и Repentance Plus без адаптации скриптов.

## Проверка ABI на Repentance.nro

В DLC stock-файлах C ABI объявлен именами `LL_*`/`LC_*` в `cdefs.lua`. В строковой таблице `Repentance.nro` буквальных экспортов `LL_Isaac__*`, `LC_Entity__*` и `L_EnableCallback` не найдено. Зато NRO содержит полноценные C++ символы IsaacRepentance с совпадающей предметной областью. Следовательно, механическое `dlsym("LL_Isaac__GetPlayer")` не сработает: нужен bridge-слой по адресам/сигнатурам, найденным в дизассемблере, либо собственные trampoline-функции.

Ниже 20 характерных соответствий. Это семантические кандидаты, а не доказанные ABI-совпадения: C++ методы используют `this` и внутренние типы, а stock wrapper ожидает C ABI. Для каждого кандидата перед внедрением нужно проверить calling convention, регистры AArch64, layout структур и адрес в конкретном Build ID.

| Stock ABI из `cdefs.lua` | Найденный кандидат в Repentance.nro | Оценка |
|---|---|---|
| `LL_Isaac__GetPlayer` | `IsaacRepentance::PlayerManager::SpawnCoPlayer(int)` / `Game::GetNearestPlayer(Vector2 const&)` | средняя; нужен `PlayerManager` accessor |
| `LL_Isaac__GetFrameCount` | `Game`/main-loop state accessors | низкая; прямой символ не найден |
| `LL_Isaac__ExecuteCommand` | `IsaacRepentance::Console::RunCommand(string const&, string*, Entity_Player*)` | высокая по смыслу |
| `LL_Isaac__FindByType` | `Game::FindByType`-семантика; Entity search symbols требуют адресного поиска | средняя |
| `LL_Isaac__CountEntities` | `Room`/`Game` entity iteration; прямой exported C bridge не найден | средняя-низкая |
| `LL_Isaac__GetRandomPosition` | `Room::GetRandomTileIndex(int)` | средняя; результат нужно преобразовать в Vector2 |
| `LL_Isaac__GetFreeNearPosition` | `Game`/`Room` spawn-position helper | низкая; искать по call-sites |
| `LL_Isaac__RenderText` | KAGE graphics `RenderTexturedTriangles`/font subsystem | низкая; не Isaac-specific |
| `LL_Isaac__ConsoleOutput` | `Console::RunCommand` + debug output | средняя |
| `LL_Isaac__GetChallenge` | global game-state/challenge field | средняя-низкая |
| `LC_Entity__GetPosition` | `IsaacRepentance::Entity` position accessor | высокая по смыслу, проверить layout |
| `LC_Entity__SetPosition` | `Entity` position mutator | высокая по смыслу |
| `LC_Entity__GetVelocity` | `Entity` velocity accessor | высокая по смыслу |
| `LC_Entity__SetVelocity` | `Entity` velocity mutator | высокая по смыслу |
| `LC_Entity_Player__AddCollectible` | `Entity_Player::AddCollectible(eCollectibleType,int,bool,int,int)` | высокая; символ найден |
| `LC_Entity_Player__RemoveCollectible` | `Entity_Player::RemoveCollectible(eCollectibleType,bool,int,bool)` | высокая; символ найден |
| `LC_Entity_Player__EvaluateItems` | `Entity_Player::EvaluateItems()` | высокая; символ найден |
| `LC_Entity_Player__AddTrinket` | `Entity_Player::AddTrinket(eTrinketType,bool)` | высокая; символ найден |
| `LC_Entity_Player__AddCard` | `Entity_Player::AddCard(eCard)` | высокая; символ найден |
| `LC_Entity_NPC__Morph` | `Entity_NPC::Morph(eEntityType,unsigned int,unsigned int,int)` | высокая; символ найден |

Важное ограничение: наличие C++ имени в NRO не означает, что символ динамически экспортирован. В текущем извлечённом NRO это строки/символьные данные для анализа; итоговый bridge должен привязываться к RVA относительно Build ID `b6e5bdb9dc12e1d1a25cbfda17f4be24b4754ef5` и иметь сигнатурные проверки.

## Минимальная архитектура runtime

```text
Repentance.nro hook
    ├─ создаёт LuaJIT state (interpreter-only)
    ├─ package.path -> SD:/.../repentanceplus/?.lua
    ├─ выполняет stock scripts_v2/main.lua
    ├─ ffi.C -> bridge table (L_*/LL_*/LC_*)
    └─ игровой callback pump -> lua_pcall(mod callbacks)
```

Bridge лучше сделать явными статическими функциями с C ABI, а не пытаться подменять mangled C++ symbols:

```cpp
extern "C" Entity_Player* LL_Isaac__GetPlayer(int id);
extern "C" void L_EnableCallback(unsigned int callback);
extern "C" void L_Mod_SaveData(const char* path, const char* data, int len);
```

Каждая функция внутри вызывает найденный RVA/C++ method или временно возвращает безопасную заглушку. Это позволит сначала запустить Lua и `RegisterMod`, а затем наращивать ABI по фактическим вызовам Repentance Plus.

## Риски

- LuaJIT FFI предполагает точное совпадение layout `Vector2`, `Color`, `EntityRef`, `LuaCallback` и указателей; ошибка ABI даст crash, а не Lua exception.
- JIT-код нельзя размещать в обычном RW heap: Horizon SVC API явно запрещает `Perm_X` для `svcSetMemoryPermission`.
- Доступ Lua к C++ объектам должен происходить на игровом потоке; callback pump в отдельном thread опасен.
- В NRO отсутствуют готовые `LL_*/LC_*` экспортные имена, поэтому автоматическая линковка stock `ffi.C` невозможна без bridge.

## Первичные источники

- [LuaJIT upstream documentation](https://github.com/LuaJIT/LuaJIT/blob/v2.1/doc/luajit.html)
- [LuaJIT ARM64 VM backend](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/vm_arm64.dasc)
- [LuaJIT architecture/configuration header](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lj_arch.h)
- [libnx SVC declarations](https://github.com/switchbrew/libnx/blob/master/nx/include/switch/kernel/svc.h)
- [nx-hbloader code-memory/NRO loader](https://github.com/switchbrew/nx-hbloader/blob/master/source/main.c)
