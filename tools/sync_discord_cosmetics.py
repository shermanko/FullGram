#!/usr/bin/env python3
"""
Sync full Discord cosmetics catalog (Avatar Decorations + Profile Effects)
from public open-source archives into assets/discord_cosmetics.json.
"""

import json
import os
import re
import subprocess
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(ROOT, "assets", "discord_cosmetics.json")

JULES_CDN = "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/"
DISCORD_AVATAR_CDN = "https://cdn.discordapp.com/avatar-decoration-presets/"


def slugify(text: str) -> str:
    s = re.sub(r"[^a-zA-Z0-9]+", "_", text.strip().lower()).strip("_")
    return s or "item"


def fetch_json_url(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "FullGram-Sync/1.0"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def gh_api_json(endpoint: str):
    out = subprocess.check_output(["gh", "api", endpoint], text=True, encoding="utf-8")
    return json.loads(out)


def encode_path(path: str) -> str:
    return "/".join(urllib.parse.quote(seg, safe="") for seg in path.split("/"))


def guess_category(title: str) -> str:
    low = title.lower()
    if any(k in low for k in ["cyber", "glitch", "neon", "tech", "pixel", "arcade", "sci", "bot", "holo", "synth", "chroma", "laser", "plasma", "circuit", "futuristic", "disxcore"]):
        return "Кибер"
    if any(k in low for k in ["anime", "sakura", "katana", "ki ", "aura", "manga", "spirit", "oni", "kitsune", "dragon", "samurai", "akuma", "shonen", "miku", "chibi"]):
        return "Аниме"
    if any(k in low for k in ["cat", "dog", "bunny", "bear", "duck", "frog", "fox", "pet", "kitty", "puppy", "cute", "kawaii", "cozy", "heart", "love", "angel", "plush", "mushroom", "fungi"]):
        return "Милые"
    if any(k in low for k in ["fire", "flame", "lightning", "storm", "ice", "frost", "snow", "water", "wave", "wind", "air", "earth", "lava", "smoke", "shadow", "dark", "blood", "skull", "blade"]):
        return "Стихия"
    if any(k in low for k in ["star", "moon", "sun", "galaxy", "space", "cosmic", "aurora", "nebula", "ufo", "planet", "zodiac", "aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpio", "sagittarius", "capricorn", "aquarius", "pisces"]):
        return "Космос"
    if any(k in low for k in ["flower", "rose", "leaf", "autumn", "spring", "butterfly", "butterflies", "forest", "garden", "bloom", "petal", "clover", "tree", "vine"]):
        return "Природа"
    if any(k in low for k in ["valorant", "league", "arcane", "street fighter", "palworld", "star wars", "marvel", "avatar", "spongebob", "fortnite", "minecraft", "jinx", "vi ", "ahri", "dungeons"]):
        return "Игры"
    return "Discord"


def main():
    print("Fetching JulesZYTB/discord-collectibles-downloader tree...")
    tree = gh_api_json("repos/JulesZYTB/discord-collectibles-downloader/git/trees/main?recursive=1")
    paths = [x["path"] for x in tree.get("tree", []) if x.get("type") == "blob"]

    frames_by_id = {}
    effects_map = {}

    # 1. Parse Avatar_Decorations (prefer Animated APNG)
    anim_dec = {}
    static_dec = {}
    for p in paths:
        if not p.startswith("discord_collectibles/Avatar_Decorations/"):
            continue
        parts = p.split("/")
        if len(parts) < 5:
            continue
        title = parts[2].strip()
        kind = parts[3]
        fname = parts[4]
        if not fname.lower().endswith(".png"):
            continue
        if kind == "Animated":
            anim_dec[title] = p
        elif kind == "Static":
            static_dec[title] = p

    all_dec_titles = sorted(set(anim_dec.keys()) | set(static_dec.keys()), key=lambda s: s.lower())
    for title in all_dec_titles:
        p = anim_dec.get(title) or static_dec.get(title)
        fname = p.split("/")[-1]
        m = re.search(r"(a_[0-9a-f]{20,40})\.png$", fname, re.I)
        urls = []
        if m:
            asset_hash = m.group(1)
            urls.append(f"{DISCORD_AVATAR_CDN}{asset_hash}.png?size=240&passthrough=true")
        urls.append(JULES_CDN + encode_path(p))

        fid = "dc_" + slugify(title)
        if fid in frames_by_id:
            fid = f"{fid}_{len(frames_by_id)}"
        frames_by_id[fid] = {
            "id": fid,
            "title": title,
            "category": guess_category(title),
            "urls": urls,
        }

    # 2. Merge wickstudio effects.json (official Discord CDN links not in Jules)
    try:
        wick = fetch_json_url("https://raw.githubusercontent.com/wickstudio/Discord-Avatar-Decoration-Bot/main/effects.json")
        existing_hashes = set()
        for f in frames_by_id.values():
            for u in f["urls"]:
                m = re.search(r"(a_[0-9a-f]{20,40})", u, re.I)
                if m:
                    existing_hashes.add(m.group(1).lower())
        added_wick = 0
        for item in wick:
            url = (item.get("url") or "").strip()
            label = (item.get("label") or "").strip()
            if not url or not label:
                continue
            m = re.search(r"(a_[0-9a-f]{20,40})", url, re.I)
            if m and m.group(1).lower() in existing_hashes:
                continue
            fid = "dc_" + slugify(label)
            if fid in frames_by_id:
                continue
            cat = "Флаги" if item.get("category") == "flags" else guess_category(label)
            frames_by_id[fid] = {
                "id": fid,
                "title": label,
                "category": cat,
                "urls": [url],
            }
            if m:
                existing_hashes.add(m.group(1).lower())
            added_wick += 1
        print(f"Merged +{added_wick} unique items from wickstudio")
    except Exception as e:
        print("Warning: wickstudio fetch failed:", e)

    # 3. Parse Profile_Effects (intro/loop APNG layers)
    for p in paths:
        if not p.startswith("discord_collectibles/Profile_Effects/"):
            continue
        parts = p.split("/")
        if len(parts) < 5:
            continue
        title = parts[2].strip()
        fname = parts[4]
        if not fname.lower().endswith(".png"):
            continue
        layer_match = re.search(r"_layer_(\d+)_", fname)
        layer_idx = int(layer_match.group(1)) if layer_match else 0
        effects_map.setdefault(title, []).append((layer_idx, JULES_CDN + encode_path(p)))

    profile_effects = []
    seen_eids = set()
    for title in sorted(effects_map.keys(), key=lambda s: s.lower()):
        layers = [u for _, u in sorted(effects_map[title], key=lambda x: x[0])]
        eid = "pe_" + slugify(title)
        if eid in seen_eids:
            eid = f"{eid}_{len(seen_eids)}"
        seen_eids.add(eid)
        profile_effects.append({
            "id": eid,
            "title": title,
            "category": guess_category(title),
            "layers": layers[:2],  # layer 0 (intro) + layer 1 (loop/ambient)
        })

    frames = sorted(frames_by_id.values(), key=lambda x: x["title"].lower())
    payload = {
        "version": 1,
        "framesCount": len(frames),
        "effectsCount": len(profile_effects),
        "frames": frames,
        "profileEffects": profile_effects,
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    size_kb = os.path.getsize(OUT_PATH) / 1024.0
    print(f"Wrote {OUT_PATH} ({size_kb:.1f} KB): {len(frames)} avatar frames, {len(profile_effects)} profile effects.")


if __name__ == "__main__":
    main()
