# FullGram Developer API

Документация по разработке плагинов на **Lua** и **Python**, развёртыванию бесплатного онлайн-каталога плагинов без переустановки клиента, а также устройству модулей безопасности и ИИ-ассистента FullGram.

---

## Содержание

1. [Быстрый старт](#1-быстрый-старт)
2. [Заголовок и метаданные плагина](#2-заголовок-и-метаданные-плагина)
3. [Хуки жизненного цикла](#3-хуки-жизненного-цикла)
4. [Встроенный модуль `fullgram`](#4-встроенный-модуль-fullgram)
5. [Ограничения песочницы и безопасность](#5-ограничения-песочницы-и-безопасность)
6. [Поддерживаемый синтаксис Lua и Python](#6-поддерживаемый-синтаксис-lua-и-python)
7. [Готовые примеры плагинов](#7-готовые-примеры-плагинов)
8. [Бесплатный сервер каталога плагинов (`plugins.json`)](#8-бесплатный-сервер-каталога-плагинов-pluginsjson)
9. [Протокол ИИ-ассистента](#9-протокол-ии-ассистента)

---

## 1. Быстрый старт

Плагины выполняются во встроенных изолированных VM ([`FullGramLuaEngine.swift`](../submodules/Display/Source/FullGramLuaEngine.swift) и [`FullGramPythonEngine.swift`](../submodules/Display/Source/FullGramPythonEngine.swift)) под управлением [`FullGramPluginManager`](../submodules/Display/Source/FullGramPluginManager.swift).

Создать или импортировать плагин можно тремя способами:
1. Внутри приложения: **Настройки → FullGram → Плагины → `+ Новый плагин на Lua / Python`**.
2. Импорт файла `.lua` или `.py` из «Файлов» или прямо из чата (устанавливается выключенным до ручного включения).
3. Установка из **Онлайн-каталога плагинов** (`plugins.json`).

---

## 2. Заголовок и метаданные плагина

Первые 30 строк файла могут содержать теги в комментариях (`--` для Lua, `#` для Python):

| Тег | Описание | Обязательный |
| --- | --- | --- |
| `@name` | Отображаемое имя плагина | Нет (берётся имя файла) |
| `@id` | Уникальный ID (`[a-z0-9_]`), используется для хранения и обновлений | Нет (генерируется из `@name`) |
| `@version` | Версия, например `1.0` | Нет |
| `@author` | Имя или `@username` автора | Нет |
| `@description` | Краткое описание в списке плагинов и в подсказке команд | Нет |
| `@permission` | Разрешения, например `net` (требуется для `fullgram.http_get`) | Нет |

### Пример заголовка (Lua)

```lua
-- @name Погода в чате
-- @id weather_cmd
-- @version 1.0
-- @author shermanko
-- @description Команда .weather [город]
-- @permission net
```

### Пример заголовка (Python)

```python
# @name Текст-мастер
# @id text_master
# @version 1.0
# @author shermanko
# @description Команды .upper и .mock
```

---

## 3. Хуки жизненного цикла

Плагин экспортирует глобальные функции, которые FullGram вызывает автоматически:

### 3.1. `on_command(ctx)`
Вызывается при отправке сообщения вида `.команда [аргументы]` или `.plug <подкоманда> [аргументы]`.

**Поля `ctx`:**
- `ctx.command` (`string`) — имя команды без точки в нижнем регистре (например, `"calc"` или `"plug"`).
- `ctx.subcommand` (`string`) — первое слово аргументов в нижнем регистре (для `.plug info-chat` будет `"info-chat"`).
- `ctx.args` (`string`) — вся строка после первой команды.
- `ctx.text` (`string`) — исходный текст сообщения целиком.
- `ctx.peer_id` (`int`) — числовой ID текущего чата.
- `ctx.is_group` (`bool`) — является ли чат группой/супергруппой.
- `ctx.is_channel` (`bool`) — является ли чат каналом.
- `ctx.chat_stats` (`table | nil`) — предрассчитанная локальная статистика чата (заполняется для команд `.plug` / `.info-chat`).

**Возвращаемое значение:**
- `nil` / `None` — пропустить обработку (передать следующему плагину).
- `string` — заменить текст сообщения на возвращённую строку и отправить её.
- `table` / `dict`:
  - `{ text = "новый текст" }` — заменить текст;
  - `{ cancel = true, toast = "текст" }` — **отменить отправку сообщения** и при наличии показать всплывающее уведомление.

---

### 3.2. `on_outgoing_message(ctx)`
Вызывается перед отправкой любого текстового сообщения (на фоновой очереди).

**Поля `ctx`:** `text`, `peer_id`, `is_group`, `is_channel`.  
**Возврат:** аналогично `on_command` (`nil`/`None`, `string` или `{ cancel = true, toast = "..." }`).

---

### 3.3. `on_render_message(ctx)`
Вызывается при рендере текста сообщения в пузыре (`ChatMessageTextBubbleContentNode`).

**Поля `ctx`:**
- `ctx.text` (`string`)
- `ctx.peer_id` (`int`)
- `ctx.is_incoming` (`bool`)
- `ctx.message_id` (`int`)

**Возврат:** строка (заменяет отображаемый текст на экране без изменения на сервере) или `nil`/`None`.

> [!WARNING]
> Вызов `fullgram.http_get` внутри `on_render_message` **жёстко запрещён** движком для защиты переписки и UI от утечек и тормозов при скролле.

---

### 3.4. `on_message_action(ctx)`
Пользовательское действие для контекстного меню сообщения.

**Поля `ctx`:** `text`, `peer_id`.  
**Возврат:** строка-результат или `nil`/`None`.

---

## 4. Встроенный модуль `fullgram`

В Lua пространство имён `fullgram` доступно глобально; в Python можно использовать как глобально, так и через `import fullgram`.

| Функция | Сигнатура | Описание |
| --- | --- | --- |
| `fullgram.log` | `(...args) -> nil` | Записать строку в консоль плагина (просмотр в редакторе) |
| `fullgram.toast` | `(text: string) -> nil` | Показать всплывающее уведомление в текущем экране |
| `fullgram.clipboard_get` | `() -> string` | Прочитать текст из системного буфера обмена |
| `fullgram.clipboard_set` | `(text: string) -> bool` | Записать текст в системный буфер обмена |
| `fullgram.storage_get` | `(key: string, default?: any) -> any` | Прочитать значение из изолированного хранилища плагина |
| `fullgram.storage_set` | `(key: string, value: any) -> bool` | Сохранить значение (`nil`/`None` удаляет ключ) |
| `fullgram.register_command` | `(cmd: string, fn: function) -> nil` | Зарегистрировать обработчик команды без `on_command` |
| `fullgram.get_chat_stats` | `() -> table \| nil` | Получить статистику открытого чата (для `.plug info-chat` и т.п.) |
| `fullgram.http_get` | `(url: string) -> string \| nil` | Синхронный `HTTPS GET`-запрос (таймаут `1.8 с`, требует `@permission net`) |

### Структура `fullgram.get_chat_stats()`

Доступна при вызове команд `.plug ...` / `.info-chat` ([`fullGramBuildChatStatsSignal`](../submodules/TelegramUI/Sources/FullGramAIOverlay.swift#L1212-L1336)):

```json
{
  "title": "Название чата",
  "first_date": "01.03.2025 14:22",
  "last_date": "16.11.2026 13:55",
  "analyzed_count": 600,
  "top_words": [
    { "word": "привет", "count": 42 }
  ],
  "rare_words": [
    { "word": "синхронизация", "count": 1 }
  ],
  "profanity_count": 3,
  "voice_count": 18,
  "round_count": 7
}
```

---

## 5. Ограничения песочницы и безопасность

- **Лимит инструкций (`maxSteps`)**: `120 000` шагов на один вызов хука — защита от бесконечных циклов.
- **Лимит рекурсии (`maxCallDepth`)**: `64` вложенных вызова — защита от Stack Overflow.
- **Потокобезопасность (`vmLock`)**: все операции VM (`load`, `hasFunction`, `callFunction`, `getGlobal`) защищены `NSRecursiveLock`.
- **Сетевой контроль `http_get`**:
  - требует явного `-- @permission net` / `# @permission net` в заголовке плагина;
  - запрещает `http://`, разрешает **только `https://`**;
  - блокирует `localhost`, `.local`, `.internal`, `.arpa`, IPv6 и приватные/серые IPv4 (`127.*`, `10.*`, `192.168.*`, `172.16-31.*`, `169.254.*`, `100.64-127.*`, `224+.*`);
  - блокируется внутри `on_render_message`.
- **Безопасный бэкап (`.fullgram`)**: все плагины, восстановленные из стороннего `.fullgram` файла или принятые в чате, импортируются с `isEnabled = false`.

---

## 6. Поддерживаемый синтаксис Lua и Python

- **Lua**: `local`, `function`, замыкания, `if/elseif/else`, `for i = a, b`, `for k, v in pairs/ipairs`, `while`, `repeat/until`, `break`, таблицы/массивы, `pcall`, `print`, `tonumber`, `tostring`, `type`, модули `string`, `table`, `math`, `json`.
- **Python**: `def` (параметры по умолчанию), `lambda`, `if/elif/else`, `for/while` (`break`/`continue`), `try/except`, f-строки, list comprehensions, `dict`/`list`/`tuple`/срезы `[a:b]`, встроенные `len`, `range`, `enumerate`, `int`, `float`, `str`, `sorted`, `min`, `max`, `sum`, модули `re`, `json`, `math`, `random`, `time`, `fullgram`.

---

## 7. Готовые примеры плагинов

### Lua: автоподпись или быстрая команда через `register_command`

```lua
-- @name Быстрый статус
-- @id quick_ping
-- @version 1.0
-- @author Dev
-- @description Команда .ping проверяет работу плагина

fullgram.register_command("ping", function(ctx)
    local n = tonumber(fullgram.storage_get("pings", 0)) + 1
    fullgram.storage_set("pings", n)
    return { cancel = true, toast = "Pong! Вызовов: " .. tostring(n) }
end)
```

### Lua: подкоманда `.plug` со статистикой чата

```lua
-- @name Счётчик ГС и кружков
-- @id media_brief
-- @version 1.0
-- @author Dev
-- @description Команда .plug media выводит число голосовых и кружков

function on_command(ctx)
    if ctx.command == "plug" and ctx.subcommand == "media" then
        local st = fullgram.get_chat_stats()
        if not st then
            return { cancel = true, toast = "Нет данных по чату" }
        end
        return "🎤 ГС: " .. tostring(st.voice_count) .. " | ⭕️ Кружков: " .. tostring(st.round_count)
    end
    return nil
end
```

### Python: сетевая команда с `@permission net`

```python
# @name Курс BTC
# @id btc_price
# @version 1.0
# @author Dev
# @description Команда .btc вставляет текущий курс BTC/USDT
# @permission net

import json
import fullgram

def on_command(ctx):
    if ctx["command"] == "btc":
        raw = fullgram.http_get("https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT")
        if not raw:
            return {"cancel": True, "toast": "Не удалось получить курс"}
        data = json.loads(raw)
        return f"₿ BTC/USDT: {data['price']}"
    return None
```

---

## 8. Бесплатный сервер каталога плагинов (`plugins.json`)

В FullGram встроен клиентский загрузчик каталога ([`fetchRemoteCatalog`](../submodules/Display/Source/FullGramPluginManager.swift#L1052-L1118) и экран **Плагины → Каталог плагинов с сервера**). Вы можете выкладывать и обновлять плагины для всех пользователей без пересборки приложения.

### Формат `plugins.json`

```json
{
  "version": 1,
  "plugins": [
    {
      "id": "fg_chat_info",
      "name": "1. Информация о чате",
      "language": "lua",
      "version": "1.0",
      "author": "shermanko",
      "description": "Команда .plug info-chat: даты, частые/редкие слова, маты, ГС и кружки",
      "url": "https://cdn.jsdelivr.net/gh/<USER>/fullgram-plugins@main/scripts/info-chat.lua"
    }
  ]
}
```

Поле `url` (строго `https://`, до `256 КБ`) можно заменить на inline-поле `"code": "..."`, если скрипт небольшой.

### Бесплатный хостинг (0 ₽)

1. **GitHub + Raw / jsDelivr CDN**:
   - Создайте публичный репозиторий `fullgram-plugins` и поместите в него `plugins.json` + папку `scripts/`.
   - В приложении укажите ссылку:
     - `https://raw.githubusercontent.com/<USER>/fullgram-plugins/main/plugins.json` или
     - `https://cdn.jsdelivr.net/gh/<USER>/fullgram-plugins@main/plugins.json`.
   - Для публикации нового плагина достаточно сделать `git push`.
2. **Cloudflare Workers + KV**:
   - Бесплатный тариф до 100 000 запросов в сутки с готовым `https://*.workers.dev`.
   - Позволяет подключить админ-бота в Telegram: вы отправляете файл `.lua`/`.py` боту → воркер сохраняет его в KV → каталог по `https://<worker>.workers.dev/plugins.json` обновляется мгновенно.

---

## 9. Протокол ИИ-ассистента

Собственный ИИ-агент настраивается в [`FullGramAIAssistant.swift`](../submodules/Display/Source/FullGramAIAssistant.swift) и управляет чатами через [`FullGramAIOverlay.swift`](../submodules/TelegramUI/Sources/FullGramAIOverlay.swift):

- **Хранение API-ключей**: iOS Keychain (`FullGram.AIAssistant.Keys`), без записи в бэкапы.
- **Поддерживаемые API**: OpenAI Chat Completions, OpenRouter, Groq, Anthropic Messages (`x-api-key`) и кастомный `https://` / `http://localhost` (Ollama).
- **Изоляция данных**: чужие сообщения передаются в `[UNTRUSTED_CHAT_DATA]`, а точные счётчики за дату (например, `.ai ... 15.05.2026`) передаются в `[VERIFIED_LOCAL_STATS]` после локального вызова `searchMessages`.
- **Действия агента**: в конце ответа модель может предложить ровно 1 JSON-блок `[[FULLGRAM_ACTION:{...}]]` с `kind` из белого списка: `insert_draft`, `send_message`, `open_chat`, `toggle_setting` (`ghost_mode`, `download_boost`, `floating_pet`, `quick_formatting`). Отправка сообщений и изменение настроек всегда требуют ручного подтверждения кнопкой в окне ассистента.
