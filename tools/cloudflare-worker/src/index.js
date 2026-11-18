const DEFAULT_OWNER_ID = "8899688273";
const MAX_SCRIPT_BYTES = 256 * 1024;

const DEFAULT_BADGES = {
  version: 1,
  roles: {
    creator: {
      label: "Создатель FullGram",
      shortLabel: "CREATOR",
      emoji: "👑",
      color: "#FF9500"
    },
    official: {
      label: "Официальный ресурс FullGram",
      shortLabel: "FULLGRAM",
      emoji: "🛡",
      color: "#007AFF"
    },
    premium: {
      label: "FullGram+",
      shortLabel: "FG+",
      emoji: "💎",
      color: "#AF52DE"
    },
    dev: {
      label: "Разработчик",
      shortLabel: "DEV",
      emoji: "⚡",
      color: "#34C759"
    }
  },
  users: {
    "8899688273": "creator"
  },
  usernames: {
    shermanko: "creator",
    fullgram_mod: "official",
    fullgramgroup: "official"
  }
};

const DEFAULT_PLUGINS = {
  version: 1,
  plugins: [
    {
      id: "fg_layout_fixer",
      name: "Исправление раскладки (.fix)",
      language: "python",
      version: "1.0",
      author: "FullGram",
      description: "Команда .fix <текст>: переводит раскладку (по умолчанию Рус → Англ, направление меняется во вкладке Плагины).",
      code: `# @name Исправление раскладки (.fix)
# @id fg_layout_fixer
# @version 1.0
# @author FullGram
# @description Команда .fix <текст>: переводит раскладку (по умолчанию Рус → Англ, меняется во вкладке Плагины)

import fullgram

RU_CHARS = "йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ"
EN_CHARS = "qwertyuiop[]asdfghjkl;'zxcvbnm,.\`QWERTYUIOP{}ASDFGHJKL:\\"ZXCVBNM<>~"

def convert_text(text, direction):
    out = ""
    for ch in text:
        if direction == "ru2en":
            idx = RU_CHARS.find(ch)
            out = out + (EN_CHARS[idx] if idx >= 0 else ch)
        elif direction == "en2ru":
            idx = EN_CHARS.find(ch)
            out = out + (RU_CHARS[idx] if idx >= 0 else ch)
    return out

def on_command(ctx):
    if ctx["command"] != "fix":
        return None
    raw = str(ctx["args"]).strip()
    if not raw:
        mode = str(fullgram.storage_get("mode", "ru2en"))
        return {"cancel": True, "toast": f"Формат: .fix <текст> (режим: {mode})"}

    lower_raw = raw.lower()
    if lower_raw == "mode ru2en":
        fullgram.storage_set("mode", "ru2en")
        return {"cancel": True, "toast": "Раскладка .fix: Русский → Английский"}
    elif lower_raw == "mode en2ru":
        fullgram.storage_set("mode", "en2ru")
        return {"cancel": True, "toast": "Раскладка .fix: Английский → Русский"}
    elif lower_raw == "mode auto":
        fullgram.storage_set("mode", "auto")
        return {"cancel": True, "toast": "Раскладка .fix: Авто (Рус ↔ Англ)"}

    mode = str(fullgram.storage_get("mode", "ru2en"))
    direction = mode
    if mode == "auto":
        ru_count = 0
        en_count = 0
        for ch in raw:
            if RU_CHARS.find(ch) >= 0:
                ru_count = ru_count + 1
            elif EN_CHARS.find(ch) >= 0:
                en_count = en_count + 1
        direction = "ru2en" if ru_count >= en_count else "en2ru"

    return convert_text(raw, direction)
`
    },
    {
      id: "fg_casino",
      name: "Казино (.slots / .roulette / .bal)",
      language: "lua",
      version: "1.0",
      author: "FullGram",
      description: "Слоты (.slots [ставка]), рулетка (.roulette red/black/green [ставка]), монетка (.coin) и баланс фишек (.bal).",
      code: `-- @name Казино (.slots / .roulette / .bal)
-- @id fg_casino
-- @version 1.0
-- @author FullGram
-- @description Слоты (.slots [ставка]), рулетка (.roulette red/black/green [ставка]), монетка (.coin) и баланс фишек (.bal)

function get_balance()
    local b = tonumber(fullgram.storage_get("balance", 1000))
    if b == nil then return 1000 end
    return b
end

function set_balance(val)
    fullgram.storage_set("balance", val)
    local best = tonumber(fullgram.storage_get("best_balance", 1000)) or 1000
    if val > best then
        fullgram.storage_set("best_balance", val)
    end
end

function on_command(ctx)
    local cmd = ctx.command
    local args = tostring(ctx.args or "")

    if cmd == "bal" or cmd == "casino" then
        local bal = get_balance()
        local best = tonumber(fullgram.storage_get("best_balance", 1000)) or 1000
        if args == "bonus" or bal < 50 then
            bal = bal + 1000
            set_balance(bal)
            return "🎁 Бонус казино FullGram начислен: +1000 🪙\\n💰 Текущий баланс: " .. tostring(bal) .. " 🪙 (Рекорд: " .. tostring(best) .. " 🪙)"
        end
        return "🎰 Казино FullGram\\n💰 Баланс: " .. tostring(bal) .. " 🪙 (Рекорд: " .. tostring(best) .. " 🪙)\\nКоманды: .slots [ставка], .roulette red/black/green [ставка], .coin [ставка], .bal bonus"
    end

    if cmd == "slots" then
        local bal = get_balance()
        if bal <= 0 then
            bal = 500
            set_balance(bal)
        end
        local bet = tonumber(args) or 100
        if bet < 10 then bet = 10 end
        if bet > bal then bet = bal end

        local symbols = {"🍒", "🍋", "🔔", "💎", "7️⃣"}
        local r1 = math.random(1, 5)
        local r2 = math.random(1, 5)
        local r3 = math.random(1, 5)
        local s1 = symbols[r1]
        local s2 = symbols[r2]
        local s3 = symbols[r3]

        local mult = 0
        local status = "❌ Мимо!"
        if r1 == 5 and r2 == 5 and r3 == 5 then
            mult = 15
            status = "🔥 МЕГА ДЖЕКПОТ 777 (x15)!"
        elseif r1 == r2 and r2 == r3 then
            mult = 7
            status = "🎉 ДЖЕКПОТ 3 В РЯД (x7)!"
        elseif r1 == r2 or r2 == r3 or r1 == r3 then
            mult = 2
            status = "✨ Совпадение 2 из 3 (x2)!"
        end

        local delta = (mult > 0) and (bet * (mult - 1)) or (-bet)
        bal = bal + delta
        set_balance(bal)
        local sign = (delta >= 0) and ("+" .. tostring(delta)) or tostring(delta)

        return "🎰 Слоты FullGram | Ставка: " .. tostring(bet) .. " 🪙\\n"
            .. "┏━━━━━━━━━━━┓\\n"
            .. "┃  " .. s1 .. " │ " .. s2 .. " │ " .. s3 .. "  ┃\\n"
            .. "┗━━━━━━━━━━━┛\\n"
            .. status .. " (" .. sign .. " 🪙)\\n"
            .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
    end

    if cmd == "roulette" or cmd == "roul" then
        local bal = get_balance()
        if bal <= 0 then bal = 500 end
        local choice = string.lower(ctx.subcommand or "red")
        local bet_str = string.match(args, "%s+(%d+)$")
        local bet = tonumber(bet_str) or 100
        if bet > bal then bet = bal end

        local num = math.random(0, 36)
        local color = "black"
        local badge = "⚫️ Чёрное"
        if num == 0 then
            color = "green"
            badge = "🟢 Зеро (0)"
        elseif num % 2 == 1 then
            color = "red"
            badge = "🔴 Красное"
        end

        local win = false
        local mult = 2
        if (choice == "green" or choice == "0" or choice == "зеленое" or choice == "зеро") and color == "green" then
            win = true
            mult = 14
        elseif (choice == "red" or choice == "красное" or choice == "к") and color == "red" then
            win = true
        elseif (choice == "black" or choice == "черное" or choice == "ч") and color == "black" then
            win = true
        end

        local delta = win and (bet * (mult - 1)) or (-bet)
        bal = bal + delta
        set_balance(bal)
        local outcome = win and ("✅ Выигрыш: +" .. tostring(delta) .. " 🪙") or ("❌ Проигрыш: " .. tostring(delta) .. " 🪙")

        return "🎡 Рулетка FullGram\\nВыпало: " .. badge .. " [" .. tostring(num) .. "]\\n" .. outcome .. "\\n💰 Баланс: " .. tostring(bal) .. " 🪙"
    end

    if cmd == "coin" then
        local bal = get_balance()
        if bal <= 0 then bal = 500 end
        local bet = tonumber(args) or 100
        if bet > bal then bet = bal end
        local side = (math.random(1, 2) == 1) and "🦅 Орёл" or "🪙 Решка"
        local win = (math.random(1, 2) == 1)
        local delta = win and bet or (-bet)
        bal = bal + delta
        set_balance(bal)
        local res = win and ("✅ Победа! +" .. tostring(bet) .. " 🪙") or ("❌ Не повезло: -" .. tostring(bet) .. " 🪙")
        return "🪙 Монетка: выпал " .. side .. "\\n" .. res .. " (Баланс: " .. tostring(bal) .. " 🪙)"
    end

    return nil
end
`
    },
    {
      id: "fg_anti_typos",
      name: "Анти-опечатки",
      language: "python",
      version: "1.0",
      author: "FullGram",
      description: "Автоматически исправляет частые клавиатурные опечатки, двойные заглавные буквы и лишние пробелы перед знаками препинания.",
      code: `# @name Анти-опечатки
# @id fg_anti_typos
# @version 1.0
# @author FullGram
# @description Автоматически исправляет клавиатурные опечатки, двойные заглавные буквы и пробелы у знаков препинания (без сленг-макросов)

import re

TYPOS = {
    "привте": "привет",
    "првиет": "привет",
    "спсаибо": "спасибо",
    "спаисбо": "спасибо",
    "пожалусйта": "пожалуйста",
    "пожалйста": "пожалуйста",
    "сегодян": "сегодня",
    "сейчса": "сейчас",
    "хороош": "хорошо",
    "хоршо": "хорошо",
    "вообщше": "вообще",
    "вобще": "вообще",
    "кстти": "кстати",
    "кстаит": "кстати",
    "почмеу": "почему",
    "ничгео": "ничего",
    "коненчо": "конечно",
    "протсо": "просто",
    "толкьо": "только",
    "склько": "сколько",
    "извиин": "извини",
    "поянл": "понял",
    "будте": "будет",
    "можте": "может",
    "делате": "делает",
    "нраивтся": "нравится",
    "смотир": "смотри",
    "каежтся": "кажется"
}

def fix_word(w):
    if len(w) >= 3 and w[0] == w[0].upper() and w[1] == w[1].upper() and w[2] == w[2].lower() and w[0] != w[0].lower():
        w = w[0] + w[1:].lower()
    low = w.lower()
    if low in TYPOS:
        fixed = TYPOS[low]
        if w[0] == w[0].upper() and w[0] != w[0].lower():
            return fixed[0].upper() + fixed[1:]
        return fixed
    return w

def clean_text(text):
    if not text or text.startswith("."):
        return text
    out = re.sub(r"[ \\t]{2,}", " ", text)
    out = re.sub(r"\\s+([,.:;!?])", r"\\1", out)
    words = out.split(" ")
    res = []
    for w in words:
        if not w:
            continue
        punct = ""
        core = w
        if len(w) > 1 and w[-1] in ",.!?:;":
            punct = w[-1]
            core = w[:-1]
        res.append(fix_word(core) + punct)
    return " ".join(res)

def on_outgoing_message(ctx):
    original = str(ctx["text"])
    if not original or original.startswith("."):
        return None
    fixed = clean_text(original)
    if fixed != original:
        return fixed
    return None

def on_command(ctx):
    if ctx["command"] == "typo":
        sample = str(ctx["args"]).strip()
        if sample:
            return clean_text(sample)
        return {"cancel": True, "toast": "Анти-опечатки активны! Проверьте: .typo ПРивте , сегодян хороош"}
    return None
`
    },
    {
      id: "fg_deadlines",
      name: "Дедлайны (.dl / .deadline)",
      language: "python",
      version: "1.0",
      author: "FullGram",
      description: "Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear.",
      code: `# @name Дедлайны (.dl / .deadline)
# @id fg_deadlines
# @version 1.0
# @author FullGram
# @description Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear

import fullgram
import json

def load_items():
    raw = str(fullgram.storage_get("dl_json", "[]"))
    data = json.loads(raw)
    if data:
        return data
    return []

def save_items(items):
    fullgram.storage_set("dl_json", json.dumps(items))

def format_list(items):
    if len(items) == 0:
        return "⏰ Дедлайнов пока нет.\\nДобавьте: .dl add Завтра 18:00 | Сдать проект"
    lines = ["⏰ Список дедлайнов FullGram:", "━━━━━━━━━━━━━━━━━━━━"]
    for idx, item in enumerate(items):
        status = "✅" if item.get("done", False) else "⏳"
        due = item.get("due", "Без срока")
        task = item.get("task", "")
        num = idx + 1
        lines.append(f"{num}. {status} [{due}] — {task}")
    return "\\n".join(lines)

def on_command(ctx):
    cmd = ctx["command"]
    if cmd != "dl" and cmd != "deadline":
        return None

    raw = str(ctx["args"]).strip()
    items = load_items()

    if not raw or raw == "list":
        return {"cancel": True, "toast": format_list(items)}

    if raw == "send":
        return format_list(items)

    if raw == "clear":
        save_items([])
        return {"cancel": True, "toast": "Все дедлайны очищены."}

    if raw.startswith("done "):
        idx_str = raw[5:].strip()
        idx = int(idx_str) - 1
        if idx >= 0 and idx < len(items):
            cur = items[idx]
            updated = []
            for i, it in enumerate(items):
                if i == idx:
                    updated.append({"due": cur.get("due", ""), "task": cur.get("task", ""), "done": True})
                else:
                    updated.append(it)
            save_items(updated)
            return {"cancel": True, "toast": f"✅ Дедлайн №{idx + 1} выполнен!"}
        return {"cancel": True, "toast": "Неверный номер дедлайна."}

    if raw.startswith("del "):
        idx_str = raw[4:].strip()
        idx = int(idx_str) - 1
        if idx >= 0 and idx < len(items):
            updated = []
            for i, it in enumerate(items):
                if i != idx:
                    updated.append(it)
            save_items(updated)
            return {"cancel": True, "toast": f"🗑 Дедлайн №{idx + 1} удалён."}
        return {"cancel": True, "toast": "Неверный номер дедлайна."}

    body = raw[4:].strip() if raw.startswith("add ") else raw
    due = "Срочно"
    task = body
    if "|" in body:
        parts = body.split("|")
        due = parts[0].strip()
        task = parts[1].strip()
    else:
        words = body.split(" ")
        if len(words) >= 2:
            due = words[0]
            task = " ".join(words[1:])

    new_list = items + [{"due": due, "task": task, "done": False}]
    save_items(new_list)
    return {"cancel": True, "toast": f"⏰ Дедлайн добавлен: [{due}] {task}"}
`
    }
  ]
};

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*"
    }
  });
}

function timingSafeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) {
    diff |= ab[i] ^ bb[i];
  }
  return diff === 0;
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function expectedWebhookSecret(env) {
  if (!env.ADMIN_TOKEN) return null;
  const hex = await sha256Hex(`${env.ADMIN_TOKEN}:tg-webhook`);
  return hex.slice(0, 48);
}

function isAuthorizedAdmin(request, env) {
  if (!env.ADMIN_TOKEN) return false;
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) return false;
  const token = auth.slice(7).trim();
  return timingSafeEqual(token, env.ADMIN_TOKEN);
}

async function loadBadges(env) {
  if (!env.FULLGRAM_KV) return structuredClone(DEFAULT_BADGES);
  const raw = await env.FULLGRAM_KV.get("badges.json");
  if (!raw) return structuredClone(DEFAULT_BADGES);
  try {
    const parsed = JSON.parse(raw);
    return {
      version: parsed.version || 1,
      roles: { ...DEFAULT_BADGES.roles, ...(parsed.roles || {}) },
      users: { ...DEFAULT_BADGES.users, ...(parsed.users || {}) },
      usernames: { ...DEFAULT_BADGES.usernames, ...(parsed.usernames || {}) }
    };
  } catch {
    return structuredClone(DEFAULT_BADGES);
  }
}

