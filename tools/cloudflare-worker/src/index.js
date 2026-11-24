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
    const rawNumber = String(body.number || "").trim();
    userEntry.numbers = userEntry.numbers.filter((n) => n.id !== targetId && (!rawNumber || String(n.number || "").trim() !== rawNumber));
  } else if (action === "toggle_username") {
    const clean = String(body.username || "").trim().replace(/^@+/, "").toLowerCase();
    const targetId = String(body.id || "").trim();
    const makeActive = body.isActive !== undefined ? Boolean(body.isActive) : null;
    const makePrimary = body.isPrimary !== undefined ? Boolean(body.isPrimary) : null;
    userEntry.usernames = userEntry.usernames.map((u) => {
      const match = (targetId && u.id === targetId) || (clean && String(u.username || "").toLowerCase() === clean);
      if (!match) {
        return makePrimary === true ? { ...u, isPrimary: false } : u;
      }
      const nextActive = makeActive !== null ? makeActive : !u.isActive;
      const nextPrimary = makePrimary !== null ? makePrimary : (nextActive ? u.isPrimary : false);
      return { ...u, isActive: nextActive, isPrimary: nextActive ? nextPrimary : false };
    });
  } else if (action === "toggle_number") {
    const targetId = String(body.id || "").trim();
    const rawNumber = String(body.number || "").trim();
    const makeActive = body.isActive !== undefined ? Boolean(body.isActive) : null;
    userEntry.numbers = userEntry.numbers.map((n) => {
      const match = (targetId && n.id === targetId) || (rawNumber && String(n.number || "").trim() === rawNumber);
      if (!match) {
        return makeActive === true ? { ...n, isActive: false } : n;
      }
      const nextActive = makeActive !== null ? makeActive : !n.isActive;
      return { ...n, isActive: nextActive };
    });
  } else if (action === "transfer_username") {
    const toPeerId = normalizePeerId(body.toPeerId != null ? String(body.toPeerId).trim() : "");
    if (!toPeerId || !/^-?\d{1,20}$/.test(toPeerId) || toPeerId === peerId) {
      throw new Error("Invalid recipient peerId");
    }
    const clean = String(body.username || "").trim().replace(/^@+/, "").toLowerCase();
    const targetId = String(body.id || "").trim();
    const idx = userEntry.usernames.findIndex((u) => (targetId && u.id === targetId) || (clean && String(u.username || "").toLowerCase() === clean));
    if (idx < 0) throw new Error("Username not found");
    const [moved] = userEntry.usernames.splice(idx, 1);
    const dst = eco.users[toPeerId] && typeof eco.users[toPeerId] === "object"
      ? {
          gramBalance: Number(eco.users[toPeerId].gramBalance || 0),
          starsBalance: Number(eco.users[toPeerId].starsBalance || 0),
          usernames: Array.isArray(eco.users[toPeerId].usernames) ? [...eco.users[toPeerId].usernames] : [],
          numbers: Array.isArray(eco.users[toPeerId].numbers) ? [...eco.users[toPeerId].numbers] : []
        }
      : { gramBalance: 0, starsBalance: 0, usernames: [], numbers: [] };
    dst.usernames = dst.usernames.filter((u) => String(u.username || "").toLowerCase() !== String(moved.username || "").toLowerCase());
    dst.usernames.unshift({ ...moved, isActive: true, isPrimary: dst.usernames.length === 0, purchasedAt: nowSec });
    dst.usernames = dst.usernames.slice(0, 30);
    eco.users[toPeerId] = dst;
  } else if (action === "transfer_number") {
    const toPeerId = normalizePeerId(body.toPeerId != null ? String(body.toPeerId).trim() : "");
    if (!toPeerId || !/^-?\d{1,20}$/.test(toPeerId) || toPeerId === peerId) {
      throw new Error("Invalid recipient peerId");
    }
    const targetId = String(body.id || "").trim();
    const rawNumber = String(body.number || "").trim();
    const idx = userEntry.numbers.findIndex((n) => (targetId && n.id === targetId) || (rawNumber && String(n.number || "").trim() === rawNumber));
    if (idx < 0) throw new Error("Number not found");
    const [moved] = userEntry.numbers.splice(idx, 1);
    const dst = eco.users[toPeerId] && typeof eco.users[toPeerId] === "object"
      ? {
          gramBalance: Number(eco.users[toPeerId].gramBalance || 0),
          starsBalance: Number(eco.users[toPeerId].starsBalance || 0),
          usernames: Array.isArray(eco.users[toPeerId].usernames) ? [...eco.users[toPeerId].usernames] : [],
          numbers: Array.isArray(eco.users[toPeerId].numbers) ? [...eco.users[toPeerId].numbers] : []
        }
      : { gramBalance: 0, starsBalance: 0, usernames: [], numbers: [] };
    dst.numbers = dst.numbers.filter((n) => String(n.number || "") !== String(moved.number || ""));
    dst.numbers.unshift({ ...moved, isActive: dst.numbers.every((n) => !n.isActive), purchasedAt: nowSec });
    dst.numbers = dst.numbers.slice(0, 30);
    eco.users[toPeerId] = dst;
  } else if (action === "transfer_gram") {
    const toPeerId = normalizePeerId(body.toPeerId != null ? String(body.toPeerId).trim() : "");
    const amount = Number(body.amount);
    if (!toPeerId || !/^-?\d{1,20}$/.test(toPeerId) || toPeerId === peerId || !Number.isFinite(amount) || amount <= 0) {
      throw new Error("Invalid transfer parameters");
    }
    userEntry.gramBalance = Math.max(0, Math.round((userEntry.gramBalance - amount) * 100) / 100);
    const dst = eco.users[toPeerId] && typeof eco.users[toPeerId] === "object"
      ? {
          gramBalance: Number(eco.users[toPeerId].gramBalance || 0),
          starsBalance: Number(eco.users[toPeerId].starsBalance || 0),
          usernames: Array.isArray(eco.users[toPeerId].usernames) ? [...eco.users[toPeerId].usernames] : [],
          numbers: Array.isArray(eco.users[toPeerId].numbers) ? [...eco.users[toPeerId].numbers] : []
        }
      : { gramBalance: 0, starsBalance: 0, usernames: [], numbers: [] };
    dst.gramBalance = Math.round((dst.gramBalance + amount) * 100) / 100;
    eco.users[toPeerId] = dst;
  } else if (action === "transfer_stars") {
    const toPeerId = normalizePeerId(body.toPeerId != null ? String(body.toPeerId).trim() : "");
    const amount = Math.floor(Number(body.amount));
    if (!toPeerId || !/^-?\d{1,20}$/.test(toPeerId) || toPeerId === peerId || !Number.isFinite(amount) || amount <= 0) {
      throw new Error("Invalid transfer parameters");
    }
    userEntry.starsBalance = Math.max(0, Math.floor(userEntry.starsBalance - amount));
    const dst = eco.users[toPeerId] && typeof eco.users[toPeerId] === "object"
      ? {
          gramBalance: Number(eco.users[toPeerId].gramBalance || 0),
          starsBalance: Number(eco.users[toPeerId].starsBalance || 0),
          usernames: Array.isArray(eco.users[toPeerId].usernames) ? [...eco.users[toPeerId].usernames] : [],
          numbers: Array.isArray(eco.users[toPeerId].numbers) ? [...eco.users[toPeerId].numbers] : []
        }
      : { gramBalance: 0, starsBalance: 0, usernames: [], numbers: [] };
    dst.starsBalance = Math.floor(dst.starsBalance + amount);
    eco.users[toPeerId] = dst;
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

let cachedBotUsername = null;

async function resolveBotUsername(env) {
  const fromEnv = String(env.BOT_USERNAME || "").trim().replace(/^@/, "");
  if (fromEnv) return fromEnv;
  if (cachedBotUsername) return cachedBotUsername;
  if (env.FULLGRAM_KV) {
    try {
      const fromKv = String((await env.FULLGRAM_KV.get("beta_bot_username_v1")) || "").trim().replace(/^@/, "");
      if (fromKv) {
        cachedBotUsername = fromKv;
        return fromKv;
      }
    } catch {}
  }
  const token = String(env.TG_BOT_TOKEN || "").trim();
  if (!token) return "";
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/getMe`);
    const data = await res.json();
    const uname = String(data?.result?.username || "").trim().replace(/^@/, "");
    if (uname) {
      cachedBotUsername = uname;
      if (env.FULLGRAM_KV) {
        await env.FULLGRAM_KV.put("beta_bot_username_v1", uname);
      }
      return uname;
    }
  } catch {}
  return "";
}

async function redeemBetaInvite(env, rawCode, rawPeerId, opts = {}) {
  const code = String(rawCode || "").trim();
  const peerId = normalizePeerId(rawPeerId != null ? String(rawPeerId).trim() : "");
  if (!code || !peerId || !/^-?\d{1,20}$/.test(peerId)) {
    return { ok: false, status: 400, error: "Требуется корректный код приглашения и ID аккаунта." };
  }
  const [inv, usersData] = await Promise.all([loadBetaInvites(env), loadBetaUsers(env)]);
  let matchedCode = inv.invites[code] ? code : null;
  if (!matchedCode) {
    const lower = code.toLowerCase();
    matchedCode = Object.keys(inv.invites || {}).find((k) => k.toLowerCase() === lower) || null;
  }
  const entry = matchedCode ? inv.invites[matchedCode] : null;
  const now = Math.floor(Date.now() / 1000);
  if (!entry || entry.revoked) {
    return { ok: false, status: 403, error: "Ссылка приглашения недействительна или отозвана." };
  }
  if (entry.expiresAt && now > entry.expiresAt) {
    return { ok: false, status: 403, error: "Срок действия ссылки приглашения истёк." };
  }
  const existingUser = usersData.users[peerId];
  if (existingUser && existingUser.revoked) {
    return { ok: false, status: 403, error: "Ваш доступ был отозван администратором." };
  }
  const alreadyUsingThisCode = Boolean(existingUser && existingUser.code === matchedCode && existingUser.activatedAt);
  if (!alreadyUsingThisCode) {
    if ((entry.uses || 0) >= (entry.maxUses || 1)) {
      return { ok: false, status: 403, error: "Лимит активаций этой ссылки исчерпан." };
    }
    entry.uses = (entry.uses || 0) + 1;
    inv.invites[matchedCode] = entry;
    await saveBetaInvites(env, inv);
  }
  usersData.users[peerId] = {
    ...(existingUser || {}),
    code: matchedCode,
    deviceHash: opts.deviceHash || existingUser?.deviceHash || "",
    via: opts.via || existingUser?.via || "app",
    username: opts.username || existingUser?.username || "",
    activatedAt: existingUser?.activatedAt || now,
    updatedAt: now,
    revoked: false
  };
  await saveBetaUsers(env, usersData);
  return {
    ok: true,
    code: matchedCode,
    peerId,
    alreadyActive: Boolean(existingUser && !existingUser.revoked),
    remaining: Math.max(0, (entry.maxUses || 1) - (entry.uses || 0))
  };
}

function extractBetaInviteCodeFromText(raw) {
  const s = String(raw || "").trim();
  if (!s) return "";
  const urlMatch = s.match(/\/beta\/([A-Za-z0-9_.-]{6,80})/i);
  if (urlMatch) return urlMatch[1];
  const startParamMatch = s.match(/[?&]start=(?:beta[_-])?([A-Za-z0-9_.-]{6,80})/i);
  if (startParamMatch) return startParamMatch[1];
  const codeParamMatch = s.match(/[?&]code=([A-Za-z0-9_.-]{6,80})/i);
  if (codeParamMatch) return codeParamMatch[1];
  const cmdMatch = s.match(/^\/(?:start|activate)(?:@\S+)?\s+(?:beta[_-])?([A-Za-z0-9_.-]{6,80})$/i);
  if (cmdMatch) return cmdMatch[1];
  const fgbMatch = s.match(/\b(fgb1_[A-Za-z0-9_.-]{6,80})\b/i);
  if (fgbMatch) return fgbMatch[1];
  if (/^[A-Za-z0-9_.-]{10,80}$/.test(s) && !s.startsWith("/")) {
    return s;
  }
  return "";
}

function renderBetaLandingHtml(code, origin, inviteStatus = null, options = {}) {
  const safeCode = escapeHtml(code || "");
  const botUsername = String(options.botUsername || "").trim().replace(/^@/, "");
  const done = Boolean(options.done);
  const hasCode = Boolean(code);
  const deepLink = hasCode ? `fullgram://beta?code=${encodeURIComponent(code)}` : "fullgram://beta";
  const syncLink = "fullgram://beta";
  const botLink = botUsername
    ? (hasCode
      ? `https://t.me/${encodeURIComponent(botUsername)}?start=beta_${encodeURIComponent(code)}`
      : `https://t.me/${encodeURIComponent(botUsername)}`)
    : "";

  let statusBadge = "Портал закрытого бета-теста";
  let statusClass = "info";
  if (done) {
    statusBadge = "Бета-доступ активирован";
    statusClass = "ok";
  } else if (hasCode && inviteStatus) {
    if (inviteStatus.revoked) {
      statusBadge = "Инвайт отозван";
      statusClass = "err";
    } else if (inviteStatus.expired) {
      statusBadge = "Срок действия истёк";
      statusClass = "err";
    } else if (inviteStatus.exhausted) {
      statusBadge = "Лимит активаций исчерпан";
      statusClass = "warn";
    } else if (!inviteStatus.exists) {
      statusBadge = "Инвайт-код не найден";
      statusClass = "err";
    } else {
      statusBadge = `Инвайт активен · свободно ${inviteStatus.remaining} из ${inviteStatus.maxUses}`;
      statusClass = "ok";
    }
  }

  const botPrimaryBlock = botLink
    ? `<a class="btn btn-primary" id="tgBotBtn" href="${escapeHtml(botLink)}">
        <span class="btn-ico">🤖</span>
        <span>${hasCode ? "Активировать через Telegram в 1 клик" : "Открыть бота активации в Telegram"}</span>
      </a>`
    : "";

  return `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover" />
  <title>FullGram Beta · Активация доступа</title>
  <script src="https://telegram.org/js/telegram-web-app.js"></script>
  <style>
    :root {
      --bg: #07090f;
      --card: rgba(19, 23, 35, 0.86);
      --card-2: rgba(255, 255, 255, 0.045);
      --border: rgba(255, 255, 255, 0.09);
      --text: #f8fafc;
      --muted: #94a3b8;
      --accent: #3b82f6;
      --accent-2: #8b5cf6;
      --ok: #34d399;
      --warn: #fbbf24;
      --err: #f87171;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background:
        radial-gradient(circle at 18% 12%, rgba(59,130,246,0.22), transparent 42%),
        radial-gradient(circle at 82% 18%, rgba(139,92,246,0.20), transparent 44%),
        radial-gradient(circle at 50% 92%, rgba(16,185,129,0.12), transparent 48%),
        var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
      padding: 24px 16px 42px;
      display: flex;
      justify-content: center;
      align-items: flex-start;
    }
    .wrap {
      width: 100%;
      max-width: 500px;
      margin-top: 8px;
    }
    .hero {
      background: var(--card);
      backdrop-filter: blur(22px);
      -webkit-backdrop-filter: blur(22px);
      border: 1px solid var(--border);
      border-radius: 26px;
      padding: 26px 22px 22px;
      box-shadow: 0 24px 64px rgba(0, 0, 0, 0.55);
    }
    .top-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      margin-bottom: 16px;
      flex-wrap: wrap;
    }
    .brand {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      font-weight: 800;
      font-size: 16px;
      letter-spacing: -0.2px;
    }
    .brand-logo {
      width: 34px;
      height: 34px;
      border-radius: 11px;
      background: linear-gradient(135deg, #38bdf8, #6366f1 55%, #a855f7);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 17px;
      box-shadow: 0 8px 20px rgba(99, 102, 241, 0.38);
    }
    .pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      border: 1px solid var(--border);
      background: rgba(255, 255, 255, 0.05);
    }
    .pill.ok { color: var(--ok); border-color: rgba(52, 211, 153, 0.3); background: rgba(52, 211, 153, 0.10); }
    .pill.warn { color: var(--warn); border-color: rgba(251, 191, 36, 0.3); background: rgba(251, 191, 36, 0.10); }
    .pill.err { color: var(--err); border-color: rgba(248, 113, 113, 0.3); background: rgba(248, 113, 113, 0.10); }
    .pill.info { color: #93c5fd; border-color: rgba(147, 197, 253, 0.25); background: rgba(59, 130, 246, 0.10); }
    h1 {
      font-size: 24px;
      line-height: 1.2;
      margin: 0 0 8px;
      letter-spacing: -0.4px;
    }
    .lead {
      font-size: 14px;
      line-height: 1.55;
      color: var(--muted);
      margin: 0 0 18px;
    }
    .tabs {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 6px;
      background: rgba(0, 0, 0, 0.32);
      padding: 5px;
      border-radius: 14px;
      border: 1px solid rgba(255,255,255,0.06);
      margin-bottom: 16px;
    }
    .tab {
      border: none;
      background: transparent;
      color: var(--muted);
      font-weight: 700;
      font-size: 13px;
      padding: 10px 8px;
      border-radius: 10px;
      cursor: pointer;
      transition: all .16s ease;
    }
    .tab.active {
      background: rgba(255, 255, 255, 0.10);
      color: #fff;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
    }
    .pane { display: none; }
    .pane.active { display: block; }
    .field { margin-bottom: 12px; }
    .label {
      display: flex;
      justify-content: space-between;
      font-size: 12px;
      font-weight: 600;
      color: #cbd5e1;
      margin-bottom: 6px;
    }
    .label span.sub { color: var(--muted); font-weight: 500; }
    .input {
      width: 100%;
      padding: 13px 14px;
      border-radius: 13px;
      border: 1px solid rgba(255, 255, 255, 0.12);
      background: rgba(8, 11, 19, 0.72);
      color: #fff;
      font-size: 14.5px;
      outline: none;
      transition: border-color .15s ease, box-shadow .15s ease;
    }
    .input:focus {
      border-color: #60a5fa;
      box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
    }
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 9px;
      width: 100%;
      padding: 14px 16px;
      border-radius: 14px;
      font-weight: 700;
      font-size: 14.5px;
      text-decoration: none;
      border: none;
      cursor: pointer;
      transition: transform .12s ease, opacity .15s ease;
      margin-bottom: 10px;
    }
    .btn:active { transform: scale(0.985); }
    .btn:disabled { opacity: 0.55; cursor: wait; }
    .btn-primary {
      background: linear-gradient(135deg, #2563eb, #7c3aed);
      color: #fff;
      box-shadow: 0 10px 26px rgba(99, 102, 241, 0.35);
    }
    .btn-green {
      background: linear-gradient(135deg, #059669, #10b981);
      color: #fff;
      box-shadow: 0 10px 24px rgba(16, 185, 129, 0.28);
    }
    .btn-sec {
      background: rgba(255, 255, 255, 0.065);
      border: 1px solid rgba(255, 255, 255, 0.09);
      color: #e2e8f0;
      font-size: 13.5px;
      padding: 12px 14px;
    }
    .divider {
      display: flex;
      align-items: center;
      gap: 10px;
      margin: 14px 0;
      color: #64748b;
      font-size: 11.5px;
      text-transform: uppercase;
      letter-spacing: 0.6px;
      font-weight: 700;
    }
    .divider::before, .divider::after {
      content: "";
      flex: 1;
      height: 1px;
      background: rgba(255, 255, 255, 0.08);
    }
    .alert {
      display: none;
      padding: 12px 14px;
      border-radius: 13px;
      font-size: 13.5px;
      line-height: 1.45;
      margin-bottom: 12px;
      border: 1px solid transparent;
    }
    .alert.show { display: block; }
    .alert.ok { background: rgba(16, 185, 129, 0.13); border-color: rgba(52, 211, 153, 0.35); color: #a7f3d0; }
    .alert.err { background: rgba(239, 68, 68, 0.13); border-color: rgba(248, 113, 113, 0.35); color: #fecaca; }
    .steps {
      margin-top: 16px;
      background: var(--card-2);
      border: 1px solid rgba(255, 255, 255, 0.06);
      border-radius: 16px;
      padding: 14px 16px;
    }
    .steps-title {
      font-size: 12.5px;
      font-weight: 700;
      color: #cbd5e1;
      margin-bottom: 8px;
    }
    .step-item {
      font-size: 12.5px;
      color: var(--muted);
      line-height: 1.5;
      margin-bottom: 6px;
    }
    .step-item:last-child { margin-bottom: 0; }
    .step-item b { color: #e2e8f0; }
    code.inline {
      background: rgba(255,255,255,0.08);
      padding: 2px 6px;
      border-radius: 6px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px;
      color: #bae6fd;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div class="top-row">
        <div class="brand">
          <span class="brand-logo">⚡</span>
          <span>FullGram Beta</span>
        </div>
        <div class="pill ${statusClass}" id="statusPill">${escapeHtml(statusBadge)}</div>
      </div>

      <h1>${done ? "✅ Доступ успешно активирован!" : "Активация закрытого бета-теста"}</h1>
      <p class="lead">
        ${done
          ? "Ваш Telegram-аккаунт уже добавлен в белый список тестеров FullGram. Откройте приложение — доступ разблокируется автоматически."
          : "Активируйте бета-доступ для любого своего аккаунта прямо на сайте по коду и Telegram ID или в 1 клик через бота."}
      </p>

      <div class="tabs">
        <button class="tab active" type="button" data-pane="activatePane">🎟 Активация по коду</button>
        <button class="tab" type="button" data-pane="checkPane">🔍 Проверить доступ</button>
      </div>

      <div id="resultBox" class="alert ${done ? "ok show" : ""}">${done ? "✅ Аккаунт активирован! Нажмите «Открыть FullGram и синхронизировать» ниже." : ""}</div>

      <div class="pane active" id="activatePane">
        ${botPrimaryBlock}
        ${botPrimaryBlock ? '<div class="divider">или активировать прямо на сайте</div>' : ""}

        <form id="redeemForm">
          <div class="field">
            <div class="label">
              <span>Код приглашения</span>
              <span class="sub">формат fgb1_...</span>
            </div>
            <input class="input" id="codeInput" name="code" type="text" placeholder="Например: fgb1_a1b2c3d4..." value="${safeCode}" autocomplete="off" spellcheck="false" />
          </div>
          <div class="field">
            <div class="label">
              <span>Ваш Telegram ID</span>
              <span class="sub" id="tgIdHint">узнать можно в боте (/start)</span>
            </div>
            <input class="input" id="peerIdInput" name="peerId" type="text" inputmode="numeric" placeholder="Например: 1234567890" autocomplete="off" />
          </div>
          <button class="btn btn-green" id="redeemSubmitBtn" type="submit">✨ Активировать бета-доступ на сайте</button>
        </form>

        <a class="btn btn-sec" id="openAppLink" href="${escapeHtml(done ? syncLink : deepLink)}">🚀 Открыть FullGram ${hasCode && !done ? "с этим кодом" : "и синхронизировать"}</a>
        ${hasCode ? `<button class="btn btn-sec" id="copyCodeBtn" type="button" data-code="${safeCode}">📋 Скопировать код приглашения</button>` : ""}
      </div>

      <div class="pane" id="checkPane">
        <form id="checkForm">
          <div class="field">
            <div class="label">
              <span>Telegram ID аккаунта</span>
              <span class="sub">числовой ID</span>
            </div>
            <input class="input" id="checkPeerInput" type="text" inputmode="numeric" placeholder="Введите ваш Telegram ID" autocomplete="off" />
          </div>
          <button class="btn btn-primary" id="checkSubmitBtn" type="submit">🔍 Проверить статус бета-доступа</button>
        </form>
        <div id="checkResultBox" class="alert"></div>
        <a class="btn btn-sec" href="fullgram://beta">🔄 Синхронизировать доступ в FullGram</a>
      </div>

      <div class="steps">
        <div class="steps-title">Как это работает на втором или любом другом аккаунте:</div>
        <div class="step-item">1. Нажмите <b>Активировать через Telegram</b> (или отправьте боту <code class="inline">fgb1_...</code> в ЛС) — либо введите свой <b>Telegram ID</b> и код прямо здесь на сайте.</div>
        <div class="step-item">2. Узнать свой числовой ID можно, просто написав <code class="inline">/start</code> нашему боту с нужного аккаунта.</div>
        <div class="step-item">3. Откройте <b>FullGram</b> под этим аккаунтом (или нажмите <b>Настройки → FullGram → Проверить доступ</b>).</div>
      </div>
    </div>
  </div>

  <script>
    (function() {
      var botUsername = ${JSON.stringify(botUsername)};
      var tabs = document.querySelectorAll(".tab");
      var panes = document.querySelectorAll(".pane");
      tabs.forEach(function(tab) {
        tab.addEventListener("click", function() {
          var target = tab.getAttribute("data-pane");
          tabs.forEach(function(t) { t.classList.toggle("active", t === tab); });
          panes.forEach(function(p) { p.classList.toggle("active", p.id === target); });
        });
      });

      var codeInput = document.getElementById("codeInput");
      var peerIdInput = document.getElementById("peerIdInput");
      var checkPeerInput = document.getElementById("checkPeerInput");
      var tgBotBtn = document.getElementById("tgBotBtn");
      var openAppLink = document.getElementById("openAppLink");
      var resultBox = document.getElementById("resultBox");
      var checkResultBox = document.getElementById("checkResultBox");
      var statusPill = document.getElementById("statusPill");

      try {
        var tg = window.Telegram && window.Telegram.WebApp;
        if (tg) {
          tg.ready();
          var u = tg.initDataUnsafe && tg.initDataUnsafe.user;
          if (u && u.id) {
            peerIdInput.value = String(u.id);
            checkPeerInput.value = String(u.id);
            var hint = document.getElementById("tgIdHint");
            if (hint) hint.textContent = "определён автоматически ✓";
          }
        }
      } catch (e) {}

      function extractCleanCode(raw) {
        var s = String(raw || "").trim();
        var mUrl = s.match(/\\/beta\\/([A-Za-z0-9_.-]+)/i);
        if (mUrl) return mUrl[1];
        var mStart = s.match(/[?&]start=(?:beta[_-])?([A-Za-z0-9_.-]+)/i);
        if (mStart) return mStart[1];
        if (s.toLowerCase().indexOf("beta_") === 0 || s.toLowerCase().indexOf("beta-") === 0) {
          return s.slice(5);
        }
        return s;
      }

      if (codeInput) {
        codeInput.addEventListener("input", function() {
          var c = extractCleanCode(codeInput.value);
          if (tgBotBtn && botUsername) {
            tgBotBtn.href = c
              ? ("https://t.me/" + encodeURIComponent(botUsername) + "?start=beta_" + encodeURIComponent(c))
              : ("https://t.me/" + encodeURIComponent(botUsername));
          }
          if (openAppLink) {
            openAppLink.href = c ? ("fullgram://beta?code=" + encodeURIComponent(c)) : "fullgram://beta";
          }
        });
      }

      function showAlert(el, ok, html) {
        if (!el) return;
        el.className = "alert show " + (ok ? "ok" : "err");
        el.innerHTML = html;
      }

      var redeemForm = document.getElementById("redeemForm");
      var redeemBtn = document.getElementById("redeemSubmitBtn");
      if (redeemForm) {
        redeemForm.addEventListener("submit", function(ev) {
          ev.preventDefault();
          var code = extractCleanCode(codeInput ? codeInput.value : "");
          var peerId = String(peerIdInput ? peerIdInput.value : "").trim().replace(/[^0-9-]/g, "");
          if (!code) {
            showAlert(resultBox, false, "❌ Введите код приглашения (например, <b>fgb1_...</b>).");
            return;
          }
          if (!peerId || !/^-?\\d{4,20}$/.test(peerId)) {
            showAlert(resultBox, false, "❌ Введите ваш числовой <b>Telegram ID</b> (напишите /start боту, чтобы узнать его).");
            return;
          }
          redeemBtn.disabled = true;
          var prevText = redeemBtn.textContent;
          redeemBtn.textContent = "⏳ Активируем...";
          var initData = (window.Telegram && window.Telegram.WebApp && window.Telegram.WebApp.initData) || "";
          fetch("/beta/web-activate", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ code: code, peerId: peerId, initData: initData })
          })
            .then(function(r) { return r.json(); })
            .then(function(data) {
              redeemBtn.disabled = false;
              redeemBtn.textContent = prevText;
              if (data && data.ok) {
                showAlert(
                  resultBox,
                  true,
                  "✅ <b>Бета-доступ активирован для ID " + data.peerId + "!</b><br>Теперь откройте FullGram под этим аккаунтом — функции разблокируются автоматически."
                );
                if (statusPill) {
                  statusPill.className = "pill ok";
                  statusPill.textContent = "Бета-доступ активирован";
                }
                if (openAppLink) {
                  openAppLink.href = "fullgram://beta";
                  openAppLink.textContent = "🚀 Открыть FullGram и синхронизировать";
                }
              } else {
                showAlert(resultBox, false, "❌ " + ((data && data.error) || "Не удалось активировать код."));
              }
            })
            .catch(function() {
              redeemBtn.disabled = false;
              redeemBtn.textContent = prevText;
              showAlert(resultBox, false, "❌ Ошибка сети. Проверьте подключение и попробуйте снова.");
            });
        });
      }

      var checkForm = document.getElementById("checkForm");
      var checkBtn = document.getElementById("checkSubmitBtn");
      if (checkForm) {
        checkForm.addEventListener("submit", function(ev) {
          ev.preventDefault();
          var peerId = String(checkPeerInput ? checkPeerInput.value : "").trim().replace(/[^0-9-]/g, "");
          if (!peerId || !/^-?\\d{4,20}$/.test(peerId)) {
            showAlert(checkResultBox, false, "❌ Введите корректный числовой Telegram ID.");
            return;
          }
          checkBtn.disabled = true;
          checkBtn.textContent = "⏳ Проверяем...";
          fetch("/beta/public-status?peerId=" + encodeURIComponent(peerId))
            .then(function(r) { return r.json(); })
            .then(function(data) {
              checkBtn.disabled = false;
              checkBtn.textContent = "🔍 Проверить статус бета-доступа";
              if (data && data.active) {
                showAlert(checkResultBox, true, "✅ <b>Доступ активен!</b> Аккаунт <b>" + data.peerId + "</b> состоит в закрытом бета-тесте FullGram.");
              } else {
                showAlert(checkResultBox, false, "ℹ️ Для аккаунта <b>" + peerId + "</b> бета-доступ ещё не активирован. Перейдите на вкладку «Активация по коду».");
              }
            })
            .catch(function() {
              checkBtn.disabled = false;
              checkBtn.textContent = "🔍 Проверить статус бета-доступа";
              showAlert(checkResultBox, false, "❌ Не удалось проверить статус.");
            });
        });
      }

      var copyBtn = document.getElementById("copyCodeBtn");
      if (copyBtn) {
        copyBtn.addEventListener("click", function() {
          var code = (codeInput && codeInput.value.trim()) || copyBtn.getAttribute("data-code") || "";
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(code).then(function() {
              copyBtn.textContent = "✅ Код скопирован";
            });
          }
        });
      }
    })();
  </script>
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

  // Allow any user in private chat ONLY to:
  // 1) redeem a beta invite via /start beta_<CODE>, /activate <CODE>, or sending fgb1_... / /beta/<CODE>
  // 2) tap /start (without args) on a non-owner account to see their Telegram ID and instructions to activate beta
  // 3) check their own beta status via callback beta_my_status
  // Management/admin commands and plugins remain 100% owner-locked!
  const isOwnerActor = Boolean(actorId && actorId === ownerId && isAdminUserId(actorId, env));

  if (!isOwnerActor && update.callback_query?.id && update.callback_query?.data === "beta_my_status") {
    const cq = update.callback_query;
    const cqChatType = cq.message?.chat?.type || "";
    if (cqChatType === "private" && cq.from?.id != null) {
      const checkId = normalizePeerId(String(cq.from.id));
      const usersData = await loadBetaUsers(env);
      const rec = usersData.users[checkId];
      const active = Boolean(rec && !rec.revoked);
      await answerTelegramCallback(
        env,
        cq.id,
        active ? "✅ Бета-доступ активен!" : "ℹ️ Бета-доступ ещё не активирован."
      );
      await sendTelegramMessage(
        env,
        cq.message.chat.id,
        active
          ? `✅ <b>Бета-доступ активен!</b>\n\nВаш Telegram ID: <code>${escapeHtml(checkId)}</code>\nОткройте FullGram — все функции разблокированы.`
          : `ℹ️ <b>Бета-доступ пока не активирован</b>\n\nВаш Telegram ID: <code>${escapeHtml(checkId)}</code>\nОтправьте сюда код приглашения (например, <code>fgb1_...</code>) или активируйте доступ на сайте:`,
        {
          parse_mode: "HTML",
          reply_markup: {
            inline_keyboard: [[{ text: "🌐 Сайт бета-активации", url: `${origin}/beta` }]]
          }
        }
      );
      return jsonResponse({ ok: true });
    }
  }

  const preMsg = update.message;
  if (preMsg?.from?.id != null && preMsg.chat?.type === "private" && typeof preMsg.text === "string") {
    const preText = preMsg.text.trim();
    const preSenderId = normalizePeerId(String(preMsg.from.id).trim());
    const extractedBetaCode = extractBetaInviteCodeFromText(preText);
    const isExplicitBetaRedeem = Boolean(
      extractedBetaCode && (
        preText.toLowerCase().includes("beta") ||
        extractedBetaCode.toLowerCase().startsWith("fgb1_") ||
        /^\/activate\b/i.test(preText) ||
        (!isOwnerActor && !preText.startsWith("/"))
      )
    );
    if (isExplicitBetaRedeem) {
      const result = await redeemBetaInvite(env, extractedBetaCode, preSenderId, {
        via: "bot",
        username: preMsg.from?.username || ""
      });
      if (result.ok) {
        await sendTelegramMessage(
          env,
          preMsg.chat.id,
          `✅ <b>Бета-доступ FullGram активирован!</b>\n\n` +
          `Ваш Telegram ID: <code>${escapeHtml(preSenderId)}</code>\n` +
          `Теперь просто откройте приложение FullGram — все функции откроются автоматически.\n\n` +
          `Если FullGram уже открыт, зайдите в <b>Настройки → FullGram → Проверить доступ</b>.`,
          {
            parse_mode: "HTML",
            reply_markup: {
              inline_keyboard: [[{ text: "🚀 Открыть портал FullGram", url: `${origin}/beta/${encodeURIComponent(result.code)}?done=1` }]]
            }
          }
        );
      } else {
        await sendTelegramMessage(
          env,
          preMsg.chat.id,
          `❌ ${escapeHtml(result.error)}\n\nВаш Telegram ID: <code>${escapeHtml(preSenderId)}</code>`,
          {
            parse_mode: "HTML",
            reply_markup: {
              inline_keyboard: [[{ text: "🌐 Открыть сайт активации", url: `${origin}/beta` }]]
            }
          }
        );
      }
      return jsonResponse({ ok: true });
    }

    if (!isOwnerActor && (/^\/start(?:@\S+)?$/i.test(preText) || /^\/help(?:@\S+)?$/i.test(preText))) {
      const usersData = await loadBetaUsers(env);
      const rec = usersData.users[preSenderId];
      const active = Boolean(rec && !rec.revoked);
      await sendTelegramMessage(
        env,
        preMsg.chat.id,
        `🔐 <b>Активация закрытого бета-теста FullGram</b>\n\n` +
        `Ваш Telegram ID: <code>${escapeHtml(preSenderId)}</code>\n` +
        `Статус: ${active ? "✅ <b>Бета-доступ активен</b>" : "⏳ <b>Ожидает активации</b>"}\n\n` +
        `Чтобы активировать доступ на этом аккаунте:\n` +
        `• Отправьте сюда ваш код приглашения (<code>fgb1_...</code>) или ссылку инвайта;\n` +
        `• Либо активируйте доступ через веб-портал по кнопке ниже.\n\n` +
        `<i>Панель управления ботом доступна исключительно владельцу FullGram.</i>`,
        {
          parse_mode: "HTML",
          reply_markup: {
            inline_keyboard: [
              [{ text: "🌐 Открыть сайт бета-активации", url: `${origin}/beta` }],
              [{ text: "🔍 Проверить мой статус", callback_data: "beta_my_status" }]
            ]
          }
        }
      );
      return jsonResponse({ ok: true });
    }
  }

  if (!isOwnerActor) {
    if (update.callback_query?.id) {
      await answerTelegramCallback(env, update.callback_query.id, "⛔ Управление ботом доступно только владельцу FullGram.");
    } else if (update.inline_query?.id) {
      // Ignore inline queries silently from non-owners
    } else {
      const msgObj = update.message || update.edited_message;
      if (msgObj?.chat?.id && msgObj?.chat?.type === "private") {
        const guestId = normalizePeerId(String(msgObj.from?.id || ""));
        await sendTelegramMessage(
          env,
          msgObj.chat.id,
          `⛔ Управление ботом доступно исключительно владельцу FullGram.\n\n` +
          `Для активации закрытого бета-теста отправьте код приглашения (<code>fgb1_...</code>) или откройте сайт активации.\n` +
          (guestId ? `Ваш Telegram ID: <code>${escapeHtml(guestId)}</code>` : ""),
          {
            parse_mode: "HTML",
            reply_markup: {
              inline_keyboard: [[{ text: "🌐 Открыть сайт активации", url: `${origin}/beta` }]]
            }
          }
        );
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
      const botUsername = await resolveBotUsername(env);
      const inv = await loadBetaInvites(env);
      inv.invites[code] = {
        maxUses,
        uses: 0,
        note: "button",
        botUsername: botUsername || undefined,
        createdAt: Math.floor(Date.now() / 1000),
        revoked: false
      };
      await saveBetaInvites(env, inv);
      await answerTelegramCallback(env, cq.id, `✅ Бета-ссылка (${maxUses}) создана`);
      const botLinkLine = botUsername
        ? `🤖 <b>Ссылка в 1 клик (работает везде):</b>\nhttps://t.me/${botUsername}?start=beta_${code}\n\n`
        : "";
      await sendTelegramMessage(
        env,
        cq.from.id,
        `🎟 <b>Ссылка для закрытого бета-теста FullGram</b>\n` +
        `Лимит активаций: <b>${maxUses}</b>\n\n` +
        botLinkLine +
        `🌐 <b>Веб-ссылка:</b>\n${origin}/beta/${code}\n\n` +
        `🔑 <b>Код для ручного ввода:</b>\n<code>${code}</code>`,
        {
          parse_mode: "HTML",
          disable_web_page_preview: true,
          reply_markup: {
            inline_keyboard: [
              [{ text: "🌐 Открыть веб-страницу", url: `${origin}/beta/${code}` }],
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
      "/beta_add <peerId> — выдать бета-доступ напрямую по ID\n" +
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
    if (betaCmd === "/beta_add") {
      const targetId = normalizePeerId((parts[1] || "").trim());
      if (!targetId || !/^-?\d{1,20}$/.test(targetId)) {
        await sendTelegramMessage(env, chatId, "Формат: /beta_add <peerId>");
        return jsonResponse({ ok: true });
      }
      const usersData = await loadBetaUsers(env);
      const now = Math.floor(Date.now() / 1000);
      usersData.users[targetId] = {
        ...(usersData.users[targetId] || {}),
        code: "owner_grant",
        via: "owner",
        activatedAt: usersData.users[targetId]?.activatedAt || now,
        updatedAt: now,
        revoked: false
      };
      await saveBetaUsers(env, usersData);
      await sendTelegramMessage(env, chatId, `✅ Бета-доступ выдан аккаунту <code>${escapeHtml(targetId)}</code>.`, { parse_mode: "HTML" });
      return jsonResponse({ ok: true });
    }
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
    const hasCount = parts.length > 1 && Number.isFinite(maxUsesRaw) && maxUsesRaw >= 1;
    const maxUses = hasCount ? Math.min(500, Math.floor(maxUsesRaw)) : 1;
    const note = (hasCount ? parts.slice(2) : parts.slice(1)).join(" ").trim().slice(0, 80);
    const rand = new Uint8Array(12);
    crypto.getRandomValues(rand);
    const code = `fgb1_${bytesToHex(rand)}`;
    const botUsername = await resolveBotUsername(env);
    const inv = await loadBetaInvites(env);
    inv.invites[code] = {
      maxUses,
      uses: 0,
      note,
      botUsername: botUsername || undefined,
      createdAt: Math.floor(Date.now() / 1000),
      revoked: false
    };
    await saveBetaInvites(env, inv);
    const botLinkLine = botUsername
      ? `🤖 <b>Ссылка в 1 клик (работает везде):</b>\nhttps://t.me/${botUsername}?start=beta_${code}\n\n`
      : "";
    await sendTelegramMessage(
      env,
      chatId,
      `🎟 <b>Ссылка для закрытого бета-теста FullGram</b>\n` +
      `Лимит активаций: <b>${maxUses}</b>${note ? `\nЗаметка: ${escapeHtml(note)}` : ""}\n\n` +
      botLinkLine +
      `🌐 <b>Веб-ссылка:</b>\n${origin}/beta/${code}\n\n` +
      `🔑 <b>Код для ручного ввода:</b>\n<code>${code}</code>`,
      {
        parse_mode: "HTML",
        disable_web_page_preview: true,
        reply_markup: {
          inline_keyboard: [
            [{ text: "🌐 Открыть веб-страницу", url: `${origin}/beta/${code}` }],
            [{ text: "🗑 Отозвать эту ссылку", callback_data: `beta_revoke:${code}` }]
          ]
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
      const cacheKey = new Request(`${origin}/assets/frames/${fileName}?fmt=rgba2`, { method: "GET" });
      const cachedResp = await cache.match(cacheKey);
      if (cachedResp) {
        return cachedResp;
      }
      const sources = [
        `https://raw.githubusercontent.com/shermanko/FullGram/release/next/assets/frames/${fileName}`,
        `https://cdn.jsdelivr.net/gh/shermanko/FullGram@release/next/assets/frames/${fileName}`
      ];
      for (const srcUrl of sources) {
        try {
          const upstream = await fetch(srcUrl, { cf: { cacheTtl: 3600, cacheEverything: true } });
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
            ctx.waitUntil(cache.put(cacheKey, resp.clone()));
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

    if (request.method === "GET" && path === "/beta/public-status") {
      const peerId = normalizePeerId(url.searchParams.get("peerId") || "");
      if (!peerId || !/^-?\d{4,20}$/.test(peerId)) {
        return jsonResponse({ ok: false, active: false, error: "Некорректный Telegram ID" }, 400);
      }
      if (isAdminUserId(peerId, env)) {
        return jsonResponse({ ok: true, active: true, peerId });
      }
      const usersData = await loadBetaUsers(env);
      const userRec = usersData.users[peerId];
      return jsonResponse({ ok: true, active: Boolean(userRec && !userRec.revoked), peerId });
    }

    if (request.method === "POST" && path === "/beta/web-activate") {
      try {
        const body = await request.json();
        const rawCode = extractBetaInviteCodeFromText(body.code || "") || String(body.code || "").trim();
        let peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
        let verifiedUsername = "";
        if (typeof body.initData === "string" && body.initData.trim() && env.TG_BOT_TOKEN) {
          const verified = await verifyTelegramInitData(body.initData.trim(), env.TG_BOT_TOKEN);
          if (verified?.user?.id != null) {
            peerId = normalizePeerId(String(verified.user.id));
            verifiedUsername = String(verified.user.username || "");
          }
        }
        if (!rawCode || !peerId || !/^-?\d{4,20}$/.test(peerId)) {
          return jsonResponse({ ok: false, error: "Укажите корректный код приглашения и числовой Telegram ID." }, 400);
        }
        const result = await redeemBetaInvite(env, rawCode, peerId, {
          via: "web",
          username: verifiedUsername
        });
        if (!result.ok) {
          return jsonResponse({ ok: false, error: result.error }, result.status || 403);
        }
        return jsonResponse({
          ok: true,
          active: true,
          peerId: result.peerId,
          code: result.code,
          remaining: result.remaining
        });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "GET" && (path.startsWith("/beta/") || path === "/beta")) {
      const rawCode = path.startsWith("/beta/") ? path.slice("/beta/".length) : (url.searchParams.get("code") || "");
      const code = rawCode.trim().replace(/[^a-zA-Z0-9_.-]/g, "");
      const done = url.searchParams.get("done") === "1";
      let statusInfo = null;
      let entry = null;
      if (code) {
        const inv = await loadBetaInvites(env);
        entry = inv.invites && inv.invites[code] ? inv.invites[code] : null;
        const now = Math.floor(Date.now() / 1000);
        const maxUses = entry ? (entry.maxUses || 1) : 0;
        const uses = entry ? (entry.uses || 0) : 0;
        statusInfo = {
          exists: Boolean(entry),
          revoked: Boolean(entry?.revoked),
          expired: Boolean(entry?.expiresAt && now > entry.expiresAt),
          exhausted: Boolean(entry && uses >= maxUses),
          maxUses,
          remaining: Math.max(0, maxUses - uses)
        };
      }
      let botUsername = String(entry?.botUsername || "").trim().replace(/^@/, "");
      if (!botUsername) {
        botUsername = await resolveBotUsername(env);
      }
      return new Response(renderBetaLandingHtml(code, origin, statusInfo, { botUsername, done }), {
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
        const deviceHash = await sha256Hex(deviceSecret);
        const result = await redeemBetaInvite(env, code, peerId, { deviceHash, via: "app" });
        if (!result.ok) {
          return jsonResponse({ ok: false, error: result.error }, result.status || 403);
        }
        const receipt = await issueBetaReceipt(peerId, deviceHash, result.code, env);
        return jsonResponse({ ok: true, active: true, peerId, receipt });
      } catch (err) {
        return jsonResponse({ ok: false, error: err.message }, 400);
      }
    }

    if (request.method === "POST" && (path === "/beta/check" || path === "/beta/status")) {
      try {
        const body = await request.json();
        const peerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : "");
        const deviceSecret = String(body.deviceSecret || "").trim();
        if (!peerId || !/^-?\d{1,20}$/.test(peerId) || deviceSecret.length < 16) {
          return jsonResponse({ ok: true, active: false });
        }
        const deviceHash = await sha256Hex(deviceSecret);
        if (isAdminUserId(peerId, env)) {
          let receipt = "";
          try {
            receipt = await issueBetaReceipt(peerId, deviceHash, "owner", env);
          } catch {}
          return jsonResponse({ ok: true, active: true, peerId, isOwner: true, receipt });
        }
        const usersData = await loadBetaUsers(env);
        const userRec = usersData.users[peerId];
        if (!userRec || userRec.revoked) {
          return jsonResponse({ ok: true, active: false });
        }
        if (!userRec.deviceHash) {
          userRec.deviceHash = deviceHash;
          usersData.users[peerId] = userRec;
          await saveBetaUsers(env, usersData);
        }
        let receipt = typeof body.receipt === "string" ? body.receipt.trim() : "";
        const existingVerified = receipt ? await verifyBetaReceipt(receipt, env) : null;
        if (!existingVerified || existingVerified.uid !== peerId || !timingSafeEqual(existingVerified.dh, deviceHash)) {
          receipt = await issueBetaReceipt(peerId, deviceHash, userRec.code || "beta", env);
        }
        return jsonResponse({ ok: true, active: true, peerId, receipt });
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

    if (request.method === "POST" && path === "/economy/action") {
      const auth = await authenticateRequest(request, env);
      if (!auth) {
        return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
      }
      try {
        const body = await request.json();
        const selfPeerId = normalizePeerId(String(auth.uid));
        const targetPeerId = normalizePeerId(body.peerId != null ? String(body.peerId).trim() : selfPeerId);
        const sponsorTier = auth.isAdmin ? "plus" : (await getSponsorTier(env, auth.uid));
        const canManageAny = Boolean(auth.isAdmin || sponsorTier === "plus");
        if (!canManageAny && targetPeerId !== selfPeerId) {
          return jsonResponse({ ok: false, error: "Forbidden: can only manage your own economy items" }, 403);
        }
        const act = String(body.action || "").trim().toLowerCase();
        const selfAllowedActions = new Set([
          "revoke_username",
          "revoke_number",
          "toggle_username",
          "toggle_number",
          "transfer_username",
          "transfer_number",
          "transfer_gram",
          "transfer_stars"
        ]);
        if (!canManageAny && !selfAllowedActions.has(act)) {
          return jsonResponse({ ok: false, error: "Forbidden: Sponsor+ required to mint server economy items" }, 403);
        }
        const result = await applyEconomyChange(env, { ...body, peerId: targetPeerId }, auth.uid);
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
