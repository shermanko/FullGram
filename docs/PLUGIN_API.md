# FullGram Plugin System & Developer API (v2.0)

Полностью переработанная система плагинов FullGram с поддержкой **управления ником и профилем Telegram**, **доступа к локальному времени и состоянию телефона**, **фонового режима выполнения** (`on_background_tick`), шины событий и единого модульного **Plugin API v2.0** для **Lua**, **Python** и **Rust**.

---

## Содержание

1. [Что нового в Plugin System v2.0](#1-что-нового-в-plugin-system-v20)
2. [Быстрый старт и метаданные](#2-быстрый-старт-и-метаданные)
3. [Хуки жизненного цикла и фоновый режим](#3-хуки-жизненного-цикла-и-фоновый-режим)
4. [Plugin API v2.0 — Полный справочник](#4-plugin-api-v20--полный-справочник)
   - [4.1. Профиль и ник Telegram (`fullgram.profile`)](#41-профиль-и-ник-telegram-fullgramprofile)
   - [4.2. Время на телефоне (`fullgram.time`)](#42-время-на-телефоне-fullgramtime)
   - [4.3. Устройство и батарея (`fullgram.device`)](#43-устройство-и-батарея-fullgramdevice)
   - [4.4. Фоновый движок и шина событий (`fullgram.background`)](#44-фоновый-движок-и-шина-событий-fullgrambackground)
   - [4.5. Чаты и сообщения (`fullgram.chat`)](#45-чаты-и-сообщения-fullgramchat)
   - [4.6. Изолированное и общее хранилище (`fullgram.storage`)](#46-изолированное-и-общее-хранилище-fullgramstorage)
   - [4.7. Сеть (`fullgram.net`)](#47-сеть-fullgramnet)
   - [4.8. Криптография и кодирование (`fullgram.crypto`)](#48-криптография-и-кодирование-fullgramcrypto)
   - [4.9. Интерфейс, буфер обмена и логи (`fullgram.ui`)](#49-интерфейс-буфер-обмена-и-логи-fullgramui)
5. [Графический UI плагинов (`open_ui` и `on_ui_event`)](#5-графический-ui-плагинов-open_ui-и-on_ui_event)
6. [Стандартные библиотеки Lua, Python и Rust](#6-стандартные-библиотеки-lua-python-и-rust)
7. [Готовые примеры плагинов v2.0](#7-готовые-примеры-плагинов-v20)
8. [Безопасность и ограничения песочницы](#8-безопасность-и-ограничения-песочницы)
9. [Протокол ИИ-ассистента](#9-протокол-ии-ассистента)

---

## 1. Что нового в Plugin System v2.0

- **Управление ником и профилем Telegram (`fullgram.profile.*`)**:
  - Смена отображаемого имени/ника (`set_name` / `set_nickname`), `@username` (`set_username`) и описания профиля (`set_bio`).
  - Автоматическое сохранение исходного ника пользователя и быстрый возврат (`restore_name()` / `restore_nickname()`).
  - Встроенный шаблонизатор (`format_nick`, `apply_template`) с поддержкой плейсхолдеров времени и батареи (`{time}`, `{time_bold}`, `{time_mono}`, `{time_fancy}`, `{clock}`, `{date}`, `{weekday}`, `{battery}`, `{name}`).
  - Защита от флуд-лимитов Telegram: дедупликация неизменённых значений и встроенный троттлинг MTProto-запросов с отложенной доставкой.
- **Локальное время и параметры телефона (`fullgram.time.*`, `fullgram.device.*`)**:
  - Подробное локальное время телефона (`hm`, `hms`, `date`, `iso`, `year`, `month`, `day`, `hour`, `minute`, `second`, `weekday_name`, `timezone`, `utc_offset_str`, `clock_emoji`, стилизованные цифры `bold_hm`, `mono_hm`, `double_hm`, `fancy_hm`).
  - Информация об устройстве: модель, версия iOS, заряд батареи в %, состояние зарядки, Low Power Mode, активное/фоновое состояние приложения.
  - Стандартные модули времени в языках: `os` (`os.time`, `os.date`, `os.clock`, `os.difftime`) в Lua; расширенный `time` и новый `datetime` в Python.
- **Фоновый режим (`on_background_tick`, `on_app_state`, `on_incoming_message`)**:
  - Выделенный фоновый планировщик (`DispatchSourceTimer` на очереди `.utility`) с индивидуальными интервалами (`5...3600` сек) для каждого плагина.
  - Запрос `UIBackgroundTaskIdentifier` при сворачивании приложения в фон + автоматическая синхронизация при возврате на передний план.
  - Отдельный тумблер в **Настройки → FullGram → Плагины → Фоновый режим плагинов** и в редакторе каждого плагина, плюс кнопка **«⏱ Фон»** для отладки фонового тика в песочнице.
- **Встроенный плагин «Живой Ник и Часы» (`fg_nick_clock`)**:
  - Команды `.nick`, `.nick clock on`, `.nick clock off`, `.nick set <Имя> | <Фамилия>`, `.nick style <bold|mono|double|circled>`, `.nick bio <текст>`, `.nick reset`, `.time`.
  - Нативный графический интерфейс управления живым ником (`kind = "nick_clock"`).

---

## 2. Быстрый старт и метаданные

Плагины выполняются во встроенных изолированных VM под управлением [`FullGramPluginManager`](../submodules/Display/Source/FullGramPluginManager.swift):
- **Lua 5.x** — [`FullGramLuaEngine.swift`](../submodules/Display/Source/FullGramLuaEngine.swift)
- **Python 3** — [`FullGramPythonEngine.swift`](../submodules/Display/Source/FullGramPythonEngine.swift)
- **Rust (скриптовое подмножество)** — [`FullGramRustEngine.swift`](../submodules/Display/Source/FullGramRustEngine.swift)

Первые 45 строк скрипта могут содержать теги в комментариях (`--` для Lua, `#` для Python, `//` для Rust):

| Тег | Описание | Пример |
| --- | --- | --- |
| `@name` | Отображаемое имя плагина | `-- @name Живые часы` |
| `@id` | Уникальный ID (`[a-z0-9_-]`) | `-- @id live_clock` |
| `@version` | Версия скрипта | `-- @version 2.0` |
| `@author` | Автор плагина | `-- @author FullGram` |
| `@description` | Описание в списке плагинов и подсказках | `-- @description Часы в нике` |
| `@background` | Включить фоновый режим (`true` / `false`) | `-- @background true` |
| `@interval` | Интервал фонового тика в секундах (`5...3600`, или `1m`) | `-- @interval 30` |
| `@permission` | Запрашиваемые права (например `net`) | `-- @permission net` |

---

## 3. Хуки жизненного цикла и фоновый режим

### 3.1. `on_load()` и `on_unload()`
Вызываются при инициализации/включении и при выключении/выгрузке плагина. Удобны для начальной настройки `fullgram.background.set_interval(...)` или подписки на события через `fullgram.background.on(...)`.

### 3.2. `on_background_tick(ctx)` (алиасы: `on_tick(ctx)`, `on_timer(ctx)`)
Вызывается автоматически по таймеру (в фоне и при активном приложении), если у плагина включён фоновый режим (`@background true` или тумблер в редакторе, или вызван `fullgram.set_interval(sec)`).

**Поля `ctx`:**
- `ctx.tick` (`int`) — порядковый номер фонового тика для данного плагина.
- `ctx.interval` (`int`) — текущий интервал в секундах.
- `ctx.in_background` (`bool`) — находится ли приложение сейчас в фоне.
- `ctx.app_state` (`string`) — `"foreground"`, `"background"` или `"inactive"`.
- `ctx.time` (`table`) — снимок времени телефона (как в `fullgram.time.now()`).
- `ctx.profile` (`table`) — профиль текущего аккаунта Telegram (как в `fullgram.profile.get()`).
- `ctx.device` (`table`) — состояние устройства и батареи (как в `fullgram.device.info()`).

### 3.3. `on_app_state(ctx)`
Вызывается при переходе приложения между передним планом и фоном.
- `ctx.state` (`string`) — `"foreground"` или `"background"`.
- `ctx.in_background` (`bool`)
- `ctx.time` (`table`)

### 3.4. `on_incoming_message(ctx)`
Вызывается в фоне при получении нового входящего сообщения.
- `ctx.text` (`string`), `ctx.peer_id` (`int`), `ctx.sender_name` (`string`), `ctx.timestamp` (`int`), `ctx.is_group` (`bool`), `ctx.is_channel` (`bool`), `ctx.time` (`table`).

### 3.5. `on_command(ctx)`
Вызывается при отправке `.команда [аргументы]` или `.plug <подкоманда> [аргументы]`.
- **Поля `ctx`:** `command`, `subcommand`, `args`, `text`, `peer_id`, `is_group`, `is_channel`, `chat_stats`.
- **Возврат:** `nil`/`None` (пропустить), строка (отправить заменённый текст), `{ text = "..." }`, или `{ cancel = true, toast = "..." }`.

### 3.6. `on_outgoing_message(ctx)`
Перехват любого исходящего текста перед отправкой (`text`, `peer_id`, `is_group`, `is_channel`).

### 3.7. `on_render_message(ctx)`
Модификация отображаемого текста сообщения (`text`, `peer_id`, `is_incoming`, `message_id`).
> [!WARNING]
> Сетевые вызовы (`http_get`, `http_post`, `http_request`) и `chat.send` внутри `on_render_message` **заблокированы**.

### 3.8. `on_message_action(ctx)` и `on_ui_event(ctx)`
- `on_message_action(ctx)` — действие из контекстного меню сообщения (`text`, `peer_id`).
- `on_ui_event(ctx)` — обработка нажатий в `open_ui` (`action`, `input`).

---

## 4. Plugin API v2.0 — Полный справочник

В API v2.0 все методы доступны **в двух равноправных формах** (для Lua, Python `import fullgram` и Rust `fullgram::...`):
1. **Модульная форма (рекомендуется):** `fullgram.profile.set_name(...)`, `fullgram.time.now()`, `fullgram.device.info()`, `fullgram.background.set_interval(...)`, `fullgram.chat.send(...)`, `fullgram.storage.get(...)`, `fullgram.net.get(...)`, `fullgram.crypto.sha256(...)`, `fullgram.ui.toast(...)`.
2. **Плоская форма (совместимость и краткость):** `fullgram.set_nickname(...)`, `fullgram.get_time()`, `fullgram.get_device_info()`, `fullgram.set_interval(...)`, `fullgram.send_message(...)`, `fullgram.storage_get(...)`, `fullgram.http_get(...)`, `fullgram.toast(...)`.

Версия API доступна через `fullgram.api_version` (`"2.0"`) и `fullgram.version` (`"2.0.0"`).

### 4.1. Профиль и ник Telegram (`fullgram.profile`)

| Модульный вызов | Плоский вызов | Сигнатура и описание |
| --- | --- | --- |
| `fullgram.profile.get()` | `fullgram.get_profile()` | Возвращает таблицу: `id`, `peer_id`, `first_name`, `last_name`, `full_name`, `name`, `username`, `bio`, `phone`, `original_first_name`, `original_last_name`, `updated_at`. |
| `fullgram.profile.set_name(first, last?)` | `fullgram.set_nickname(first, last?)` / `set_name` | Изменяет отображаемое имя/ник в Telegram. При первой смене автоматически сохраняет исходный ник. Дедуплицирует повторы и защищает от флуда. |
| `fullgram.profile.restore_name()` | `fullgram.restore_nickname()` | Восстанавливает исходные имя и фамилию пользователя. |
| `fullgram.profile.set_username(username)` | `fullgram.set_username(username)` | Изменяет `@username` аккаунта (пустая строка снимает username). |
| `fullgram.profile.set_bio(bio)` | `fullgram.set_bio(bio)` | Изменяет текст «О себе» (до 140 символов). |
| `fullgram.profile.format_nick(tpl, style?, base_first?)` | `fullgram.format_nick(...)` | Подставляет плейсхолдеры времени и профиля в шаблон, возвращает строку. |
| `fullgram.profile.apply_template(tpl?, style?, base_first?)` | `fullgram.apply_nick_template(...)` | Форматирует шаблон и сразу устанавливает ник в Telegram. |

**Плейсхолдеры шаблонов ника/био:**
- `{time}` — текущее время `HH:mm` (с выбранным стилем цифр)
- `{time_sec}` — время с секундами `HH:mm:ss`
- `{time_raw}` — обычное `HH:mm` без стилизации
- `{time_bold}` — `𝟏𝟑:𝟒𝟓`, `{time_mono}` — `𝟷𝟹:𝟺𝟻`, `{time_fancy}` — `①③:④⑤`
- `{clock}` — эмодзи часов, соответствующий времени (`🕐`..`🕧`)
- `{date}` — `dd.MM.yyyy`, `{weekday}` — день недели, `{weekday_short}` — краткий день недели
- `{battery}` — заряд батареи в `%`
- `{name}`, `{first_name}`, `{last_name}` — исходное имя пользователя
- `||` — разделитель имени и фамилии в шаблоне (например: `"{name} || ⌚ {time}"`)

### 4.2. Время на телефоне (`fullgram.time`)

| Модульный вызов | Плоский вызов | Описание |
| --- | --- | --- |
| `fullgram.time.now()` | `fullgram.get_time(ts?)` | Возвращает таблицу локального времени телефона (см. поля ниже). |
| `fullgram.time.format(fmt?, ts?, style?)` | `fullgram.format_time(...)` | Форматирует время по маске `DateFormatter` (напр. `"HH:mm:ss"`, `"dd MMM, EEEE"`) и стилю цифр. |
| `fullgram.time.stylize(text, style?)` | `fullgram.stylize_time(text, style?)` | Преобразует цифры в строке в стиль: `"normal"`, `"bold"`, `"mono"`, `"double"`, `"sans"`, `"circled"`. |
| `fullgram.time.timestamp()` | — | Текущее время в секундах (`double`). |
| `fullgram.time.unix_ms()` | — | Текущее время в миллисекундах (`int`). |

**Поля таблицы `fullgram.time.now()`:**
`timestamp`, `unix`, `unix_ms`, `hm` (`"14:35"`), `hms` (`"14:35:08"`), `formatted` (`"23.11.2026 14:35:08"`), `date` (`"23.11.2026"`), `iso`, `year`, `month`, `day`, `hour`, `minute`, `second`, `weekday` (`1..7`), `weekday_name`, `weekday_short`, `month_name`, `timezone`, `timezone_abbr`, `utc_offset`, `utc_offset_str`, `is_24h`, `bold_hm`, `mono_hm`, `double_hm`, `fancy_hm`, `clock_emoji`.

### 4.3. Устройство и батарея (`fullgram.device`)

| Модульный вызов | Плоский вызов | Описание |
| --- | --- | --- |
| `fullgram.device.info()` | `fullgram.get_device_info()` | Таблица: `model`, `system_name`, `system_version`, `battery_level`, `battery_percent`, `battery_state` (`"charging"`, `"full"`, `"unplugged"`), `is_charging`, `is_low_power`, `locale`, `timezone`, `app_state`, `is_background`, `uptime`. |
| `fullgram.device.battery()` | `fullgram.get_battery()` | Таблица: `level`, `percent`, `state`, `is_charging`, `is_low_power`. |
| `fullgram.device.haptic(style?)` | `fullgram.haptic(style?)` | Тактильный отклик: `"light"`, `"medium"`, `"heavy"`, `"success"`, `"warning"`, `"error"`, `"selection"`. |
| `fullgram.device.app_state()` | — | `"foreground"`, `"background"` или `"inactive"`. |

### 4.4. Фоновый движок и шина событий (`fullgram.background`)

| Модульный вызов | Плоский вызов | Описание |
| --- | --- | --- |
| `fullgram.background.set_interval(sec)` | `fullgram.set_interval(sec)` | Включает фоновый тик для плагина с интервалом `5...3600` сек. |
| `fullgram.background.stop_interval()` | `fullgram.stop_interval()` | Останавливает фоновый тик плагина. |
| `fullgram.background.status()` | `fullgram.get_background_status()` | Таблица: `system_enabled`, `plugin_enabled`, `interval`, `tick_count`, `app_state`, `in_background`. |
| `fullgram.background.on(event, fn)` | `fullgram.on_event(event, fn)` | Подписка на пользовательское событие. |
| `fullgram.background.emit(event, data?)` | `fullgram.emit_event(event, data?)` | Отправка события всем активным плагинам (возвращает число вызванных обработчиков). |

### 4.5. Чаты и сообщения (`fullgram.chat`)

| Модульный вызов | Плоский вызов | Описание |
| --- | --- | --- |
| `fullgram.chat.send(text, peer_id?)` | `fullgram.send_message(text, peer_id?)` | Отправить сообщение в указанный или текущий открытый чат. |
| `fullgram.chat.set_draft(text, peer_id?)` | `fullgram.set_draft(text, peer_id?)` | Вставить текст в поле ввода активного чата. |
| `fullgram.chat.active()` | `fullgram.get_active_chat()` | Информация об активном чате (`peer_id`, `is_group`, `is_channel`) или `nil`. |
| `fullgram.chat.stats()` | `fullgram.get_chat_stats()` | Статистика открытого чата (для команд `.plug` / `.info-chat`). |

### 4.6. Изолированное и общее хранилище (`fullgram.storage`)

| Модульный вызов | Плоский вызов | Описание |
| --- | --- | --- |
| `fullgram.storage.get(key, default?)` | `fullgram.storage_get(key, default?)` | Чтение из личного хранилища плагина. |
| `fullgram.storage.set(key, val)` | `fullgram.storage_set(key, val)` | Запись (`nil`/`None` удаляет ключ). |
| `fullgram.storage.delete(key)` | `fullgram.storage_delete(key)` | Удалить ключ. |
| `fullgram.storage.keys()` | `fullgram.storage_keys()` | Список всех ключей данного плагина. |
| `fullgram.storage.clear()` | `fullgram.storage_clear()` | Очистить все ключи данного плагина. |
| `fullgram.storage.shared_get(key, default?)` | `fullgram.shared_get(...)` | Общее хранилище между плагинами FullGram. |
| `fullgram.storage.shared_set(key, val)` | `fullgram.shared_set(...)` | Запись в общее хранилище плагинов. |

### 4.7. Сеть (`fullgram.net`)

| Модульный вызов | Плоский вызов | Описание |
| --- | --- | --- |
| `fullgram.net.get(url, headers?)` | `fullgram.http_get(url, headers?)` | Синхронный `GET`-запрос (до 1 МБ, таймаут 8 с). |
| `fullgram.net.post(url, body?, headers?)` | `fullgram.http_post(url, body?, headers?)` | Синхронный `POST`-запрос. |
| `fullgram.net.request(spec)` | `fullgram.http_request(spec)` | Запрос по таблице `{ url, method, headers, body, timeout }`, возвращает `{ ok, status, body, error }`. |

### 4.8. Криптография и кодирование (`fullgram.crypto`)

- `fullgram.crypto.sha256(str)` / `fullgram.sha256(str)`
- `fullgram.crypto.base64_encode(str)` / `fullgram.base64_encode(str)`
- `fullgram.crypto.base64_decode(str)` / `fullgram.base64_decode(str)`
- `fullgram.crypto.url_encode(str)` / `fullgram.url_encode(str)`
- `fullgram.crypto.url_decode(str)` / `fullgram.url_decode(str)`
- `fullgram.crypto.uuid()` / `fullgram.uuid()`

### 4.9. Интерфейс, буфер обмена и логи (`fullgram.ui`)

- `fullgram.ui.toast(text)` / `fullgram.toast(text)`
- `fullgram.ui.alert(title, message?)` / `fullgram.alert(title, message?)`
- `fullgram.ui.open(spec)` / `fullgram.open_ui(spec)`
- `fullgram.ui.log(...args)` / `fullgram.log(...args)`
- `fullgram.ui.clipboard_get()` / `fullgram.clipboard_get()`
- `fullgram.ui.clipboard_set(text)` / `fullgram.clipboard_set(text)`
- `fullgram.register_command(cmd, fn)`

---

## 5. Графический UI плагинов (`open_ui` и `on_ui_event`)

Встроенные специализированные экраны:
- `kind = "nick_clock"` — панель управления живым ником, шрифтами часов и фоновым интервалом.
- `kind = "deadlines"` — менеджер дедлайнов с чекбоксами.
- `kind = "webview"` — защищённый WebView (`url` на доверенном домене).
- `kind = "custom"` — декларативный экран с карточкой результата, полем ввода и цветными кнопками (`blue`, `green`, `orange`, `red`, `purple`, `indigo`, `teal`, `gray`), вызывающий `on_ui_event(ctx)`.

---

## 6. Стандартные библиотеки Lua, Python и Rust

- **Lua**: `local`, замыкания, `if/elseif/else`, `for`, `pairs/ipairs`, `while`, `repeat/until`, `pcall`, таблицы, `string`, `table`, `math`, `json`, `os` (`os.time()`, `os.date(fmt?, ts?)`, `os.clock()`, `os.difftime()`).
- **Python**: `def`, `lambda`, `if/elif/else`, `for/while`, `try/except`, f-строки, list comprehensions, `dict`/`list`/`tuple`/срезы, `re`, `json`, `math`, `random`, `time` (`time`, `monotonic`, `localtime`, `gmtime`, `strftime`, `ctime`), `datetime` (`datetime.now()`, `datetime.fromtimestamp()`), `fullgram`.
- **Rust**: `fn`, `let`/`let mut`, `if/else`, `match`, `for`/`while`/`loop`, замыкания `|x| ...`, `format!`, `vec!`, строки, `HashMap`, `fullgram::*` (включая `fullgram::profile::set_name`, `fullgram::time::now`, `fullgram::device::info`, `fullgram::background::set_interval`).

---

## 7. Готовые примеры плагинов v2.0

### 7.1. Lua: Живые часы с зарядом батареи в нике (фоновый режим)

```lua
-- @name Часы + Батарея в нике
-- @id nick_battery_clock
-- @version 2.0
-- @author Dev
-- @background true
-- @interval 30
-- @description Обновляет ник в фоне: Имя | ⌚ 14:35 🔋87%

function on_background_tick(ctx)
    local t = ctx.time
    local dev = ctx.device
    local base = ctx.profile.original_first_name
    if base == "" then base = "User" end
    local nick = base .. " | " .. t.clock_emoji .. " " .. t.bold_hm .. " 🔋" .. tostring(dev.battery_level) .. "%"
    fullgram.profile.set_name(nick)
end

function on_command(ctx)
    if ctx.command == "mytime" then
        local t = fullgram.time.now()
        return "Сейчас на телефоне: " .. t.hms .. " (" .. t.date .. ")"
    end
    return nil
end
```

### 7.2. Python: Фоновый логгер входа/фона + время

```python
# @name Монитор активности (Python)
# @id activity_monitor_py
# @version 2.0
# @author Dev
# @background true
# @interval 60
# @description Фиксирует переходы в фон и показывает текущее время

import fullgram
import datetime

def on_app_state(ctx):
    now = datetime.now()
    fullgram.log(f"App state -> {ctx['state']} at {now['hms']}")

def on_background_tick(ctx):
    t = ctx["time"]
    fullgram.log(f"Background tick #{ctx['tick']} | {t['hm']} | battery={ctx['device']['battery_level']}%")

def on_command(ctx):
    if ctx["command"] == "clock":
        now = datetime.now()
        return {"cancel": True, "toast": f"🕒 {now['hms']} • {now['date']}"}
    return None
```

### 7.3. Rust: Быстрая смена ника со временем

```rust
// @name Rust Nick Time
// @id rust_nick_time
// @version 2.0
// @author Dev
// @background true
// @interval 60
// @description Обновляет ник с локальным временем на Rust

use fullgram::*;

fn on_background_tick(ctx: Context) {
    let t = fullgram::time::now();
    let prof = fullgram::profile::get();
    let base = if prof.original_first_name != "" { prof.original_first_name } else { "FullGram" };
    let next_nick = format!("{} [{}]", base, t.hm);
    fullgram::profile::set_name(next_nick);
}

fn on_command(ctx: Context) -> Option<String> {
    if ctx.command == "rtime" {
        let t = fullgram::time::now();
        return Some(format!("🕒 Время телефона: {} ({})", t.hms, t.timezone));
    }
    None
}
```

---

## 8. Безопасность и ограничения песочницы

- **Лимит инструкций (`maxSteps`)**: `120 000` шагов на один вызов хука.
- **Лимит рекурсии (`maxCallDepth`)**: `64` вложенных вызова.
- **Потокобезопасность (`vmLock`)**: все вызовы VM защищены `NSRecursiveLock`.
- **Защита ника Telegram**: минимальный интервал между реальными MTProto-обновлениями ника — `15` секунд; одинаковые значения отфильтровываются без отправки запроса; исходное имя пользователя сохраняется до первой смены.
- **Сеть**: `http://` и `https://` с таймаутом `8.0 с` по умолчанию; запрещено внутри `on_render_message` и на главном потоке.

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
