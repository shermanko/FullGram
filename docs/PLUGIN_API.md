# FullGram Developer API (v1.5.0)

Документация по разработке плагинов на **Lua**, **Python** и **Rust**, созданию графического интерфейса (`fullgram.open_ui`), ограничениям безопасности и протоколу ИИ-ассистента FullGram.

---

## Содержание

1. [Быстрый старт](#1-быстрый-старт)
2. [Заголовок и метаданные плагина](#2-заголовок-и-метаданные-плагина)
3. [Хуки жизненного цикла](#3-хуки-жизненного-цикла)
4. [Встроенный модуль `fullgram`](#4-встроенный-модуль-fullgram)
5. [Графический UI плагинов (`open_ui` и `on_ui_event`)](#5-графический-ui-плагинов-open_ui-и-on_ui_event)
6. [Ограничения песочницы и безопасность](#6-ограничения-песочницы-и-безопасность)
7. [Поддерживаемый синтаксис Lua, Python и Rust](#7-поддерживаемый-синтаксис-lua-python-и-rust)
8. [Готовые примеры плагинов](#8-готовые-примеры-плагинов)
9. [Протокол ИИ-ассистента](#9-протокол-ии-ассистента)

---

## 1. Быстрый старт

Плагины выполняются во встроенных изолированных VM под управлением [`FullGramPluginManager`](../submodules/Display/Source/FullGramPluginManager.swift):
- **Lua 5.x** — [`FullGramLuaEngine.swift`](../submodules/Display/Source/FullGramLuaEngine.swift)
- **Python 3** — [`FullGramPythonEngine.swift`](../submodules/Display/Source/FullGramPythonEngine.swift)
- **Rust (скриптовое подмножество)** — [`FullGramRustEngine.swift`](../submodules/Display/Source/FullGramRustEngine.swift)

Установить или создать плагин можно через **Настройки → FullGram → Плагины**:
1. Установка из официального **Маркета плагинов FullGram** (`https://fullgram.korsakovx.workers.dev/plugins.json`).
2. Создание и редактирование скрипта во встроенном редакторе кода с консолью логов.

---

## 2. Заголовок и метаданные плагина

Первые 40 строк скрипта могут содержать теги в комментариях (`--` для Lua, `#` для Python, `//` для Rust):

| Тег | Описание | Обязательный |
| --- | --- | --- |
| `@name` | Отображаемое имя плагина | Нет (берётся имя файла) |
| `@id` | Уникальный ID (`[a-z0-9_]`), используется для хранения и обновлений | Нет (генерируется из `@name`) |
| `@version` | Версия, например `1.5` (при изменении версии встроенный плагин обновляется автоматически) | Нет |
| `@author` | Имя или `@username` автора | Нет |
| `@description` | Краткое описание в списке плагинов и в подсказке команд | Нет |

### Пример заголовка (Lua / Python / Rust)

```lua
-- @name Быстрый счётчик
-- @id quick_counter
-- @version 1.0
-- @author shermanko
-- @description Команда .cnt с графическим окном
```

```python
# @name Текст-мастер
# @id text_master
# @version 1.0
# @author shermanko
# @description Команды .upper и .mock
```

```rust
// @name Rust Helper
// @id rust_helper
// @version 1.0
// @author shermanko
// @description Пример плагина на Rust
```

---

## 3. Хуки жизненного цикла

### 3.1. `on_command(ctx)`
Вызывается при отправке сообщения вида `.команда [аргументы]` или `.plug <подкоманда> [аргументы]`.

**Поля `ctx`:**
- `ctx.command` (`string`) — имя команды без точки в нижнем регистре (`"casino"`, `"plug"`).
- `ctx.subcommand` (`string`) — первое слово аргументов в нижнем регистре (`"info-chat"`).
- `ctx.args` (`string`) — вся строка аргументов.
- `ctx.text` (`string`) — исходный текст сообщения целиком.
- `ctx.peer_id` (`int`) — числовой ID чата.
- `ctx.is_group` (`bool`), `ctx.is_channel` (`bool`).
- `ctx.chat_stats` (`table | nil`) — локальная статистика чата (для `.plug` / `.info-chat`).

**Возвращаемое значение:**
- `nil` / `None` — пропустить обработку;
- `string` — заменить текст сообщения и отправить его в чат;
- `{ text = "..." }` — заменить текст;
- `{ cancel = true, toast = "..." }` — **отменить отправку сообщения в чат** (и опционально показать уведомление).

### 3.2. `on_outgoing_message(ctx)`
Вызывается перед отправкой любого текстового сообщения (на фоновой очереди).  
**Поля `ctx`:** `text`, `peer_id`, `is_group`, `is_channel`.

### 3.3. `on_render_message(ctx)`
Вызывается при отображении текста сообщения в пузыре (`ChatMessageTextBubbleContentNode`).  
**Поля `ctx`:** `text`, `peer_id`, `is_incoming`, `message_id`.  
**Возврат:** строка для отображения на экране или `nil`/`None`.

> [!WARNING]
> Вызов `fullgram.http_get` внутри `on_render_message` **запрещён** для защиты переписки и плавности скролла.

### 3.4. `on_message_action(ctx)`
Действие в контекстном меню сообщения (`text`, `peer_id`).

### 3.5. `on_ui_event(ctx)`
Вызывается при нажатии кнопки в графическом окне, открытом через `fullgram.open_ui(...)`.  
**Поля `ctx`:**
- `ctx.action` (`string`) — `id` нажатой кнопки;
- `ctx.input` (`string`) — текущий текст из поля ввода окна.

**Возврат:** строка (обновляет карточку результата в окне) или таблица `{ text = "..." }`.

---

## 4. Встроенный модуль `fullgram`

В Lua `fullgram` доступен глобально; в Python — глобально или через `import fullgram`; в Rust — `fullgram::...`.

| Функция | Сигнатура | Описание |
| --- | --- | --- |
| `fullgram.log` | `(...args) -> nil` | Записать строку в консоль плагина |
| `fullgram.toast` | `(text: string) -> nil` | Показать всплывающее уведомление |
| `fullgram.open_ui` | `(spec: string \| table) -> bool` | Открыть нативный графический UI плагина |
| `fullgram.clipboard_get` | `() -> string` | Прочитать текст из буфера обмена |
| `fullgram.clipboard_set` | `(text: string) -> bool` | Скопировать текст в буфер обмена |
| `fullgram.storage_get` | `(key: string, default?: any) -> any` | Прочитать значение из изолированного хранилища плагина |
| `fullgram.storage_set` | `(key: string, value: any) -> bool` | Сохранить значение (`nil`/`None` удаляет ключ) |
| `fullgram.register_command` | `(cmd: string, fn: function) -> nil` | Зарегистрировать обработчик команды без `on_command` |
| `fullgram.get_chat_stats` | `() -> table \| nil` | Получить статистику открытого чата |
| `fullgram.http_get` | `(url: string) -> string \| nil` | Синхронный `HTTP / HTTPS GET`-запрос (таймаут `8.0 с`) |

---

## 5. Графический UI плагинов (`open_ui` и `on_ui_event`)

Чтобы плагин не спамил текстом в чат, вызывайте `fullgram.open_ui(...)` и возвращайте `{ cancel = true }`.

### Встроенные специализированные экраны
- `kind = "betking_casino"` — анимированное казино BetKing / Betona (`game`: `"zeus"`, `"dogs"`, `"slots777"`, `"crash"`, `"roulette"`, `"coin"`).
- `kind = "deadlines"` — интерактивный менеджер дедлайнов с чекбоксами и свайпом удаления.

### Декларативный кастомный экран (`kind = "custom"`)
```lua
fullgram.open_ui({
    kind = "custom",
    title = "Мой плагин",
    subtitle = "Начальный текст на карточке результата",
    placeholder = "Введите число или текст…",
    default_input = "100",
    buttons = {
        { items = {
            { title = "⚡ Действие 1", id = "act_1", color = "orange" },
            { title = "✅ Действие 2", id = "act_2", color = "green" }
        } },
        { title = "🔄 Сброс", id = "reset", color = "red" }
    }
})
```
Доступные цвета кнопок: `blue`, `green`, `orange`, `red`, `purple`, `indigo`, `teal`, `gray`.

При нажатии на кнопку FullGram вызывает `on_ui_event(ctx)` с `ctx.action = "<id>"` и `ctx.input = "<текст поля>"`, а возвращённый текст отображается на карточке (пользователь может отправить его в чат кнопкой «В чат» в правом верхнем углу).

---

## 6. Ограничения песочницы и безопасность

- **Лимит инструкций (`maxSteps`)**: `120 000` шагов на один вызов хука.
- **Лимит рекурсии (`maxCallDepth`)**: `64` вложенных вызова.
- **Потокобезопасность (`vmLock`)**: все вызовы VM защищены `NSRecursiveLock`.
- **Сеть `http_get`**: `http://` и `https://` с таймаутом `8.0 с` (запрещено внутри `on_render_message`).
- **Защита источников**: сторонние непроверенные источники плагинов ограничены; официальный каталог обслуживается сервером FullGram.

---

## 7. Поддерживаемый синтаксис Lua, Python и Rust

- **Lua**: `local`, `function`, замыкания, `if/elseif/else`, `for`, `pairs/ipairs`, `while`, `repeat/until`, `pcall`, таблицы, `string`, `table`, `math`, `json`.
- **Python**: `def`, `lambda`, `if/elif/else`, `for/while`, `try/except`, f-строки, list comprehensions, `dict`/`list`/`tuple`/срезы, `re`, `json`, `math`, `random`, `time`, `fullgram`.
- **Rust**: `fn`, `let`/`let mut`, `if/else`, `for`/`while`, строки, массивы, `fullgram::*`.

---

## 8. Готовые примеры плагинов

### Lua: плагин с графическим окном (без спама в чат)

```lua
-- @name Кости GUI
-- @id dice_gui
-- @version 1.0
-- @author Dev
-- @description Команда .dice открывает окно броска кубиков

function on_command(ctx)
    if ctx.command ~= "dice" then return nil end
    fullgram.open_ui({
        kind = "custom",
        title = "🎲 Кубики",
        subtitle = "Нажмите кнопку ниже, чтобы бросить кубики",
        default_input = "6",
        buttons = {
            { items = {
                { title = "🎲 1 кубик", id = "roll1", color = "blue" },
                { title = "🎲🎲 2 кубика", id = "roll2", color = "purple" }
            } }
        }
    })
    return { cancel = true }
end

function on_ui_event(ctx)
    local sides = tonumber(ctx.input) or 6
    if sides < 2 then sides = 6 end
    if ctx.action == "roll2" then
        local a = math.random(1, sides)
        local b = math.random(1, sides)
        return "🎲 Выпало: " .. tostring(a) .. " + " .. tostring(b) .. " = " .. tostring(a + b)
    end
    return "🎲 Выпало: " .. tostring(math.random(1, sides)) .. " (d" .. tostring(sides) .. ")"
end
```

### Lua: регистрация команды через `register_command`

```lua
-- @name Быстрый пинг
-- @id quick_ping
-- @version 1.0
-- @author Dev
-- @description Команда .ping

fullgram.register_command("ping", function(ctx)
    local n = tonumber(fullgram.storage_get("pings", 0)) + 1
    fullgram.storage_set("pings", n)
    return { cancel = true, toast = "Pong! Вызовов: " .. tostring(n) }
end)
```

---

## 9. Протокол ИИ-ассистента

Перед отправкой запроса модели `FullGramAITelegramContextBuilder` ([`FullGramAIOverlay.swift`](../submodules/TelegramUI/Sources/FullGramAIOverlay.swift)) формирует контекст:
- **`[VERIFIED_LOCAL_STATS — ТЕКУЩИЙ ЧАТ]`** — количество сообщений сегодня / за 7 дней / в истории, медиа, ГС, кружки, топ участников (если открыт чат).
- **`[VERIFIED_LOCAL_STATS — ОБЩАЯ СТАТИСТИКА АККАУНТА]`** — число личных чатов, групп и каналов, активных сегодня диалогов, общее число непрочитанных и топ чатов с непрочитанными.
- **`[UNTRUSTED_CHAT_DATA]`** — изолированные тексты сообщений и названия диалогов (модель не имеет права исполнять инструкции из этого блока).

Опциональные действия в конце ответа модели (подтверждаются пользователем вручную):
```text
[[FULLGRAM_ACTION:{"kind":"insert_draft","text":"текст"}]]
[[FULLGRAM_ACTION:{"kind":"send_message","peer_id":12345,"text":"текст"}]]
[[FULLGRAM_ACTION:{"kind":"open_chat","peer_id":12345}]]
[[FULLGRAM_ACTION:{"kind":"toggle_setting","setting_key":"ghost_mode|download_boost|floating_pet|quick_formatting","setting_value":true}]]
```