async function saveBadges(env, badges) {
  await env.FULLGRAM_KV.put("badges.json", JSON.stringify(badges, null, 2));
}

async function loadPlugins(env) {
  const base = structuredClone(DEFAULT_PLUGINS.plugins);
  if (!env.FULLGRAM_KV) return { version: 1, plugins: base };
  const raw = await env.FULLGRAM_KV.get("plugins.json");
  if (!raw) return { version: 1, plugins: base };
  try {
    const parsed = JSON.parse(raw);
    const kvList = Array.isArray(parsed.plugins) ? parsed.plugins : [];
    const byId = new Map();
    for (const p of base) byId.set(p.id, p);
    for (const p of kvList) byId.set(p.id, p);
    return {
      version: parsed.version || 1,
      plugins: Array.from(byId.values())
    };
  } catch {
    return { version: 1, plugins: base };
  }
}

async function savePlugins(env, catalog) {
  await env.FULLGRAM_KV.put("plugins.json", JSON.stringify(catalog, null, 2));
}

function normalizeId(raw, fallback) {
  const src = (raw || fallback || "plugin").toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_+|_+$/g, "");
  return src || `plugin_${Date.now()}`;
}

function parsePluginMetadata(code, filename, language) {
  const lines = String(code || "").split(/\r?\n/).slice(0, 40);
  const prefix = language === "python" ? "#" : "--";
  const tags = {};
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith(prefix)) continue;
    const body = trimmed.slice(prefix.length).trim();
    const m = body.match(/^@(id|name|version|author|description)\s+(.+)$/i);
    if (m) {
      tags[m[1].toLowerCase()] = m[2].trim();
    }
  }
  const baseName = String(filename || "plugin").replace(/\.(lua|py)$/i, "");
  const name = tags.name || baseName;
  const id = normalizeId(tags.id, name);
  return {
    id,
    name,
    version: tags.version || "1.0",
    author: tags.author || "shermanko",
    description: tags.description || ""
  };
}

