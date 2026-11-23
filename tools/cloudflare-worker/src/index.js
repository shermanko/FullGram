const DEFAULT_OWNER_ID = "8899688273";
const MAX_SCRIPT_BYTES = 256 * 1024;

// In-memory isolate cache to prevent Cloudflare KV limit exhaustion under heavy load
const MEMORY_CACHE = new Map();
const CACHE_TTL_MS = 20 * 1000; // 20 seconds TTL

function getMemCached(key) {
  const item = MEMORY_CACHE.get(key);
  if (!item) return null;
  if (Date.now() - item.ts > CACHE_TTL_MS) {
    MEMORY_CACHE.delete(key);
    return null;
  }
  return item.data;
}

function setMemCached(key, data) {
  MEMORY_CACHE.set(key, { data, ts: Date.now() });
}

function invalidateMemCache(key) {
  if (key) {
    MEMORY_CACHE.delete(key);
  } else {
    MEMORY_CACHE.clear();
  }
}

import { CASINO_HTML } from "./casino.js";

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
    sponsor: {
      label: "Спонсор FullGram",
      shortLabel: "SPONSOR",
      emoji: "💎",
      color: "#5856D6"
    },
    sponsor_plus: {
      label: "Спонсор+ FullGram",
      shortLabel: "SPONSOR+",
      emoji: "💠",
      color: "#FF2D55"
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
  version: 2,
  plugins: []
};

const DEFAULT_FEATURE_FLAGS = {
  classicDesign: true,
  cloudCosmetics: true,
  avatarFrames: true,
  nicknameStyles: true,
  adminPanel: true,
  screenCapturePrivacy: true,
  chatFaceIdLock: true,
  pluginsEngine: true,
  aiAssistant: true,
  paperDeleteAnimation: true
};

const MAX_INIT_DATA_AGE_SECONDS = 24 * 60 * 60;
const SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;

function jsonResponse(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow",
      "Access-Control-Allow-Origin": "*",
      ...extraHeaders
    }
  });
}

