# Upstream Lua findings for Switch Repentance

Исследованы исходники:

- [REPENTOGON](https://github.com/TeamREPENTOGON/REPENTOGON), checkout
  `a3d540cba1131e0ea01205728695c0c1616f84cd`;
- [repentogxm](https://github.com/0xl0cal/repentogxm), checkout
  `2629b331937c1a8e8c7553d62e087ce182c5b3d1`;
- [IsaacDocs](https://github.com/wofsauge/IsaacDocs) — официально-совместимое
  описание Lua API;
- [isaac-chapi](https://github.com/TaigaTreant/isaac-chapi) — пример обычного
  Lua-мода, не native-плагина.

Клоны находятся в `switch-port/reference/upstream/`; большие build outputs не
создавались.

## REPENTOGON: реальная схема Lua

REPENTOGON не реализует отдельную виртуальную машину модов: он цепляется к уже
существующему `LuaEngine` игры (исходники рассчитаны на Windows/x86). Главная
точка — [`repentogon/LuaInit.cpp`](../reference/upstream/REPENTOGON/repentogon/LuaInit.cpp):

1. `HOOK_METHOD(LuaEngine, Init, ...)` вызывает оригинальный `Init`, получает
   `g_LuaEngine->_state`, регистрирует `debug`/`os`, создаёт `_CBindings` и
   вызывает `RunBundledScript("resources/scripts/enums_ex.lua")` и
   `RunBundledScript("resources/scripts/main_ex.lua")` (строки 207–235).
2. Из Lua globals `_UnloadMod`, `_RunCallback`,
   `_RunCallbackWithTwoParams` сохраняются registry references; именно через
   них проходят выгрузка и callback dispatch.
3. `HOOK_METHOD_PRIORITY(LuaEngine, RegisterClasses, ...)` получает созданные
   игрой metatables из Lua registry, сопоставляет их с C++ enum и извлекает
   адреса native binding-функций (`RegisterMetatables`, строки 108–170 и
   351–366). Это полезный способ восстановить таблицу API на Switch: сначала
   найти уже зарегистрированные metatables, затем не переписывать сотни классов
   вручную.

Версия Lua явно зафиксирована в [`repentogon/lua/lua.h`](../reference/upstream/REPENTOGON/repentogon/lua/lua.h): **Lua 5.3.3** (`LUA_VERSION_NUM 503`).

### Скриптовый слой

- [`resources/scripts/main_ex.lua`](../reference/upstream/REPENTOGON/repentogon/resources/scripts/main_ex.lua)
  расширяет callback dispatcher. `Isaac.AddCallback`/`RemoveCallback`
  управляют списками `COMMON`, `PARAM`, `ALL`; первый callback включает native
  callback через `Isaac.SetBuiltInCallbackState` (строки 1229–1284).
- `_RunCallback` получает iterator, выбирает специализированную или обычную
  логику и вызывается из native кода (строки 1961–1982).
- `RegisterMod` сначала вызывает оригинальный `RegisterMod`, затем добавляет
  reference в `ModManager.detail.RegisterMod` (строки 2029–2037).
- [`repentogon_extras/mod_manager.lua`](../reference/upstream/REPENTOGON/repentogon/resources/scripts/repentogon_extras/mod_manager.lua)
  хранит `ModReference -> ModId`, список references и флаг `ModsLoaded`.
- C++ `_CBindings.GetModId` реализован в
  [`LuaInterfaces/_Internals.cpp`](../reference/upstream/REPENTOGON/repentogon/LuaInterfaces/_Internals.cpp).

### Нативные точки/сигнатуры

В [`libzhl/functions/LuaEngine.zhl`](../reference/upstream/REPENTOGON/libzhl/functions/LuaEngine.zhl)
зафиксированы сигнатуры `LuaEngine::Init(bool)`, `RegisterClasses()`,
`RunBundledScript(const char*)`, `RunScript(const char*)`, `LuamodCMD`,
`PostGameStart`, `PostRender`, `Callback_PreEntitySpawn` и callback methods.
В [`ModManager.zhl`](../reference/upstream/REPENTOGON/libzhl/functions/ModManager.zhl)
есть `ListMods`, `LoadConfigs`, `TryRedirectPath`, `UpdateWorkshopMods`,
`LoadShaders`; layout `LuaEngine` и `ModManager` также описан там.

Это **не готовые Switch offsets**: signatures x86 (`__thiscall`, x86 byte
patterns), поэтому их нельзя перенести побайтно в ARM64 NRO. Переносимая часть —
порядок и контракт вызовов.

## Repentogxm: наиболее близкий ARM-пример

`repentogxm` — статически перекомпилированный ARM-порт PC EXE на Vita. Он
подтверждает, что Lua-моды реально работают на ARM при сохранении Lua ABI:

- README, [`INSTALL.md`](../reference/upstream/repentogxm/INSTALL.md:126) и
  [`recomp/vita/README.md`](../reference/upstream/repentogxm/recomp/vita/README.md:551)
  собирают чистый Lua 5.3.3 из пользовательского source tree;
- моды лежат в `ux0:data/isaacr001/mods/<workshop id>/`, EID проверен как
  рабочий Lua-мод; включение/выключение делается `disable.it`;
- [`runtime/host_vita_lua.c`](../reference/upstream/repentogxm/recomp/runtime/host_vita_lua.c)
  даёт ABI bridge: Lua state native, а guest CFunction хранит адрес в hidden
  upvalue и входит через общий trampoline в translated dispatcher;
- bridge учитывает re-entry и protected errors (`lua_pcallk`), ограничивает
  callback depth, даёт guest allocator и Lua import routing. Это архитектурный
  шаблон для Switch, если NRO оставляет старый Lua ABI;
- [`runtime/host_vita_lua_getclass.c`](../reference/upstream/repentogxm/recomp/runtime/host_vita_lua_getclass.c)
  показывает selective native seam: `Userdata::getClass` (`sub_003f8e30`) и
  `getExact` (`sub_003f8c80`) вызываются через `--wrap`, а не переписываются
  целиком; при любой непредвиденной форме userdata выполняется translated
  fallback;
- [`recomp/gen_all.py`](../reference/upstream/repentogxm/recomp/gen_all.py:7320)
  документирует startup bypass: PC-only гигантские Lua reservations обходятся,
  создаётся bounded guest-heap `luaL_newstate`, после чего выполнение
  возвращается в оригинальный `LuaEngine::Init`/`RegisterClasses`.

Ограничение: Vita-проект получает **PC EXE пользователя**, переводит его в C и
имеет 32-bit x86 guest ABI. Поэтому его адреса (`0x0050B6F2`, `0x0050B7A7`,
`sub_003f8e30` и т.п.) не являются Switch patch offsets. Но его модель
`native Lua 5.3.3 + callback trampoline + selective native fast paths` — самый
близкий готовый референс для ARM.

## Связь с найденным Switch NRO

В Switch Repentance уже присутствуют отдельные `Repentance.nro`/`AfterbirthPlus.nro`
и DLC RomFS содержит `resources/scripts/main.lua`, `enums.lua` и `scripts_v2`.
Первичная гипотеза была проверить существующий NRO Lua state. Последующий
разбор `dynsym`, строк и машинного кода эту гипотезу опроверг:

- в `Repentance.nro` нет `lua_State`, `luaL_*`, `lua_pcall`, стандартных строк
  Lua VM или экспортов ABI из `scripts_v2/cdefs.lua`;
- `ModManager::RunModScripts()` по `0x421838` состоит из одного `ret`;
- `ModManager::RunModScript(...)` по `0x42183c` возвращает `false` и делает
  `ret`;
- старый `AfterbirthPlus.nro` заглушен тем же способом.

Поэтому практический путь теперь такой:

1. встроить Lua runtime в отдельный injected `subsdk`;
2. переиспользовать штатные `scripts_v2`, где уже реализованы `RegisterMod`,
   callback registry, классы и enums поверх документированного `L_*`/`LL_*`/
   `LC_*` ABI;
3. реализовать сначала только ABI-замыкание, реально нужное Repentance Plus,
   вызывая экспортированные C++ функции Switch NRO;
4. перехватить игровые event points и передавать их в штатный Lua callback
   dispatcher;
5. оставить существующим `ModManager::ListMods` и XML/resource loader их
   текущую работу.

Итоговая оценка: `repentogxm` доказывает реализуемость полноценного Lua слоя на
ARM, а REPENTOGON даёт точный контракт модов и callback semantics. Runtime в
Switch-сборке отсутствует, но находящиеся в Switch RomFS `scripts_v2` сокращают
объём собственного binding-кода: их FFI ABI и экспортированные C++ symbols NRO
дают две стороны будущего bridge. Статическая перекомпиляция всего PC Lua
bridge из `repentogxm` напрямую неприменима из-за другого ABI и отсутствия PC
guest image.