async function applyBadgeChange(env, body) {
  const badges = await loadBadges(env);
  const peerId = body.peerId != null ? String(body.peerId).trim() : "";
  const cleanUser = typeof body.username === "string"
    ? body.username.trim().replace(/^@+/, "").toLowerCase()
    : "";

  if (!peerId && !cleanUser) {
    throw new Error("peerId or username is required");
  }

  const enabled = body.enabled !== false;
  const customRoleKey = peerId ? `user_${peerId}` : `name_${cleanUser}`;

  if (!enabled) {
    if (peerId) delete badges.users[peerId];
    if (cleanUser) delete badges.usernames[cleanUser];
    delete badges.roles[customRoleKey];
    await saveBadges(env, badges);
    return badges;
  }

  const requestedRole = typeof body.roleId === "string" ? body.roleId.trim() : "";
  const customEmojiId = body.customEmojiId != null && String(body.customEmojiId).trim() !== ""
    ? String(body.customEmojiId).trim()
    : null;
  const emoji = typeof body.emoji === "string" && body.emoji.trim() ? body.emoji.trim() : null;
  const label = typeof body.label === "string" && body.label.trim() ? body.label.trim() : null;
  const shortLabel = typeof body.shortLabel === "string" && body.shortLabel.trim() ? body.shortLabel.trim() : null;
  const color = typeof body.color === "string" && /^#[0-9a-fA-F]{6}$/.test(body.color.trim())
    ? body.color.trim()
    : null;

  const baseRole = badges.roles[requestedRole] || DEFAULT_BADGES.roles.premium;
  const hasOverrides = Boolean(
    customEmojiId ||
    (label && label !== baseRole.label) ||
    (shortLabel && shortLabel !== (baseRole.shortLabel || baseRole.label)) ||
    (emoji && emoji !== baseRole.emoji) ||
    (color && color.toUpperCase() !== String(baseRole.color || "").toUpperCase()) ||
    !badges.roles[requestedRole]
  );

  let assignedRoleId = requestedRole || "premium";
  if (hasOverrides) {
    assignedRoleId = customRoleKey;
    const roleObj = {
      label: label || baseRole.label || "FullGram+",
      shortLabel: shortLabel || baseRole.shortLabel || "FG+",
      emoji: emoji || baseRole.emoji || "💎",
      color: color || baseRole.color || "#AF52DE"
    };
    if (customEmojiId) {
      roleObj.customEmojiId = customEmojiId;
    }
    badges.roles[assignedRoleId] = roleObj;
  } else {
    delete badges.roles[customRoleKey];
  }

  if (peerId) badges.users[peerId] = assignedRoleId;
  if (cleanUser) badges.usernames[cleanUser] = assignedRoleId;

  await saveBadges(env, badges);
  return badges;
}

