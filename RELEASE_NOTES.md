# v0.1.0-alpha — первый аппаратный bring-up

Первый публичный пакет нативного Switch-порта Repentance Plus.

Установка:

1. Нужна легально установленная The Binding of Isaac: Repentance с Title ID
   `010021C000B6A000` и Build ID, указанными в README.
2. Распаковать архив в корень microSD с объединением папки `atmosphere`.
3. Запустить игру через Atmosphère.

Архив добавляет:

- `atmosphere/contents/010021C000B6A000/exefs/subsdk9` — runtime injector;
- `atmosphere/contents/010021C000B6A000/romfs/mods/repentanceplus` — Lua/XML/assets;
- `atmosphere/contents/010021C000B6A000/romfs/rp_patch/resources` — resource overlay.

Не добавляйте чужой `main.npdm`. Если уже установлен другой `subsdk9`, он
конфликтует с этим инжектором.

Статус: alpha. Lua runtime, callback smoke, resource package и штатный
ModManager собраны; полное покрытие Isaac Lua ABI ещё в работе. При сбое
приложите Atmosphère crash report и строки `[isaac-port]` к GitHub Issue.

NSP/NSZ игры, ключи и оригинальные Nintendo-бинарники в релиз не входят.