function privateJsonResponse(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow",
      ...extraHeaders
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

function bytesToHex(bytes) {
  return Array.from(new Uint8Array(bytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function base64UrlEncodeBytes(bytes) {
  let binary = "";
  const arr = new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) {
    binary += String.fromCharCode(arr[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlEncodeString(text) {
  return base64UrlEncodeBytes(new TextEncoder().encode(text));
}

function base64UrlDecodeToString(str) {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((str.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

async function hmacSha256Raw(keyBytes, message) {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const msgBytes = typeof message === "string" ? new TextEncoder().encode(message) : message;
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, msgBytes));
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return bytesToHex(digest);
}

function getAdminIds(env) {
  const raw = [env.ADMIN_TG_IDS, env.ADMIN_TG_ID]
    .filter((v) => typeof v === "string" && v.trim())
    .join(",");
  const ids = raw
    .split(/[\s,;]+/)
    .map((s) => s.trim())
    .filter((s) => /^\d{1,20}$/.test(s));
  if (!ids.length) {
    ids.push(DEFAULT_OWNER_ID);
  }
  return new Set(ids);
}

function isAdminUserId(userId, env) {
  const clean = String(userId || "").trim();
  if (!/^\d{1,20}$/.test(clean)) return false;
  return getAdminIds(env).has(clean);
}

function getSessionSecret(env) {
  return (env.SESSION_SECRET || env.ADMIN_TOKEN || env.TG_BOT_TOKEN || "").trim();
}

async function issueSessionToken(userId, role, env, ttlSeconds = SESSION_TTL_SECONDS) {
  const secret = getSessionSecret(env);
  if (!secret) {
    throw new Error("Server signing secret is not configured");
  }
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    uid: String(userId),
    role: role === "admin" ? "admin" : "user",
    iat: now,
    exp: now + ttlSeconds
  };
  const payloadB64 = base64UrlEncodeString(JSON.stringify(payload));
  const sigBytes = await hmacSha256Raw(new TextEncoder().encode(secret), `fg1.${payloadB64}`);
  const sigB64 = base64UrlEncodeBytes(sigBytes);
  return {
    token: `fg1.${payloadB64}.${sigB64}`,
    expiresAt: payload.exp
  };
}

async function verifySessionToken(token, env) {
  if (typeof token !== "string" || !token.startsWith("fg1.")) return null;
  const secret = getSessionSecret(env);
  if (!secret) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [, payloadB64, providedSig] = parts;
  const expectedSigBytes = await hmacSha256Raw(new TextEncoder().encode(secret), `fg1.${payloadB64}`);
  const expectedSig = base64UrlEncodeBytes(expectedSigBytes);
  if (!timingSafeEqual(providedSig, expectedSig)) return null;
  try {
    const payload = JSON.parse(base64UrlDecodeToString(payloadB64));
    const uid = String(payload.uid || "").trim();
    const exp = Number(payload.exp || 0);
    const now = Math.floor(Date.now() / 1000);
    if (!/^\d{1,20}$/.test(uid) || !Number.isFinite(exp) || exp <= now) {
      return null;
    }
    const isAdmin = payload.role === "admin" && isAdminUserId(uid, env);
    return { uid, isAdmin, method: "session_token", exp };
  } catch {
    return null;
  }
}

async function verifyTelegramInitData(initDataRaw, env) {
  if (typeof initDataRaw !== "string" || !initDataRaw.trim()) return null;
  const botToken = String(env.TG_BOT_TOKEN || "").trim();
  if (!botToken) return null;

  const params = new URLSearchParams(initDataRaw.trim());
  const providedHash = (params.get("hash") || "").trim().toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(providedHash)) return null;

  const pairs = [];
  for (const [k, v] of params.entries()) {
    if (k === "hash") continue;
    pairs.push([k, v]);
  }
  pairs.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
  const dataCheckString = pairs.map(([k, v]) => `${k}=${v}`).join("\n");

  const secretKey = await hmacSha256Raw(new TextEncoder().encode("WebAppData"), botToken);
  const expectedHash = bytesToHex(await hmacSha256Raw(secretKey, dataCheckString));
  if (!timingSafeEqual(providedHash, expectedHash)) return null;

  const authDate = Number(params.get("auth_date") || 0);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(authDate) || authDate <= 0 || now - authDate > MAX_INIT_DATA_AGE_SECONDS || authDate - now > 300) {
    return null;
  }

  let userObj = null;
  try {
    userObj = JSON.parse(params.get("user") || "null");
  } catch {
    return null;
  }
  const uid = userObj && userObj.id != null ? String(userObj.id).trim() : "";
  if (!/^\d{1,20}$/.test(uid)) return null;

  return {
    uid,
    username: typeof userObj.username === "string" ? userObj.username : null,
    isAdmin: isAdminUserId(uid, env),
    method: "telegram_init_data"
  };
}

async function authenticateRequest(request, env) {
  const initDataHeader = (request.headers.get("X-Telegram-Init-Data") || "").trim();
  if (initDataHeader) {
    const tgAuth = await verifyTelegramInitData(initDataHeader, env);
    if (tgAuth) return tgAuth;
  }

  const authHeader = (request.headers.get("Authorization") || "").trim();
  if (authHeader.startsWith("tma ")) {
    const tgAuth = await verifyTelegramInitData(authHeader.slice(4).trim(), env);
    if (tgAuth) return tgAuth;
  }

  if (authHeader.startsWith("Bearer ")) {
    const token = authHeader.slice(7).trim();
    if (token.startsWith("fg1.")) {
      const session = await verifySessionToken(token, env);
      if (session) return session;
    }
    if (env.ADMIN_TOKEN && env.ALLOW_LEGACY_ADMIN_TOKEN === "1" && timingSafeEqual(token, env.ADMIN_TOKEN)) {
      const ownerId = Array.from(getAdminIds(env))[0] || DEFAULT_OWNER_ID;
      return { uid: ownerId, isAdmin: true, method: "legacy_admin_token" };
    }
  }

  return null;
}

async function expectedWebhookSecret(env) {
  const base = (env.ADMIN_TOKEN || env.SESSION_SECRET || env.TG_BOT_TOKEN || "").trim();
  if (!base) return null;
  const hex = await sha256Hex(`${base}:tg-webhook`);
  return hex.slice(0, 48);
}

async function loadFeatureFlags(env) {
  const cached = getMemCached("feature_flags");
  if (cached) return cached;
  const base = { ...DEFAULT_FEATURE_FLAGS };
  if (!env.FULLGRAM_KV) return { version: 1, flags: base };
  const raw = await env.FULLGRAM_KV.get("feature_flags.json");
  if (!raw) return { version: 1, flags: base };
  try {
    const parsed = JSON.parse(raw);
    const merged = { ...base };
    if (parsed && typeof parsed.flags === "object" && parsed.flags) {
      for (const [k, v] of Object.entries(parsed.flags)) {
        if (typeof v === "boolean" && /^[a-zA-Z0-9_]{1,48}$/.test(k)) {
          merged[k] = v;
        }
      }
    }
    const res = { version: parsed.version || 1, flags: merged };
    setMemCached("feature_flags", res);
    return res;
  } catch {
    return { version: 1, flags: base };
  }
}

async function saveFeatureFlags(env, flagsObj) {
  invalidateMemCache("feature_flags");
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("feature_flags.json", JSON.stringify(flagsObj, null, 2));
}

async function loadSponsors(env) {
  const cached = getMemCached("sponsors");
  if (cached) return cached;
  if (!env.FULLGRAM_KV) return { version: 1, updatedAt: new Date().toISOString(), sponsors: {} };
  const raw = await env.FULLGRAM_KV.get("sponsors_v1");
  if (!raw) return { version: 1, updatedAt: new Date().toISOString(), sponsors: {} };
  try {
    const parsed = JSON.parse(raw);
    const rawSponsors = parsed.sponsors && typeof parsed.sponsors === "object" ? parsed.sponsors : {};
    const sponsors = {};
    for (const [k, v] of Object.entries(rawSponsors)) {
      const nid = normalizePeerId(k);
      if (nid) sponsors[nid] = v;
    }
    const res = {
      version: Number(parsed.version || 1),
      updatedAt: String(parsed.updatedAt || new Date().toISOString()),
      sponsors
    };
    setMemCached("sponsors", res);
    return res;
  } catch {
    return { version: 1, updatedAt: new Date().toISOString(), sponsors: {} };
  }
}

async function saveSponsors(env, data) {
  invalidateMemCache("sponsors");
  if (!env.FULLGRAM_KV) throw new Error("FULLGRAM_KV binding not configured");
  const payload = {
    version: Number(data.version || 1) + 1,
    updatedAt: new Date().toISOString(),
    sponsors: data.sponsors || {}
  };
  await env.FULLGRAM_KV.put("sponsors_v1", JSON.stringify(payload));
  return payload;
}

function normalizeSponsorTier(raw) {
  const v = String(raw || "").trim().toLowerCase();
  if (v === "plus" || v === "sponsor_plus" || v === "sponsor+" || v === "+") {
    return "plus";
  }
  return "standard";
}

async function getSponsorTier(env, userId) {
  const nid = normalizePeerId(userId);
  if (!nid) return null;
  const data = await loadSponsors(env);
  const entry = data.sponsors && data.sponsors[nid];
  if (!entry) return null;
  return normalizeSponsorTier(entry.tier);
}

async function isSponsorUser(env, userId) {
  return Boolean(await getSponsorTier(env, userId));
}

async function applySponsorChange(env, body, actingUserId) {
  const rawMode = String(body.tier || body.mode || "").trim().toLowerCase();
  const enabled = body.enabled !== false && body.action !== "remove" && body.action !== "revoke" && rawMode !== "none" && rawMode !== "off";
  const tier = normalizeSponsorTier(body.tier || (body.plus ? "plus" : "standard"));
  const rawPeer = body.peerId ? normalizePeerId(body.peerId) : "";
  const cleanUser = body.username ? String(body.username).trim().replace(/^@/, "").toLowerCase() : "";
  let targetPeerId = rawPeer;
  if (!targetPeerId && cleanUser) {
    const badges = await loadBadges(env);
    if (badges.usernames && badges.usernames[cleanUser]) {
      targetPeerId = normalizePeerId(badges.usernames[cleanUser]);
    }
  }
  if (!targetPeerId) {
    throw new Error("Valid peerId or known @username is required");
  }
  const data = await loadSponsors(env);
  if (!data.sponsors) data.sponsors = {};
  if (enabled) {
    data.sponsors[targetPeerId] = {
      addedAt: Date.now(),
      addedBy: String(actingUserId || ""),
      tier,
      label: String(body.label || (tier === "plus" ? "Спонсор+ FullGram" : "Спонсор FullGram")).slice(0, 64)
    };
  } else {
    delete data.sponsors[targetPeerId];
  }
  const saved = await saveSponsors(env, data);
  const badges = await loadBadges(env);
  const existingRole = badges.users && badges.users[targetPeerId];
  const existingRoleId = typeof existingRole === "string" ? existingRole : null;
  const targetRole = tier === "plus" ? "sponsor_plus" : "sponsor";
  if (enabled && (!existingRoleId || existingRoleId === "premium" || existingRoleId === "sponsor" || existingRoleId === "sponsor_plus")) {
    await applyBadgeChange(env, { peerId: targetPeerId, enabled: true, roleId: targetRole });
  } else if (!enabled && (existingRoleId === "sponsor" || existingRoleId === "sponsor_plus")) {
    await applyBadgeChange(env, { peerId: targetPeerId, enabled: false });
  }
  return { peerId: targetPeerId, enabled, tier: enabled ? tier : null, sponsors: saved.sponsors };
}

async function applyNftChange(env, body, grantedBy) {
  const peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
  if (!peerId || !/^-?\d{1,20}$/.test(peerId)) {
    throw new Error("Invalid peerId");
  }
  const nfts = await loadNfts(env);
  if (!nfts.users) nfts.users = {};
  const list = Array.isArray(nfts.users[peerId]) ? nfts.users[peerId] : [];
  const entryId = body.id != null && String(body.id).trim()
    ? String(body.id).trim().slice(0, 64)
    : (body.nftId != null && String(body.nftId).trim()
      ? String(body.nftId).trim().slice(0, 64)
      : `fg_nft_${Date.now()}_${Math.floor(Math.random() * 10000)}`);

  const action = String(body.action || "").toLowerCase();
  if (body.enabled === false || action === "revoke" || action === "remove" || action === "delete") {
    nfts.users[peerId] = list.filter((item) => item.id !== entryId);
    if (!nfts.users[peerId].length) delete nfts.users[peerId];
  } else {
    const giftId = body.giftId != null ? String(body.giftId).trim() : "";
    if (!/^-?\d{1,20}$/.test(giftId)) {
      throw new Error("Invalid giftId");
    }
    const rawNum = Number(body.number);
    const number = Number.isFinite(rawNum) && rawNum >= 1 ? Math.min(9999999, Math.floor(rawNum)) : 1;
    const rawBackdropId = body.backdropId != null ? Number(body.backdropId) : null;
    const rawTitle = typeof body.title === "string" && body.title.trim() ? body.title.trim().slice(0, 64) : "NFT";
    const entry = {
      id: entryId,
      giftId,
      title: rawTitle,
      modelName: typeof body.modelName === "string" ? body.modelName.trim().slice(0, 64) : "",
      backdropName: typeof body.backdropName === "string" ? body.backdropName.trim().slice(0, 64) : "",
      backdropId: Number.isFinite(rawBackdropId) ? Math.floor(rawBackdropId) : null,
      patternName: typeof body.patternName === "string" ? body.patternName.trim().slice(0, 64) : "",
      number,
      note: typeof body.note === "string" ? body.note.trim().slice(0, 120) : "",
      pinned: body.pinned !== false,
      hidden: Boolean(body.hidden),
      grantedBy: String(grantedBy || ""),
      grantedAt: Math.floor(Date.now() / 1000)
    };
    const idx = list.findIndex((item) => item.id === entryId);
    if (idx >= 0) list[idx] = entry;
    else list.unshift(entry);
    nfts.users[peerId] = list.slice(0, 50);
  }
  await saveNfts(env, nfts);
  return { id: entryId, peerId, items: nfts.users[peerId] || [] };
}

async function applyNftAction(env, body, actorId, canManageAny) {
  const action = String(body.action || "").trim().toLowerCase();
  const fromPeerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : String(actorId));
  const entryId = String(body.id || "").trim().slice(0, 64);
  const slug = String(body.slug || "").trim();
  if (!fromPeerId || !/^-?\d{1,20}$/.test(fromPeerId)) {
    throw new Error("Invalid peerId");
  }
  if (!canManageAny && fromPeerId !== normalizePeerId(String(actorId))) {
    throw new Error("Forbidden: can only modify your own NFT");
  }
  const nfts = await loadNfts(env);
  if (!nfts.users) nfts.users = {};
  const list = Array.isArray(nfts.users[fromPeerId]) ? [...nfts.users[fromPeerId]] : [];
  const idx = list.findIndex((item) => {
    if (entryId && item.id === entryId) return true;
    if (slug && `FullGram-${item.giftId}-${item.number}`.toLowerCase() === slug.toLowerCase()) return true;
    return false;
  });
  if (idx < 0) {
    throw new Error("NFT not found");
  }
  const item = { ...list[idx] };
  if (action === "hide") {
    item.hidden = true;
    list[idx] = item;
    nfts.users[fromPeerId] = list;
  } else if (action === "show") {
    item.hidden = false;
    list[idx] = item;
    nfts.users[fromPeerId] = list;
  } else if (action === "pin") {
    item.pinned = true;
    list[idx] = item;
    nfts.users[fromPeerId] = list;
  } else if (action === "unpin") {
    item.pinned = false;
    list[idx] = item;
    nfts.users[fromPeerId] = list;
  } else if (action === "delete" || action === "remove" || action === "revoke") {
    list.splice(idx, 1);
    if (list.length) nfts.users[fromPeerId] = list;
    else delete nfts.users[fromPeerId];
  } else if (action === "upgrade") {
    if (typeof body.modelName === "string" && body.modelName.trim()) item.modelName = body.modelName.trim().slice(0, 64);
    if (typeof body.backdropName === "string" && body.backdropName.trim()) item.backdropName = body.backdropName.trim().slice(0, 64);
    if (body.backdropId != null && Number.isFinite(Number(body.backdropId))) item.backdropId = Math.floor(Number(body.backdropId));
    if (typeof body.patternName === "string" && body.patternName.trim()) item.patternName = body.patternName.trim().slice(0, 64);
    if (body.number != null && Number.isFinite(Number(body.number)) && Number(body.number) >= 1) {
      item.number = Math.min(9999999, Math.floor(Number(body.number)));
    }
    list[idx] = item;
    nfts.users[fromPeerId] = list;
  } else if (action === "transfer") {
    const toPeerId = normalizePeerId(body.toPeerId != null ? String(body.toPeerId).trim() : "");
    if (!toPeerId || !/^-?\d{1,20}$/.test(toPeerId) || toPeerId === fromPeerId) {
      throw new Error("Invalid recipient peerId");
    }
    list.splice(idx, 1);
    if (list.length) nfts.users[fromPeerId] = list;
    else delete nfts.users[fromPeerId];
    item.pinned = true;
    item.hidden = false;
    const targetList = Array.isArray(nfts.users[toPeerId]) ? [...nfts.users[toPeerId]] : [];
    targetList.unshift(item);
    nfts.users[toPeerId] = targetList.slice(0, 50);
  } else {
    throw new Error("Unsupported NFT action");
  }
  await saveNfts(env, nfts);
  return { id: item.id, action, peerId: fromPeerId, items: nfts.users[fromPeerId] || [] };
}

async function loadEconomy(env) {
  const cached = getMemCached("economy");
  if (cached) return cached;
  const empty = { version: 1, users: {} };
  if (!env.FULLGRAM_KV) return empty;
  const raw = await env.FULLGRAM_KV.get("economy_v1");
  if (!raw) return empty;
  try {
    const parsed = JSON.parse(raw);
    const res = {
      version: parsed.version || 1,
      users: parsed.users && typeof parsed.users === "object" ? parsed.users : {}
    };
    setMemCached("economy", res);
    return res;
  } catch {
    return empty;
  }
}

async function saveEconomy(env, eco) {
  invalidateMemCache("economy");
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("economy_v1", JSON.stringify(eco, null, 2));
}

async function applyEconomyChange(env, body, grantedBy) {
  const peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
  if (!peerId || !/^-?\d{1,20}$/.test(peerId)) {
    throw new Error("Invalid peerId");
  }
  const eco = await loadEconomy(env);
  if (!eco.users) eco.users = {};
  const userEntry = eco.users[peerId] && typeof eco.users[peerId] === "object"
    ? {
        gramBalance: Number(eco.users[peerId].gramBalance || 0),
        starsBalance: Number(eco.users[peerId].starsBalance || 0),
        usernames: Array.isArray(eco.users[peerId].usernames) ? [...eco.users[peerId].usernames] : [],
        numbers: Array.isArray(eco.users[peerId].numbers) ? [...eco.users[peerId].numbers] : []
      }
    : { gramBalance: 0, starsBalance: 0, usernames: [], numbers: [] };

  const action = String(body.action || "").trim().toLowerCase();
  const nowSec = Math.floor(Date.now() / 1000);
  const tonRate = 5.4;

  if (action === "set_gram") {
    const val = Number(body.amount);
    if (!Number.isFinite(val) || val < 0) throw new Error("Invalid gram amount");
    userEntry.gramBalance = Math.round(val * 100) / 100;
  } else if (action === "set_stars") {
    const val = Number(body.amount);
    if (!Number.isFinite(val) || val < 0) throw new Error("Invalid stars amount");
    userEntry.starsBalance = Math.floor(val);
  } else if (action === "grant_username") {
    const clean = String(body.username || "").trim().replace(/^@+/, "").toLowerCase();
    if (!/^[a-z0-9_]{4,32}$/.test(clean)) throw new Error("Invalid username (4-32 latin/digits/_)");
    const priceTon = Math.max(0, Number(body.priceTon || 0) || 0);
    const isPrimary = body.isPrimary !== false;
    if (isPrimary) {
      userEntry.usernames = userEntry.usernames.map((u) => ({ ...u, isPrimary: false }));
    }
    userEntry.usernames = userEntry.usernames.filter((u) => String(u.username || "").toLowerCase() !== clean);
    userEntry.usernames.unshift({
      id: String(body.id || `fg_u_${Date.now()}_${Math.floor(Math.random() * 1000)}`),
      username: clean,
      priceTon,
      priceUsd: Math.round(priceTon * tonRate * 100) / 100,
      purchasedAt: nowSec,
      isActive: true,
      isPrimary,
      grantedBy: String(grantedBy || "")
    });
    userEntry.usernames = userEntry.usernames.slice(0, 30);
  } else if (action === "revoke_username") {
    const clean = String(body.username || "").trim().replace(/^@+/, "").toLowerCase();
    const targetId = String(body.id || "").trim();
    userEntry.usernames = userEntry.usernames.filter((u) => u.id !== targetId && String(u.username || "").toLowerCase() !== clean);
  } else if (action === "grant_number") {
    const rawNum = String(body.number || "").trim();
    if (!rawNum) throw new Error("Invalid number");
    const digits = rawNum.replace(/\D/g, "");
    let core = digits.startsWith("888") ? digits.slice(3) : digits;
    if (core.length < 4) core = core.padEnd(8, "0");
    if (core.length > 8) core = core.slice(0, 8);
    const formatted = core.length === 8 ? `+888 ${core.slice(0, 4)} ${core.slice(4)}` : rawNum.slice(0, 32);
    const priceTon = Math.max(0, Number(body.priceTon || 0) || 0);
    userEntry.numbers = userEntry.numbers.map((n) => ({ ...n, isActive: false }));
    userEntry.numbers.unshift({
      id: String(body.id || `fg_n_${Date.now()}_${Math.floor(Math.random() * 1000)}`),
      number: formatted,
      priceTon,
      priceUsd: Math.round(priceTon * tonRate * 100) / 100,
      purchasedAt: nowSec,
      isActive: true,
      grantedBy: String(grantedBy || "")
    });
    userEntry.numbers = userEntry.numbers.slice(0, 30);
  } else if (action === "revoke_number") {
    const targetId = String(body.id || "").trim();
    userEntry.numbers = userEntry.numbers.filter((n) => n.id !== targetId);
  } else {
    throw new Error("Unknown economy action");
  }

  eco.users[peerId] = userEntry;
  await saveEconomy(env, eco);
  return { peerId, economy: userEntry };
}

async function loadBetaInvites(env) {
  if (!env.FULLGRAM_KV) return { version: 1, invites: {} };
  const raw = await env.FULLGRAM_KV.get("beta_invites_v1");
  if (!raw) return { version: 1, invites: {} };
  try {
    const parsed = JSON.parse(raw);
    return { version: parsed.version || 1, invites: parsed.invites && typeof parsed.invites === "object" ? parsed.invites : {} };
  } catch {
    return { version: 1, invites: {} };
  }
}

async function saveBetaInvites(env, data) {
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("beta_invites_v1", JSON.stringify(data));
}

async function loadBetaUsers(env) {
  if (!env.FULLGRAM_KV) return { version: 1, users: {} };
  const raw = await env.FULLGRAM_KV.get("beta_users_v1");
  if (!raw) return { version: 1, users: {} };
  try {
    const parsed = JSON.parse(raw);
    return { version: parsed.version || 1, users: parsed.users && typeof parsed.users === "object" ? parsed.users : {} };
  } catch {
    return { version: 1, users: {} };
  }
}

async function saveBetaUsers(env, data) {
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("beta_users_v1", JSON.stringify(data));
}

async function issueBetaReceipt(peerId, deviceHash, code, env) {
  const secret = getSessionSecret(env);
  if (!secret) throw new Error("Server signing secret is not configured");
  const payload = { uid: String(peerId), dh: String(deviceHash), code: String(code), iat: Math.floor(Date.now() / 1000) };
  const payloadB64 = base64UrlEncodeString(JSON.stringify(payload));
  const sigBytes = await hmacSha256Raw(new TextEncoder().encode(secret), `fgba1.${payloadB64}`);
  return `fgba1.${payloadB64}.${base64UrlEncodeBytes(sigBytes)}`;
}

async function verifyBetaReceipt(receipt, env) {
  if (typeof receipt !== "string" || !receipt.startsWith("fgba1.")) return null;
  const secret = getSessionSecret(env);
  if (!secret) return null;
  const parts = receipt.split(".");
  if (parts.length !== 3) return null;
  const [, payloadB64, sig] = parts;
  const expected = base64UrlEncodeBytes(await hmacSha256Raw(new TextEncoder().encode(secret), `fgba1.${payloadB64}`));
  if (!timingSafeEqual(sig, expected)) return null;
  try {
    return JSON.parse(base64UrlDecodeToString(payloadB64));
  } catch {
    return null;
  }
}

function renderBetaLandingHtml(code, origin, inviteStatus = null) {
  const safeCode = escapeHtml(code);
  const deepLink = `fullgram://beta?code=${encodeURIComponent(code)}`;
  const tgDeepLink = `tg://fullgram/beta?code=${encodeURIComponent(code)}`;
  let statusBadge = "Готово к активации";
  let statusColor = "#34d399";
  if (inviteStatus) {
    if (inviteStatus.revoked) {
      statusBadge = "Ссылка отозвана";
      statusColor = "#f87171";
    } else if (inviteStatus.expired) {
      statusBadge = "Срок действия истёк";
      statusColor = "#f87171";
    } else if (inviteStatus.exhausted) {
      statusBadge = "Лимит активаций исчерпан";
      statusColor = "#fbbf24";
    } else if (!inviteStatus.exists) {
      statusBadge = "Код не найден";
      statusColor = "#f87171";
    } else {
      statusBadge = `Активна · осталось ${inviteStatus.remaining} из ${inviteStatus.maxUses}`;
    }
  }
  return `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>FullGram · Закрытый бета-тест</title>
  <style>
    body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#0a0b10;color:#fff;font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:24px;}
    .card{max-width:410px;width:100%;background:#151822;border:1px solid rgba(255,255,255,.08);border-radius:22px;padding:28px;text-align:center;box-shadow:0 20px 50px rgba(0,0,0,.45);}
    .pill{display:inline-block;padding:5px 12px;border-radius:999px;font-size:12px;font-weight:700;background:rgba(255,255,255,.06);margin-bottom:14px;}
    h1{font-size:22px;margin:0 0 10px;}
    p{font-size:14px;line-height:1.5;color:#a4abc0;margin:0 0 20px;}
    .btn{display:block;padding:14px 18px;border-radius:14px;background:linear-gradient(135deg,#3390ec,#6c5ce7);color:#fff;text-decoration:none;font-weight:700;font-size:15px;margin-bottom:10px;}
    .btn-sec{display:block;padding:12px 16px;border-radius:12px;background:rgba(255,255,255,.07);color:#e2e8f0;text-decoration:none;font-weight:600;font-size:13.5px;border:none;width:100%;cursor:pointer;margin-bottom:8px;}
    .code{margin-top:14px;font-size:12px;color:#737b94;word-break:break-all;}
  </style>
</head>
<body>
  <div class="card">
    <div class="pill" style="color:${statusColor};">${escapeHtml(statusBadge)}</div>
    <h1>🔐 Закрытый бета-тест FullGram</h1>
    <p>Нажмите кнопку ниже, чтобы открыть FullGram и активировать бета-функции. Если откроется меню Настройки → FullGram, можно также вставить код вручную.</p>
    <a class="btn" href="${deepLink}">Открыть FullGram и активировать</a>
    <a class="btn-sec" href="${tgDeepLink}">Альтернативная ссылка (tg://)</a>
    <button class="btn-sec" type="button" onclick="navigator.clipboard?.writeText(${JSON.stringify(code)});this.textContent='✅ Код скопирован';">📋 Скопировать код приглашения</button>
    <div class="code">Код: ${safeCode}</div>
  </div>
  <script>setTimeout(function(){ window.location.href = ${JSON.stringify(deepLink)}; }, 150);</script>
</body>
</html>`;
}

async function loadNfts(env) {
  const cached = getMemCached("nfts");
  if (cached) return cached;
  const empty = { version: 1, users: {} };
  if (!env.FULLGRAM_KV) return empty;
  const raw = await env.FULLGRAM_KV.get("nfts.json");
  if (!raw) return empty;
  try {
    const parsed = JSON.parse(raw);
    const res = {
      version: parsed.version || 1,
      users: parsed.users && typeof parsed.users === "object" ? parsed.users : {}
    };
    setMemCached("nfts", res);
    return res;
  } catch {
    return empty;
  }
}

async function saveNfts(env, nfts) {
  invalidateMemCache("nfts");
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("nfts.json", JSON.stringify(nfts, null, 2));
}

async function loadBadges(env) {
  const cached = getMemCached("badges");
  if (cached) return cached;
  if (!env.FULLGRAM_KV) return structuredClone(DEFAULT_BADGES);
  const raw = await env.FULLGRAM_KV.get("badges.json");
  if (!raw) return structuredClone(DEFAULT_BADGES);
  try {
    const parsed = JSON.parse(raw);
    const rawUsers = parsed.users && typeof parsed.users === "object" ? parsed.users : DEFAULT_BADGES.users;
    const users = {};
    for (const [k, v] of Object.entries(rawUsers)) {
      users[k] = v;
      const norm = normalizePeerId(k);
      if (norm && norm !== k) {
        users[norm] = v;
      }
    }
    const res = {
      version: parsed.version || 1,
      roles: { ...DEFAULT_BADGES.roles, ...(parsed.roles || {}) },
      users,
      usernames: parsed.usernames && typeof parsed.usernames === "object" ? { ...parsed.usernames } : { ...DEFAULT_BADGES.usernames }
    };
    setMemCached("badges", res);
    return res;
  } catch {
    return structuredClone(DEFAULT_BADGES);
  }
}

async function saveBadges(env, badges) {
  invalidateMemCache("badges");
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("badges.json", JSON.stringify(badges, null, 2));
}

async function loadCosmetics(env) {
  const cached = getMemCached("cosmetics");
  if (cached) return cached;
  const empty = { version: 1, users: {} };
  if (!env.FULLGRAM_KV) return empty;
  const raw = await env.FULLGRAM_KV.get("cosmetics.json");
  if (!raw) return empty;
  try {
    const parsed = JSON.parse(raw);
    const rawUsers = parsed.users && typeof parsed.users === "object" ? parsed.users : {};
    const users = {};
    for (const [k, v] of Object.entries(rawUsers)) {
      const nid = normalizePeerId(k);
      if (nid) users[nid] = v;
    }
    const res = {
      version: parsed.version || 1,
      users
    };
    setMemCached("cosmetics", res);
    return res;
  } catch {
    return empty;
  }
}

async function saveCosmetics(env, cosmetics) {
  invalidateMemCache("cosmetics");
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("cosmetics.json", JSON.stringify(cosmetics, null, 2));
}

async function applyCosmeticChange(env, body) {
  const peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
  if (!/^-?\d{1,20}$/.test(peerId)) {
    throw new Error("Invalid peerId");
  }
  const cosmetics = await loadCosmetics(env);
  const existing = cosmetics.users[peerId] || {};

  let frameId = existing.frameId || null;
  if ("frameId" in body) {
    if (body.frameId == null || String(body.frameId).trim() === "") {
      frameId = null;
    } else {
      const candidate = String(body.frameId).trim();
      if (!/^[a-z0-9_-]{1,96}$/i.test(candidate)) {
        throw new Error("Invalid frameId");
      }
      frameId = candidate;
    }
  }

  let customFrameUrl = existing.customFrameUrl || null;
  if ("customFrameUrl" in body) {
    if (body.customFrameUrl == null || String(body.customFrameUrl).trim() === "") {
      customFrameUrl = null;
    } else {
      const candidate = String(body.customFrameUrl).trim();
      if (candidate.length > 400 || !/^https:\/\/[^\s]+$/i.test(candidate)) {
        throw new Error("Invalid customFrameUrl");
      }
      customFrameUrl = candidate;
    }
  }

  let profileEffectId = existing.profileEffectId || null;
  if ("profileEffectId" in body) {
    if (body.profileEffectId == null || String(body.profileEffectId).trim() === "") {
      profileEffectId = null;
    } else {
      const candidate = String(body.profileEffectId).trim();
      if (!/^[a-z0-9_-]{1,96}$/i.test(candidate)) {
        throw new Error("Invalid profileEffectId");
      }
      profileEffectId = candidate;
    }
  }

  let nickColor = existing.nickColor || null;
  if ("nickColor" in body) {
    if (body.nickColor == null || String(body.nickColor).trim() === "") {
      nickColor = null;
    } else {
      const candidate = String(body.nickColor).trim().toUpperCase();
      if (!/^#[0-9A-F]{6}$/.test(candidate)) {
        throw new Error("Invalid nickColor");
      }
      nickColor = candidate;
    }
  }

  let nickGlow = typeof existing.nickGlow === "boolean" ? existing.nickGlow : false;
  if ("nickGlow" in body) {
    nickGlow = Boolean(body.nickGlow);
  }

  if (!frameId && !customFrameUrl && !profileEffectId && !nickColor) {
    delete cosmetics.users[peerId];
  } else {
    cosmetics.users[peerId] = {
      frameId: frameId || null,
      customFrameUrl: customFrameUrl || null,
      profileEffectId: profileEffectId || null,
      nickColor: nickColor || null,
      nickGlow: Boolean(nickColor ? nickGlow : false)
    };
  }
  await saveCosmetics(env, cosmetics);
  return cosmetics.users[peerId] || null;
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
    for (const p of kvList) byId.set(p.id, p);
    for (const p of base) byId.set(p.id, p);
    return {
      version: parsed.version || 1,
      plugins: Array.from(byId.values())
    };
  } catch {
    return { version: 1, plugins: base };
  }
}

async function savePlugins(env, catalog) {
  if (!env.FULLGRAM_KV) return;
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

function normalizePeerId(raw) {
  const s = String(raw ?? "").trim();
  if (!/^-?\d+$/.test(s)) return s;
  try {
    let n = BigInt(s);
    if (n < 0n) n = -n;
    const threshold = 1n << 35n;
    if (n >= threshold) {
      const low = n & 0xffffffffn;
      const high = n >> 35n;
      return String((high << 32n) | low);
    }
    return String(n);
  } catch {
    return s;
  }
}

async function applyBadgeChange(env, body) {
  const badges = await loadBadges(env);
  const rawPeerId = body.peerId != null ? String(body.peerId).trim() : "";
  const peerId = normalizePeerId(rawPeerId);
  const cleanUser = typeof body.username === "string"
    ? body.username.trim().replace(/^@+/, "").toLowerCase()
    : "";

  if (!peerId && !cleanUser) {
    throw new Error("peerId or username is required");
  }

  const enabled = body.enabled !== false;
  const customRoleKey = peerId ? `user_${peerId}` : `name_${cleanUser}`;
  const rawCustomRoleKey = rawPeerId && rawPeerId !== peerId ? `user_${rawPeerId}` : null;

  if (!enabled) {
    if (peerId) delete badges.users[peerId];
    if (rawPeerId) delete badges.users[rawPeerId];
    if (cleanUser) delete badges.usernames[cleanUser];
    delete badges.roles[customRoleKey];
    if (rawCustomRoleKey) delete badges.roles[rawCustomRoleKey];
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
  if (rawCustomRoleKey) {
    delete badges.roles[rawCustomRoleKey];
  }

  if (peerId) badges.users[peerId] = assignedRoleId;
  if (rawPeerId && rawPeerId !== peerId) badges.users[rawPeerId] = assignedRoleId;
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

  if (!env.FULLGRAM_KV) {
    throw new Error("FULLGRAM_KV binding is not configured");
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
  if (!cleanId || !env.FULLGRAM_KV) return false;
  if (DEFAULT_PLUGINS.plugins.some((p) => p.id === cleanId)) {
    return false;
  }
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

async function sendTelegramMessage(env, chatId, text, extra = {}) {
  if (!env.TG_BOT_TOKEN) return;
  await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      disable_web_page_preview: true,
      ...extra
    })
  });
}

async function answerTelegramCallback(env, callbackQueryId, text = "") {
  if (!env.TG_BOT_TOKEN || !callbackQueryId) return;
  await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/answerCallbackQuery`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      callback_query_id: callbackQueryId,
      text
    })
  });
}

function escapeHtml(str) {
  return String(str || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function adminBotKeyboard() {
  return {
    inline_keyboard: [
      [
        { text: "🔑 Новый админ-токен (30 дн.)", callback_data: "gen_admin_30d" },
        { text: "⚡ Токен (7 дн.)", callback_data: "gen_admin_7d" }
      ],
      [
        { text: "🎟 Бета (1 юзер)", callback_data: "gen_beta_1" },
        { text: "👥 Бета (5)", callback_data: "gen_beta_5" },
        { text: "🚀 Бета (25)", callback_data: "gen_beta_25" }
      ],
      [
        { text: "📋 Бета-список", callback_data: "beta_list" },
        { text: "📦 Плагины в маркете", callback_data: "list_plugins" }
      ]
    ]
  };
}

async function sendAutoGeneratedAdminToken(env, chatId, senderId, days = 30) {
  const safeDays = Math.max(1, Math.min(90, Number(days) || 30));
  const ttlSeconds = safeDays * 24 * 60 * 60;
  const issued = await issueSessionToken(senderId, "admin", env, ttlSeconds);
  const expDate = new Date(issued.expiresAt * 1000).toISOString().slice(0, 10);
  await sendTelegramMessage(
    env,
    chatId,
    `🔑 <b>Админ-токен FullGram сгенерирован автоматически</b>\n` +
    `ID владельца: <code>${escapeHtml(senderId)}</code> · действует <b>${safeDays} дн.</b> (до ${expDate})\n\n` +
    `Нажмите на токен, чтобы скопировать:\n` +
    `<code>${escapeHtml(issued.token)}</code>\n\n` +
    `Вставьте его в FullGram → Админ-панель.`,
    {
      parse_mode: "HTML",
      reply_markup: {
        inline_keyboard: [
          [{ text: "🔄 Сгенерировать новый токен (30 дн.)", callback_data: "gen_admin_30d" }]
        ]
      }
    }
  );
}

async function handleTelegramWebhook(request, env, origin) {
  const expected = await expectedWebhookSecret(env);
  if (!expected) {
    return new Response("Webhook secret not configured", { status: 500 });
  }
  const provided = request.headers.get("X-Telegram-Bot-Api-Secret-Token") || "";
  if (!timingSafeEqual(provided, expected)) {
    return new Response("Forbidden", { status: 403 });
  }

  let update;
  try {
    update = await request.json();
  } catch {
    return jsonResponse({ ok: true });
  }

  // Strict owner-only lockdown: reject EVERY update type (messages, callbacks, inline, join requests, etc.) from non-owners
  const actor =
    update.message?.from ||
    update.edited_message?.from ||
    update.callback_query?.from ||
    update.inline_query?.from ||
    update.chosen_inline_result?.from ||
    update.channel_post?.from ||
    update.edited_channel_post?.from ||
    update.my_chat_member?.from ||
    update.chat_member?.from ||
    update.chat_join_request?.from ||
    null;
  const actorId = actor && actor.id != null ? String(actor.id).trim() : "";
  const ownerId = String(env.OWNER_USER_ID || DEFAULT_OWNER_ID).trim();
  if (!actorId || actorId !== ownerId || !isAdminUserId(actorId, env)) {
    if (update.callback_query?.id) {
      await answerTelegramCallback(env, update.callback_query.id, "⛔ Доступ запрещён: бот только для владельца.");
    } else if (update.inline_query?.id) {
      // Ignore inline queries silently from non-owners
    } else {
      const msgObj = update.message || update.edited_message;
      if (msgObj?.chat?.id && msgObj?.chat?.type === "private") {
        await sendTelegramMessage(env, msgObj.chat.id, "⛔ Доступ запрещён. Этот бот доступен исключительно владельцу FullGram.");
      }
    }
    return jsonResponse({ ok: true });
  }

  // Handle inline button taps (owner-only)
  if (update.callback_query && update.callback_query.from) {
    const cq = update.callback_query;
    const senderId = String(cq.from.id);
    const chatId = cq.message?.chat?.id ?? cq.from.id;
    const isPrivateChat = cq.message?.chat?.type === "private";
    if (!isAdminUserId(senderId, env)) {
      await answerTelegramCallback(env, cq.id, "⛔ Доступ только для владельца.");
      return jsonResponse({ ok: true });
    }
    const data = String(cq.data || "");
    if (data === "gen_admin_30d" || data === "gen_admin_7d") {
      if (!isPrivateChat) {
        await answerTelegramCallback(env, cq.id, "🔒 Только в личных сообщениях с ботом.");
        return jsonResponse({ ok: true });
      }
      const days = data === "gen_admin_7d" ? 7 : 30;
      try {
        await sendAutoGeneratedAdminToken(env, cq.from.id, senderId, days);
        await answerTelegramCallback(env, cq.id, `✅ Токен на ${days} дн. создан`);
      } catch (err) {
        await answerTelegramCallback(env, cq.id, "❌ Ошибка генерации токена");
        await sendTelegramMessage(env, cq.from.id, `❌ Не удалось сгенерировать токен: ${err.message}`);
      }
      return jsonResponse({ ok: true });
    }
    if (data === "gen_beta_1" || data === "gen_beta_5" || data === "gen_beta_25") {
      if (!isPrivateChat) {
        await answerTelegramCallback(env, cq.id, "🔒 Только в ЛС.");
        return jsonResponse({ ok: true });
      }
      const maxUses = data === "gen_beta_25" ? 25 : (data === "gen_beta_5" ? 5 : 1);
      const rand = new Uint8Array(12);
      crypto.getRandomValues(rand);
      const code = `fgb1_${bytesToHex(rand)}`;
      const inv = await loadBetaInvites(env);
      inv.invites[code] = { maxUses, uses: 0, note: "button", createdAt: Math.floor(Date.now() / 1000), revoked: false };
      await saveBetaInvites(env, inv);
      await answerTelegramCallback(env, cq.id, `✅ Бета-ссылка (${maxUses}) создана`);
      await sendTelegramMessage(
        env,
        cq.from.id,
        `🎟 <b>Ссылка для закрытого бета-теста FullGram</b>\n` +
        `Лимит активаций: <b>${maxUses}</b>\n\n` +
        `🔗 Веб-ссылка:\n<code>${origin}/beta/${code}</code>\n\n` +
        `📲 FullGram:\n<code>fullgram://beta?code=${code}</code>\n` +
        `📲 Telegram:\n<code>tg://fullgram/beta?code=${code}</code>`,
        {
          parse_mode: "HTML",
          reply_markup: {
            inline_keyboard: [
              [
                { text: "🔄 Ещё (1)", callback_data: "gen_beta_1" },
                { text: "👥 Ещё (5)", callback_data: "gen_beta_5" }
              ],
              [
                { text: "🗑 Отозвать эту ссылку", callback_data: `beta_revoke:${code}` }
              ]
            ]
          }
        }
      );
      return jsonResponse({ ok: true });
    }
    if (data === "beta_list") {
      const [inv, usr] = await Promise.all([loadBetaInvites(env), loadBetaUsers(env)]);
      const invLines = Object.entries(inv.invites || {}).slice(-15).map(([c, info]) =>
        `• <code>${escapeHtml(c)}</code> — ${info.uses || 0}/${info.maxUses || 1}${info.revoked ? " [ОТОЗВАН]" : ""}`
      );
      const usrLines = Object.entries(usr.users || {}).slice(-20).map(([uid, u]) =>
        `• <code>${escapeHtml(uid)}</code>${u.revoked ? " [ОТОЗВАН]" : " [АКТИВЕН]"}`
      );
      await answerTelegramCallback(env, cq.id, `Инвайтов: ${Object.keys(inv.invites || {}).length}`);
      await sendTelegramMessage(
        env,
        chatId,
        `🎟 <b>Инвайты беты:</b>\n${invLines.join("\n") || "Нет"}\n\n👤 <b>Пользователи (${Object.keys(usr.users || {}).length}):</b>\n${usrLines.join("\n") || "Нет"}`,
        { parse_mode: "HTML" }
      );
      return jsonResponse({ ok: true });
    }
    if (data.startsWith("beta_revoke:")) {
      const target = data.slice("beta_revoke:".length).trim();
      const [inv, usr] = await Promise.all([loadBetaInvites(env), loadBetaUsers(env)]);
      let ok = false;
      if (inv.invites[target]) {
        inv.invites[target].revoked = true;
        await saveBetaInvites(env, inv);
        ok = true;
      }
      if (usr.users[target]) {
        usr.users[target].revoked = true;
        await saveBetaUsers(env, usr);
        ok = true;
      }
      await answerTelegramCallback(env, cq.id, ok ? "🗑 Отозвано" : "⚠️ Не найдено");
      await sendTelegramMessage(env, chatId, ok ? `🗑 Бета-доступ/инвайт <code>${escapeHtml(target)}</code> отозван.` : `⚠️ Не найдено: ${escapeHtml(target)}`, { parse_mode: "HTML" });
      return jsonResponse({ ok: true });
    }
    if (data === "list_plugins") {
      const catalog = await loadPlugins(env);
      await answerTelegramCallback(env, cq.id, `Плагинов: ${catalog.plugins.length}`);
      if (!catalog.plugins.length) {
        await sendTelegramMessage(env, chatId, "📦 В маркете пока нет плагинов.");
      } else {
        const lines = catalog.plugins.map((p, i) => `${i + 1}. ${p.name} (${p.id}) [${p.language}] v${p.version}`);
        await sendTelegramMessage(env, chatId, `📦 Плагины в маркете (${catalog.plugins.length}):\n\n` + lines.join("\n"));
      }
      return jsonResponse({ ok: true });
    }
    await answerTelegramCallback(env, cq.id);
    return jsonResponse({ ok: true });
  }

  const msg = update.message || update.edited_message;
  if (!msg || !msg.from) {
    return jsonResponse({ ok: true });
  }

  const senderId = String(msg.from.id);
  const chatId = msg.chat?.id ?? msg.from.id;
  const isPrivateChat = msg.chat?.type === "private";
  const senderIsAdmin = isAdminUserId(senderId, env);

  // Strict owner-only & private-chat access: nobody except the owner in DM can use this bot
  if (!senderIsAdmin || senderId !== ownerId || !isPrivateChat) {
    if (isPrivateChat) {
      await sendTelegramMessage(env, chatId, "⛔ Этот бот доступен только владельцу FullGram.");
    }
    return jsonResponse({ ok: true });
  }

  const rawText = (msg.text || "").trim();
  const cmd = rawText.split(/\s+/)[0].toLowerCase().replace(/@[^@\s]+$/, "");
  if (cmd === "/auth" || cmd === "/token" || cmd === "/gen" || cmd === "/gentoken" || cmd === "/admintoken") {
    if (!isPrivateChat) {
      await sendTelegramMessage(
        env,
        chatId,
        "🔒 Генерация админ-токена доступна только в личных сообщениях с ботом."
      );
      return jsonResponse({ ok: true });
    }
    const daysArg = Number(rawText.split(/\s+/)[1]);
    const days = Number.isFinite(daysArg) && daysArg >= 1 ? Math.min(90, Math.floor(daysArg)) : 30;
    try {
      await sendAutoGeneratedAdminToken(env, msg.from.id, senderId, days);
    } catch (err) {
      await sendTelegramMessage(env, msg.from.id, `❌ Не удалось сгенерировать токен: ${err.message}`);
    }
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
      "🛠 Админ-бот маркета FullGram (только для владельца)\n\n" +
      "• Отправьте файл .lua или .py, чтобы опубликовать/обновить плагин в маркете.\n" +
      "• Подпись к файлу: описание или «Название | Описание».\n" +
      "• В начале скрипта можно указать @name, @id, @version, @author, @description.\n\n" +
      "Команды:\n" +
      "/token [дни] или /gen — автогенерация админ-токена (по умолчанию 30 дн., копируется в 1 тап)\n" +
      "/beta [кол-во] [заметка] — создать ссылку для бета-теста\n" +
      "/beta_list — список инвайтов и тестеров\n" +
      "/beta_revoke <код_или_id> — отозвать ссылку или доступ тестера\n" +
      "/list — список плагинов в маркете\n" +
      "/del <id> — удалить плагин из маркета\n" +
      "/badge <id_или_@username> <creator|official|premium|dev|off> — выдать или снять бейдж",
      { reply_markup: adminBotKeyboard() }
    );
    if (text.startsWith("/start") && isPrivateChat) {
      try {
        await sendAutoGeneratedAdminToken(env, msg.from.id, senderId, 30);
      } catch (err) {
        await sendTelegramMessage(env, msg.from.id, `❌ Не удалось авто-сгенерировать токен: ${err.message}`);
      }
    }
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

  if (text.startsWith("/beta")) {
    const parts = text.split(/\s+/);
    const betaCmd = parts[0].toLowerCase().replace(/@[^@\s]+$/, "");
    if (betaCmd === "/beta_list") {
      const [inv, usr] = await Promise.all([loadBetaInvites(env), loadBetaUsers(env)]);
      const invLines = Object.entries(inv.invites || {}).slice(-15).map(([c, info]) =>
        `• <code>${escapeHtml(c)}</code> — ${info.uses || 0}/${info.maxUses || 1}${info.revoked ? " [ОТОЗВАН]" : ""}`
      );
      const usrLines = Object.entries(usr.users || {}).slice(-20).map(([uid, u]) =>
        `• <code>${escapeHtml(uid)}</code>${u.revoked ? " [ОТОЗВАН]" : " [АКТИВЕН]"}`
      );
      await sendTelegramMessage(
        env,
        chatId,
        `🎟 <b>Инвайты беты:</b>\n${invLines.join("\n") || "Нет"}\n\n👤 <b>Пользователи:</b>\n${usrLines.join("\n") || "Нет"}`,
        { parse_mode: "HTML" }
      );
      return jsonResponse({ ok: true });
    }
    if (betaCmd === "/beta_revoke") {
      const target = (parts[1] || "").trim();
      if (!target) {
        await sendTelegramMessage(env, chatId, "Формат: /beta_revoke <code_или_peerId>");
        return jsonResponse({ ok: true });
      }
      const [inv, usr] = await Promise.all([loadBetaInvites(env), loadBetaUsers(env)]);
      let ok = false;
      if (inv.invites[target]) {
        inv.invites[target].revoked = true;
        await saveBetaInvites(env, inv);
        ok = true;
      }
      if (usr.users[target]) {
        usr.users[target].revoked = true;
        await saveBetaUsers(env, usr);
        ok = true;
      }
      await sendTelegramMessage(env, chatId, ok ? `🗑 Бета-доступ/инвайт ${target} отозван.` : `⚠️ Не найдено: ${target}`);
      return jsonResponse({ ok: true });
    }
    const maxUsesRaw = Number(parts[1]);
    const maxUses = Number.isFinite(maxUsesRaw) && maxUsesRaw >= 1 ? Math.min(500, Math.floor(maxUsesRaw)) : 1;
    const note = (Number.isFinite(maxUsesRaw) ? parts.slice(2) : parts.slice(1)).join(" ").trim().slice(0, 80);
    const rand = new Uint8Array(12);
    crypto.getRandomValues(rand);
    const code = `fgb1_${bytesToHex(rand)}`;
    const inv = await loadBetaInvites(env);
    inv.invites[code] = { maxUses, uses: 0, note, createdAt: Math.floor(Date.now() / 1000), revoked: false };
    await saveBetaInvites(env, inv);
    await sendTelegramMessage(
      env,
      chatId,
      `🎟 <b>Ссылка для закрытого бета-теста FullGram</b>\n` +
      `Лимит активаций: <b>${maxUses}</b>${note ? `\nЗаметка: ${escapeHtml(note)}` : ""}\n\n` +
      `🔗 Веб-ссылка:\n<code>${origin}/beta/${code}</code>\n\n` +
      `📲 FullGram:\n<code>fullgram://beta?code=${code}</code>\n` +
      `📲 Telegram:\n<code>tg://fullgram/beta?code=${code}</code>`,
      {
        parse_mode: "HTML",
        reply_markup: {
          inline_keyboard: [[{ text: "🗑 Отозвать эту ссылку", callback_data: `beta_revoke:${code}` }]]
        }
      }
    );
    return jsonResponse({ ok: true });
  }

  if (text.startsWith("/sponsor ") || text.startsWith("/sponsor+ ")) {
    if (!isAdminUserId(senderId, env)) {
      await sendTelegramMessage(env, chatId, "⛔ Команда /sponsor доступна только владельцу FullGram.");
      return jsonResponse({ ok: true });
    }
    const isPlusCmd = text.startsWith("/sponsor+ ");
    const rawArgs = text.slice((isPlusCmd ? "/sponsor+ " : "/sponsor ").length).trim();
    const parts = rawArgs.split(/\s+/);
    const target = parts[0] || "";
    const mode = (parts[1] || (isPlusCmd ? "plus" : "on")).toLowerCase();
    const enabled = mode !== "off" && mode !== "remove" && mode !== "none" && mode !== "0";
    const tier = (isPlusCmd && mode !== "standard" && mode !== "sponsor") || mode === "plus" || mode === "+" || mode === "sponsor+" || mode === "sponsor_plus"
      ? "plus"
      : "standard";
    try {
      const numericId = /^-?\d+$/.test(target) ? target : "";
      const res = await applySponsorChange(env, {
        peerId: numericId || undefined,
        username: numericId ? undefined : target,
        enabled,
        tier
      }, senderId);
      const reply = !enabled
        ? `🗑 С пользователя <code>${escapeHtml(res.peerId)}</code> снят статус спонсора FullGram.`
        : (res.tier === "plus"
          ? `💠 Пользователь <code>${escapeHtml(res.peerId)}</code> назначен <b>Спонсором+</b> FullGram (свой бейдж и выдача NFT любым пользователям).`
          : `💎 Пользователь <code>${escapeHtml(res.peerId)}</code> назначен <b>Спонсором</b> FullGram (доступ к своему бейджу и своим NFT).`);
      await sendTelegramMessage(env, chatId, reply, { parse_mode: "HTML" });
    } catch (err) {
      await sendTelegramMessage(env, chatId, `❌ Ошибка /sponsor: ${err.message}`);
    }
    return jsonResponse({ ok: true });
  }

  if (text.startsWith("/badge ")) {
    const parts = text.slice(7).trim().split(/\s+/);
    if (parts.length < 2) {
      await sendTelegramMessage(env, chatId, "Формат: /badge <user_id_или_@username> <creator|official|sponsor_plus|sponsor|premium|dev|off>");
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
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const origin = url.origin;

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Telegram-Init-Data"
        }
      });
    }

    if (request.method === "GET" && path === "/health") {
      return jsonResponse({ ok: true, service: "fullgram-worker" });
    }

    if (request.method === "POST" && path === "/auth/session") {
      try {
        const body = await request.json();
        const peerId = normalizePeerId(body.peerId ?? body.userId ?? "");
        const deviceSecret = String(body.deviceSecret || "").trim();
        if (!peerId || deviceSecret.length < 16) {
          return jsonResponse({ ok: false, error: "Valid peerId and deviceSecret (min 16 chars) required" }, 400);
        }
        const secretHash = await sha256Hex(deviceSecret);
        if (env.FULLGRAM_KV) {
          const kvKey = `fg_device_session:${peerId}`;
          let entry = { hashes: [] };
          const raw = await env.FULLGRAM_KV.get(kvKey);
          if (raw) {
            try {
              const parsed = JSON.parse(raw);
              if (Array.isArray(parsed.hashes)) entry.hashes = parsed.hashes;
            } catch {}
          }
          if (!entry.hashes.includes(secretHash)) {
            if (isAdminUserId(peerId, env) && entry.hashes.length >= 4) {
              // Keep owner device slots bounded while permitting legitimate reinstalls on fresh non-admin accounts.
              entry.hashes = entry.hashes.slice(-3);
            } else if (entry.hashes.length >= 6) {
              entry.hashes = entry.hashes.slice(-5);
            }
            entry.hashes.push(secretHash);
            entry.updatedAt = new Date().toISOString();
            await env.FULLGRAM_KV.put(kvKey, JSON.stringify(entry));
          }
        }
        const issued = await issueSessionToken(peerId, "user", env, 30 * 24 * 60 * 60);
        return jsonResponse({
          ok: true,
          token: issued.token,
          expiresAt: issued.expiresAt,
          uid: peerId,
          userId: peerId,
          role: "user",
          isAdmin: false,
          expiresIn: 30 * 24 * 60 * 60
        });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "GET" && path === "/casino") {
      return new Response(CASINO_HTML, {
        status: 200,
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-cache"
        }
      });
    }

    if (request.method === "GET" && path === "/config.json") {
      return jsonResponse(await loadFeatureFlags(env));
    }

    if (request.method === "GET" && path === "/sponsors.json") {
      return jsonResponse(await loadSponsors(env), 200, {
        "Cache-Control": "public, max-age=15, s-maxage=30, stale-while-revalidate=60"
      });
    }

    if (request.method === "GET" && path.startsWith("/assets/frames/")) {
      const fileName = path.slice("/assets/frames/".length).trim();
      if (!/^[a-zA-Z0-9_-]+\.png$/.test(fileName)) {
        return new Response("Not Found", { status: 404 });
      }
      const cache = caches.default;
      const cachedResp = await cache.match(request);
      if (cachedResp) {
        return cachedResp;
      }
      const sources = [
        `https://raw.githubusercontent.com/shermanko/FullGram/release/next/assets/frames/${fileName}`,
        `https://cdn.jsdelivr.net/gh/shermanko/FullGram@release/next/assets/frames/${fileName}`
      ];
      for (const srcUrl of sources) {
        try {
          const upstream = await fetch(srcUrl, { cf: { cacheTtl: 86400, cacheEverything: true } });
          if (upstream.ok) {
            const resp = new Response(upstream.body, {
              status: 200,
              headers: {
                "Content-Type": "image/png",
                "Cache-Control": "public, max-age=86400, s-maxage=604800",
                "Access-Control-Allow-Origin": "*",
                "X-Content-Type-Options": "nosniff"
              }
            });
            ctx.waitUntil(cache.put(request, resp.clone()));
            return resp;
          }
        } catch {
          // try next mirror
        }
      }
      return new Response("Not Found", { status: 404 });
    }

    if (request.method === "GET" && path.startsWith("/frames/")) {
      const fileName = path.slice("/frames/".length).replace(/[^a-zA-Z0-9._-]/g, "");
      if (!fileName || !env.FULLGRAM_KV) {
        return new Response("Not found", { status: 404 });
      }
      const raw = await env.FULLGRAM_KV.get(`custom_frame:${fileName}`, "arrayBuffer");
      if (!raw) {
        return new Response("Not found", { status: 404 });
      }
      return new Response(raw, {
        status: 200,
        headers: {
          "Content-Type": fileName.endsWith(".gif") ? "image/gif" : "image/png",
          "Cache-Control": "public, max-age=604800",
          "X-Content-Type-Options": "nosniff"
        }
      });
    }

    if (request.method === "GET" && path === "/auth/me") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: true, authenticated: false, userId: null, isAdmin: false });
      }
      return jsonResponse({
        ok: true,
        authenticated: true,
        userId: auth.uid,
        isAdmin: Boolean(auth.isAdmin),
        method: auth.method
      });
    }

    if (request.method === "POST" && path === "/auth/telegram") {
      let body = {};
      try {
        body = await request.json();
      } catch {
        body = {};
      }
      const initData = (typeof body.initData === "string" && body.initData.trim())
        ? body.initData.trim()
        : (request.headers.get("X-Telegram-Init-Data") || "").trim();
      const verified = await verifyTelegramInitData(initData, env);
      if (!verified) {
        return jsonResponse({ ok: false, error: "Invalid or expired Telegram auth signature" }, 401);
      }
      try {
        const issued = await issueSessionToken(verified.uid, verified.isAdmin ? "admin" : "user", env);
        return jsonResponse({
          ok: true,
          userId: verified.uid,
          isAdmin: verified.isAdmin,
          token: issued.token,
          expiresAt: issued.expiresAt
        });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 500);
      }
    }

    if (request.method === "GET" && path === "/badges.json") {
      return jsonResponse(await loadBadges(env), 200, {
        "Cache-Control": "public, max-age=15, s-maxage=30, stale-while-revalidate=60"
      });
    }

    if (request.method === "GET" && path === "/cosmetics.json") {
      return jsonResponse(await loadCosmetics(env), 200, {
        "Cache-Control": "public, max-age=15, s-maxage=30, stale-while-revalidate=60"
      });
    }

    if (request.method === "GET" && path === "/discord-cosmetics.json") {
      if (env.FULLGRAM_KV) {
        const cached = await env.FULLGRAM_KV.get("discord_cosmetics.json");
        if (cached) {
          return new Response(cached, {
            status: 200,
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Cache-Control": "public, max-age=3600, s-maxage=86400",
              "Access-Control-Allow-Origin": "*"
            }
          });
        }
      }
      try {
        const upstream = await fetch("https://raw.githubusercontent.com/shermanko/FullGram/release/next/assets/discord_cosmetics.json");
        if (upstream.ok) {
          const text = await upstream.text();
          if (env.FULLGRAM_KV && text.length > 50) {
            ctx.waitUntil(env.FULLGRAM_KV.put("discord_cosmetics.json", text));
          }
          return new Response(text, {
            status: 200,
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Cache-Control": "public, max-age=3600, s-maxage=86400",
              "Access-Control-Allow-Origin": "*"
            }
          });
        }
      } catch {
        // fall through
      }
      return jsonResponse({ version: 2, frames: [], profileEffects: [] });
    }

    if (request.method === "GET" && path.startsWith("/beta/")) {
      const code = path.slice("/beta/".length).trim().replace(/[^a-zA-Z0-9_.-]/g, "");
      if (!code) {
        return new Response("Invalid beta invite code", { status: 400 });
      }
      const inv = await loadBetaInvites(env);
      const entry = inv.invites && inv.invites[code] ? inv.invites[code] : null;
      const now = Math.floor(Date.now() / 1000);
      const maxUses = entry ? (entry.maxUses || 1) : 0;
      const uses = entry ? (entry.uses || 0) : 0;
      const statusInfo = {
        exists: Boolean(entry),
        revoked: Boolean(entry?.revoked),
        expired: Boolean(entry?.expiresAt && now > entry.expiresAt),
        exhausted: Boolean(entry && uses >= maxUses),
        maxUses,
        remaining: Math.max(0, maxUses - uses)
      };
      return new Response(renderBetaLandingHtml(code, origin, statusInfo), {
        status: 200,
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store"
        }
      });
    }

    if (request.method === "POST" && path === "/beta/activate") {
      try {
        const body = await request.json();
        const code = String(body.code || "").trim();
        const peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
        const deviceSecret = String(body.deviceSecret || "").trim();
        if (!code || !peerId || !/^-?\d{1,20}$/.test(peerId) || deviceSecret.length < 16) {
          return jsonResponse({ ok: false, error: "Требуется корректный код приглашения и устройство." }, 400);
        }
        const inv = await loadBetaInvites(env);
        const entry = inv.invites[code];
        const now = Math.floor(Date.now() / 1000);
        if (!entry || entry.revoked) {
          return jsonResponse({ ok: false, error: "Ссылка приглашения недействительна или отозвана." }, 403);
        }
        if (entry.expiresAt && now > entry.expiresAt) {
          return jsonResponse({ ok: false, error: "Срок действия ссылки приглашения истёк." }, 403);
        }
        const deviceHash = await sha256Hex(deviceSecret);
        const usersData = await loadBetaUsers(env);
        const existingUser = usersData.users[peerId];
        if (existingUser && existingUser.revoked && existingUser.code === code) {
          return jsonResponse({ ok: false, error: "Ваш доступ по этому приглашению был отозван." }, 403);
        }
        if (!existingUser || existingUser.code !== code) {
          if ((entry.uses || 0) >= (entry.maxUses || 1)) {
            return jsonResponse({ ok: false, error: "Лимит активаций этой ссылки исчерпан." }, 403);
          }
          entry.uses = (entry.uses || 0) + 1;
          inv.invites[code] = entry;
          await saveBetaInvites(env, inv);
        }
        usersData.users[peerId] = {
          deviceHash,
          code,
          activatedAt: now,
          revoked: false
        };
        await saveBetaUsers(env, usersData);
        const receipt = await issueBetaReceipt(peerId, deviceHash, code, env);
        return jsonResponse({ ok: true, active: true, peerId, receipt });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/beta/status") {
      try {
        const body = await request.json();
        const receipt = String(body.receipt || "").trim();
        const peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
        const deviceSecret = String(body.deviceSecret || "").trim();
        if (!receipt || !peerId || deviceSecret.length < 16) {
          return jsonResponse({ ok: true, active: false });
        }
        const verified = await verifyBetaReceipt(receipt, env);
        if (!verified || verified.uid !== peerId) {
          return jsonResponse({ ok: true, active: false });
        }
        const deviceHash = await sha256Hex(deviceSecret);
        if (!timingSafeEqual(verified.dh, deviceHash)) {
          return jsonResponse({ ok: true, active: false });
        }
        const usersData = await loadBetaUsers(env);
        const userRec = usersData.users[peerId];
        if (!userRec || userRec.revoked) {
          return jsonResponse({ ok: true, active: false });
        }
        return jsonResponse({ ok: true, active: true, peerId });
      } catch {
        return jsonResponse({ ok: true, active: false });
      }
    }

    if (request.method === "GET" && path === "/economy.json") {
      return jsonResponse(await loadEconomy(env), 200, {
        "Cache-Control": "public, max-age=15, s-maxage=30, stale-while-revalidate=60"
      });
    }

    if (request.method === "GET" && path === "/nfts.json") {
      return jsonResponse(await loadNfts(env), 200, {
        "Cache-Control": "public, max-age=15, s-maxage=30, stale-while-revalidate=60"
      });
    }

    if (request.method === "POST" && path === "/decorations/batch") {
      try {
        const body = await request.json();
        const rawIds = Array.isArray(body.peerIds) ? body.peerIds : [];
        const peerIds = Array.from(new Set(
          rawIds.map((v) => normalizePeerId(String(v || "").trim())).filter((v) => /^-?\d{1,20}$/.test(v))
        )).slice(0, 100);
        const [badges, cosmetics, nfts, sponsorsData] = await Promise.all([
          loadBadges(env),
          loadCosmetics(env),
          loadNfts(env),
          loadSponsors(env)
        ]);
        const users = {};
        for (const id of peerIds) {
          const roleId = badges.users[id] || null;
          const badge = roleId && badges.roles[roleId] ? { roleId, ...badges.roles[roleId] } : null;
          const cosmetic = cosmetics.users[id] || null;
          const userNfts = Array.isArray(nfts.users[id]) ? nfts.users[id] : [];
          const sponsorEntry = sponsorsData.sponsors && sponsorsData.sponsors[id] ? sponsorsData.sponsors[id] : null;
          const isSponsor = Boolean(sponsorEntry);
          const sponsorTier = sponsorEntry ? normalizeSponsorTier(sponsorEntry.tier) : null;
          if (badge || cosmetic || userNfts.length || isSponsor) {
            users[id] = { badge, cosmetics: cosmetic, nfts: userNfts, isSponsor, sponsorTier };
          }
        }
        return jsonResponse({ ok: true, version: 1, users });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/cosmetics") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized: valid Telegram auth or session token required" }, 401);
      }
      try {
        const body = await request.json();
        const requestedRaw = body.peerId != null ? String(body.peerId).trim() : (body.userId != null ? String(body.userId).trim() : String(auth.uid));
        const requestedPeerId = normalizePeerId(requestedRaw);
        const authPeerId = normalizePeerId(String(auth.uid || ""));
        if (!requestedPeerId || (!auth.isAdmin && requestedPeerId !== authPeerId)) {
          return jsonResponse({ ok: false, error: "Forbidden: can only modify your own cosmetics" }, 403);
        }
        const user = await applyCosmeticChange(env, { ...body, peerId: requestedPeerId });
        return jsonResponse({ ok: true, user });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/cosmetics/upload-frame") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized: valid session token required" }, 401);
      }
      if (!env.FULLGRAM_KV) {
        return jsonResponse({ ok: false, error: "Storage unavailable" }, 503);
      }
      try {
        const body = await request.json();
        const requestedPeerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : String(auth.uid));
        const authPeerId = normalizePeerId(String(auth.uid || ""));
        if (!requestedPeerId || (!auth.isAdmin && requestedPeerId !== authPeerId)) {
          return jsonResponse({ ok: false, error: "Forbidden" }, 403);
        }
        const b64 = String(body.imageBase64 || "").trim();
        if (!b64) {
          return jsonResponse({ ok: false, error: "imageBase64 required" }, 400);
        }
        const binStr = atob(b64);
        if (binStr.length < 32 || binStr.length > 1600 * 1024) {
          return jsonResponse({ ok: false, error: "Frame file too large or empty (max 1.5 MB)" }, 400);
        }
        const bytes = new Uint8Array(binStr.length);
        for (let i = 0; i < binStr.length; i++) {
          bytes[i] = binStr.charCodeAt(i);
        }
        const ext = String(body.ext || "png").toLowerCase() === "gif" ? "gif" : "png";
        const keyId = `u_${requestedPeerId}_${Date.now().toString(36)}.${ext}`;
        await env.FULLGRAM_KV.put(`custom_frame:${keyId}`, bytes.buffer);
        const frameUrl = `${url.origin}/frames/${keyId}`;
        const user = await applyCosmeticChange(env, { peerId: requestedPeerId, frameId: "custom", customFrameUrl: frameUrl });
        return jsonResponse({ ok: true, url: frameUrl, user });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/sponsor/badge") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
      }
      const sponsorTier = auth.isAdmin ? "plus" : (await getSponsorTier(env, auth.uid));
      if (!sponsorTier) {
        return jsonResponse({ ok: false, error: "Forbidden: sponsor access required" }, 403);
      }
      try {
        const body = await request.json();
        const selfPeerId = normalizePeerId(String(auth.uid));
        const requestedRaw = body.peerId != null
          ? String(body.peerId).trim()
          : (body.userId != null ? String(body.userId).trim() : selfPeerId);
        const targetPeerId = normalizePeerId(requestedRaw || selfPeerId);
        if (!targetPeerId || !/^-?\d{1,20}$/.test(targetPeerId)) {
          return jsonResponse({ ok: false, error: "Invalid target peerId" }, 400);
        }
        if (!auth.isAdmin && sponsorTier !== "plus" && targetPeerId !== selfPeerId) {
          return jsonResponse({ ok: false, error: "Forbidden: Sponsor+ access required to manage badges for other users" }, 403);
        }
        const fallbackRole = sponsorTier === "plus" ? "sponsor_plus" : "sponsor";
        const reqRole = String(body.roleId || fallbackRole).trim().toLowerCase();
        const disallowedRoles = new Set(["creator", "official", "admin", "owner"]);
        if (!auth.isAdmin && sponsorTier !== "plus") {
          disallowedRoles.add("sponsor_plus");
        }
        const safeRole = disallowedRoles.has(reqRole) ? fallbackRole : reqRole;
        const badges = await applyBadgeChange(env, {
          ...body,
          peerId: targetPeerId,
          username: null,
          roleId: safeRole
        });
        return jsonResponse({
          ok: true,
          usersCount: Object.keys(badges.users).length + Object.keys(badges.usernames).length
        });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/nft/action") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
      }
      try {
        const body = await request.json();
        const sponsorTier = auth.isAdmin ? "plus" : (await getSponsorTier(env, auth.uid));
        const canManageAny = Boolean(auth.isAdmin || sponsorTier === "plus");
        const result = await applyNftAction(env, body, auth.uid, canManageAny);
        return jsonResponse({ ok: true, ...result });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/sponsor/economy") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
      }
      const sponsorTier = auth.isAdmin ? "plus" : (await getSponsorTier(env, auth.uid));
      if (!auth.isAdmin && sponsorTier !== "plus") {
        return jsonResponse({ ok: false, error: "Forbidden: Sponsor+ access required" }, 403);
      }
      try {
        const body = await request.json();
        const result = await applyEconomyChange(env, body, auth.uid);
        return jsonResponse({ ok: true, ...result });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && path === "/sponsor/nft") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
      }
      const sponsorTier = auth.isAdmin ? "plus" : (await getSponsorTier(env, auth.uid));
      if (!sponsorTier) {
        return jsonResponse({ ok: false, error: "Forbidden: sponsor access required" }, 403);
      }
      try {
        const body = await request.json();
        const selfPeerId = normalizePeerId(String(auth.uid));
        const requestedRaw = body.peerId != null
          ? String(body.peerId).trim()
          : (body.userId != null ? String(body.userId).trim() : selfPeerId);
        const targetPeerId = normalizePeerId(requestedRaw || selfPeerId);
        if (!targetPeerId || !/^-?\d{1,20}$/.test(targetPeerId)) {
          return jsonResponse({ ok: false, error: "Invalid target peerId" }, 400);
        }
        if (!auth.isAdmin && sponsorTier !== "plus" && targetPeerId !== selfPeerId) {
          return jsonResponse({ ok: false, error: "Forbidden: Sponsor+ access required to grant NFTs to other users" }, 403);
        }
        const result = await applyNftChange(env, { ...body, peerId: targetPeerId }, auth.uid);
        return jsonResponse({ ok: true, ...result });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
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
      const builtin = DEFAULT_PLUGINS.plugins.find((p) => p.id === id);
      let code = (builtin && builtin.code) ? builtin.code : null;
      if (code == null && env.FULLGRAM_KV) {
        code = await env.FULLGRAM_KV.get(`script:${id}`);
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

    // Protected Admin Endpoints (strict server-side Telegram-signed or signed-session admin check)
    if (path.startsWith("/admin/")) {
      const auth = await authenticateRequest(request, env);
      if (!auth || !auth.isAdmin) {
        return jsonResponse({ ok: false, error: "Unauthorized: admin verification failed" }, 401);
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

      if (request.method === "POST" && path === "/admin/cosmetics") {
        try {
          const body = await request.json();
          const user = await applyCosmeticChange(env, body);
          return jsonResponse({ ok: true, user });
        } catch (err) {
          return jsonResponse({ ok: false, error: err.message }, 400);
        }
      }

      if (request.method === "GET" && path === "/admin/sponsors") {
        return jsonResponse({ ok: true, ...(await loadSponsors(env)) });
      }

      if (request.method === "POST" && path === "/admin/sponsor") {
        try {
          const body = await request.json();
          const result = await applySponsorChange(env, body, auth.uid);
          return jsonResponse({ ok: true, ...result });
        } catch (err) {
          return jsonResponse({ ok: false, error: err.message }, 400);
        }
      }

      if (request.method === "POST" && path === "/admin/nft") {
        try {
          const body = await request.json();
          const result = await applyNftChange(env, body, auth.uid);
          return jsonResponse({ ok: true, ...result });
        } catch (err) {
          return jsonResponse({ ok: false, error: err.message }, 400);
        }
      }

      if (request.method === "POST" && path === "/admin/economy") {
        try {
          const body = await request.json();
          const result = await applyEconomyChange(env, body, auth.uid);
          return jsonResponse({ ok: true, ...result });
        } catch (err) {
          return jsonResponse({ ok: false, error: err.message }, 400);
        }
      }

      if (request.method === "GET" && path === "/admin/flags") {
        return jsonResponse({ ok: true, ...(await loadFeatureFlags(env)) });
      }

      if (request.method === "POST" && path === "/admin/flags") {
        try {
          const body = await request.json();
          const current = await loadFeatureFlags(env);
          const updates = (body && typeof body.flags === "object" && body.flags) ? body.flags : body;
          for (const [k, v] of Object.entries(updates || {})) {
            if (typeof v === "boolean" && /^[a-zA-Z0-9_]{1,48}$/.test(k)) {
              current.flags[k] = v;
            }
          }
          current.version = (current.version || 1) + 1;
          await saveFeatureFlags(env, current);
          return jsonResponse({ ok: true, ...current });
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
            allowed_updates: ["message", "edited_message", "callback_query"]
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