async function upsertPlugin(env, origin, { id, name, language, version, author, description, code }) {
  const lang = language === "python" ? "python" : "lua";
  const ext = lang === "python" ? "py" : "lua";
  const parsed = parsePluginMetadata(code, name || id, lang);
  const finalId = normalizeId(id || parsed.id, parsed.name);
  const finalName = (name && name.trim()) || parsed.name;
  const finalVersion = (version && version.trim()) || parsed.version;
  const finalAuthor = (author && author.trim()) || parsed.author;
  const finalDesc = (description != null ? String(description).trim() : "") || parsed.description;

  const bytes = new TextEncoder().encode(code);
  if (!bytes.length || bytes.length > MAX_SCRIPT_BYTES) {
    throw new Error("Plugin code must be between 1 byte and 256 KB");
  }

  await env.FULLGRAM_KV.put(`script:${finalId}`, code);
  const catalog = await loadPlugins(env);
  const item = {
    id: finalId,
    name: finalName,
    language: lang,
    version: finalVersion,
    author: finalAuthor,
    description: finalDesc,
    url: `${origin}/scripts/${finalId}.${ext}`
  };
  const idx = catalog.plugins.findIndex((p) => p.id === finalId);
  if (idx >= 0) {
    catalog.plugins[idx] = item;
  } else {
    catalog.plugins.push(item);
  }
  await savePlugins(env, catalog);
  return item;
}

