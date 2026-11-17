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
  plugins: []
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
  if (!env.FULLGRAM_KV) return structuredClone(DEFAULT_PLUGINS);
  const raw = await env.FULLGRAM_KV.get("plugins.json");
  if (!raw) return structuredClone(DEFAULT_PLUGINS);
  try {
    const parsed = JSON.parse(raw);
    return {
      version: parsed.version || 1,
      plugins: Array.isArray(parsed.plugins) ? parsed.plugins : []
    };
  } catch {
    return structuredClone(DEFAULT_PLUGINS);
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
      const code = await env.FULLGRAM_KV.get(`script:${id}`);
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