async function deletePluginById(env, pluginId) {
  const cleanId = String(pluginId || "").trim();
  if (!cleanId) return false;
  const catalog = await loadPlugins(env);
  const before = catalog.plugins.length;
  catalog.plugins = catalog.plugins.filter((p) => p.id !== cleanId);
  await env.FULLGRAM_KV.delete(`script:${cleanId}`);
  if (catalog.plugins.length !== before) {
    await savePlugins(env, catalog);
    return true;
  }
  return false;
}

async function sendTelegramMessage(env, chatId, text) {
  if (!env.TG_BOT_TOKEN) return;
  await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      disable_web_page_preview: true
    })
  });
}

async function handleTelegramWebhook(request, env, origin) {
  const expected = await expectedWebhookSecret(env);
  if (expected) {
    const provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token") || "";
    if (!timingSafeEqual(provided, expected)) {
      return new Response("Forbidden", { status: 403 });
    }
  }

  let update;
  try {
    update = await request.json();
  } catch {
    return jsonResponse({ ok: true });
  }

  const msg = update.message || update.edited_message;
  if (!msg || !msg.from) {
    return jsonResponse({ ok: true });
  }

  const ownerId = String(env.ADMIN_TG_ID || DEFAULT_OWNER_ID).trim();
  const senderId = String(msg.from.id);
  const chatId = msg.chat?.id ?? msg.from.id;

  if (senderId !== ownerId) {
    await sendTelegramMessage(env, chatId, "⛔ Доступ запрещён. Этот бот работает только для владельца FullGram.");
    return jsonResponse({ ok: true });
  }

  if (msg.document) {
    const fileName = msg.document.file_name || "";
    const lower = fileName.toLowerCase();
    if (!lower.endsWith(".lua") && !lower.endsWith(".py")) {
      await sendTelegramMessage(env, chatId, "❌ Отправьте файл с расширением .lua или .py.");
      return jsonResponse({ ok: true });
    }
    if ((msg.document.file_size || 0) > MAX_SCRIPT_BYTES) {
      await sendTelegramMessage(env, chatId, "❌ Скрипт слишком большой (максимум 256 КБ).");
      return jsonResponse({ ok: true });
    }

    const fileMetaRes = await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/getFile?file_id=${encodeURIComponent(msg.document.file_id)}`);
    const fileMeta = await fileMetaRes.json();
    if (!fileMeta.ok || !fileMeta.result?.file_path) {
      await sendTelegramMessage(env, chatId, "❌ Не удалось получить файл от Telegram API.");
      return jsonResponse({ ok: true });
    }

    const fileRes = await fetch(`https://api.telegram.org/file/bot${env.TG_BOT_TOKEN}/${fileMeta.result.file_path}`);
    if (!fileRes.ok) {
      await sendTelegramMessage(env, chatId, `❌ Ошибка скачивания файла: HTTP ${fileRes.status}`);
      return jsonResponse({ ok: true });
    }

    const code = await fileRes.text();
    const language = lower.endsWith(".py") ? "python" : "lua";
    const caption = (msg.caption || "").trim();
    let customName = null;
    let customDesc = null;
    if (caption && !caption.startsWith("/")) {
      if (caption.includes("|")) {
        const [n, d] = caption.split("|", 2);
        customName = n.trim();
        customDesc = d.trim();
      } else {
        customDesc = caption;
      }
    }

    try {
      const saved = await upsertPlugin(env, origin, {
        name: customName || fileName.replace(/\.(lua|py)$/i, ""),
        language,
        description: customDesc,
        code
      });
      await sendTelegramMessage(
        env,
        chatId,
        `✅ Плагин опубликован в маркет FullGram!\n\nНазвание: ${saved.name}\nID: ${saved.id}\nЯзык: ${saved.language}\nВерсия: ${saved.version}\nURL: ${saved.url}`
      );
    } catch (err) {
      await sendTelegramMessage(env, chatId, `❌ Ошибка публикации: ${err.message}`);
    }
    return jsonResponse({ ok: true });
  }

  const text = (msg.text || "").trim();
  if (!text) return jsonResponse({ ok: true });

  if (text.startsWith("/start") || text.startsWith("/help")) {
    await sendTelegramMessage(
      env,
      chatId,
      "🛠 Админ-бот маркета FullGram\n\n" +
      "• Отправьте файл .lua или .py, чтобы опубликовать/обновить плагин в маркете.\n" +
      "• Подпись к файлу: описание или «Название | Описание».\n" +
      "• В начале скрипта можно указать @name, @id, @version, @author, @description.\n\n" +
      "Команды:\n" +
      "/list — список плагинов в маркете\n" +
      "/del <id> — удалить плагин из маркета\n" +
      "/badge <id_или_@username> <creator|official|premium|dev|off> — выдать или снять бейдж"
    );
    return jsonResponse({ ok: true });
  }

  if (text.startsWith("/list") || text.startsWith("/plugins")) {
    const catalog = await loadPlugins(env);
    if (!catalog.plugins.length) {
      await sendTelegramMessage(env, chatId, "📦 В маркете пока нет плагинов.");
    } else {
      const lines = catalog.plugins.map((p, i) => `${i + 1}. ${p.name} (${p.id}) [${p.language}] v${p.version}`);
      await sendTelegramMessage(env, chatId, `📦 Плагины в маркете (${catalog.plugins.length}):\n\n` + lines.join("\n"));
    }
    return jsonResponse({ ok: true });
  }

  if (text.startsWith("/del ")) {
    const id = text.slice(5).trim();
    const removed = await deletePluginById(env, id);
    await sendTelegramMessage(
      env,
      chatId,
      removed ? `🗑 Плагин «${id}» удалён из маркета.` : `⚠️ Плагин «${id}» не найден.`
    );
    return jsonResponse({ ok: true });
  }

  if (text.startsWith("/badge ")) {
    const parts = text.slice(7).trim().split(/\s+/);
    if (parts.length < 2) {
      await sendTelegramMessage(env, chatId, "Формат: /badge <user_id_или_@username> <creator|official|premium|dev|off>");
      return jsonResponse({ ok: true });
    }
    const target = parts[0];
    const role = parts[1].toLowerCase();
    const isNumeric = /^-?\d+$/.test(target);
    try {
      await applyBadgeChange(env, {
        peerId: isNumeric ? target : undefined,
        username: isNumeric ? undefined : target,
        enabled: role !== "off" && role !== "none" && role !== "remove",
        roleId: role
      });
      await sendTelegramMessage(
        env,
        chatId,
        role === "off" || role === "none" || role === "remove"
          ? `✅ Бейдж снят с ${target}.`
          : `✅ Бейдж «${role}» выдан ${target}.`
      );
    } catch (err) {
      await sendTelegramMessage(env, chatId, `❌ Ошибка: ${err.message}`);
    }
    return jsonResponse({ ok: true });
  }

  return jsonResponse({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    const origin = url.origin;

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization"
        }
      });
    }

    if (request.method === "GET" && path === "/health") {
      return jsonResponse({ ok: true, service: "fullgram-worker" });
    }

    if (request.method === "GET" && path === "/badges.json") {
      return jsonResponse(await loadBadges(env));
    }

    if (request.method === "GET" && path === "/plugins.json") {
      return jsonResponse(await loadPlugins(env));
    }

    if (request.method === "GET" && path.startsWith("/scripts/")) {
      const filePart = path.slice("/scripts/".length);
      const id = filePart.replace(/\.(lua|py)$/i, "");
      if (!id || id.includes("/")) {
        return new Response("Not Found", { status: 404 });
      }
      let code = await env.FULLGRAM_KV.get(`script:${id}`);
      if (code == null) {
        const builtin = DEFAULT_PLUGINS.plugins.find((p) => p.id === id);
        if (builtin && builtin.code) code = builtin.code;
      }
      if (code == null) {
        return new Response("Not Found", { status: 404 });
      }
      return new Response(code, {
        status: 200,
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "no-store"
        }
      });
    }

    if (request.method === "POST" && (path === "/telegram-webhook" || path === "/webhook" || path === "/tg")) {
      return handleTelegramWebhook(request, env, origin);
    }

    // Protected Admin Endpoints (requires Authorization: Bearer <ADMIN_TOKEN>)
    if (path.startsWith("/admin/")) {
      if (!isAuthorizedAdmin(request, env)) {
        return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
      }

      if (request.method === "GET" && path === "/admin/badge") {
        const peerId = (url.searchParams.get("peerId") || "").trim();
        const username = (url.searchParams.get("username") || "").trim().replace(/^@+/, "").toLowerCase();
        const badges = await loadBadges(env);
        let roleId = peerId ? badges.users[peerId] : null;
        if (!roleId && username) roleId = badges.usernames[username];
        const role = roleId ? badges.roles[roleId] || null : null;
        return jsonResponse({ ok: true, enabled: Boolean(role), roleId, role, roles: badges.roles });
      }

      if (request.method === "POST" && path === "/admin/badge") {
        try {
          const body = await request.json();
          const badges = await applyBadgeChange(env, body);
          return jsonResponse({
            ok: true,
            usersCount: Object.keys(badges.users).length + Object.keys(badges.usernames).length
          });
        } catch (err) {
          return jsonResponse({ ok: false, error: err.message }, 400);
        }
      }

      if (request.method === "POST" && path === "/admin/plugin") {
        try {
          const body = await request.json();
          const item = await upsertPlugin(env, origin, body);
          return jsonResponse({ ok: true, plugin: item });
        } catch (err) {
          return jsonResponse({ ok: false, error: err.message }, 400);
        }
      }

      if ((request.method === "DELETE" && path === "/admin/plugin") || (request.method === "POST" && path === "/admin/plugin/delete")) {
        let id = (url.searchParams.get("id") || "").trim();
        if (!id && request.method === "POST") {
          const body = await request.json().catch(() => ({}));
          id = String(body.id || "").trim();
        }
        const removed = await deletePluginById(env, id);
        return jsonResponse({ ok: removed, id }, removed ? 200 : 404);
      }

      if (request.method === "POST" && path === "/admin/setup-webhook") {
        if (!env.TG_BOT_TOKEN) {
          return jsonResponse({ ok: false, error: "TG_BOT_TOKEN secret not set" }, 500);
        }
        const secretToken = await expectedWebhookSecret(env);
        const webhookUrl = `${origin}/telegram-webhook`;
        const res = await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/setWebhook`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            url: webhookUrl,
            secret_token: secretToken,
            allowed_updates: ["message", "edited_message"]
          })
        });
        const tgJson = await res.json();
        return jsonResponse({ ok: Boolean(tgJson.ok), webhookUrl, telegram: tgJson }, tgJson.ok ? 200 : 502);
      }

      return jsonResponse({ ok: false, error: "Unknown admin route" }, 404);
    }

    return new Response("Not Found", { status: 404 });
  }
};
