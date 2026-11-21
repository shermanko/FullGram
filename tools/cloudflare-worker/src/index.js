const DEFAULT_OWNER_ID = "8899688273";
const MAX_SCRIPT_BYTES = 256 * 1024;

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
      name: "Parimatch · Beton Казино (.casino / .zeus / .crash)",
      language: "lua",
      version: "5.1",
      author: "FullGram",
      description: "Полноэкранный HD графический GUI (Gates of Olympus, Aviator Live, 3D Рулетка, Beton Mines 5x5) на 60fps Canvas. Без спама в чат!",
      code: `-- @name Parimatch · Beton Казино (.casino / .zeus / .crash)
-- @id fg_casino
-- @version 5.1
-- @author FullGram
-- @description Полноэкранный HD графический GUI (Gates of Olympus, Aviator Live, 3D Рулетка, Beton Mines 5x5) на 60fps Canvas. Без спама в чат!

function get_num(key, def)
    local v = tonumber(fullgram.storage_get(key, def))
    if v == nil then return def end
    return v
end

function get_balance()
    return math.max(0, math.floor(get_num("balance", 1000) + 0.5))
end

function set_balance(val)
    local b = math.max(0, math.floor((tonumber(val) or 0) + 0.5))
    fullgram.storage_set("balance", b)
    local best = get_num("best_balance", 1000)
    if b > best then
        fullgram.storage_set("best_balance", b)
    end
    return b
end

function fmt2(x)
    local n = math.floor((tonumber(x) or 0) * 100 + 0.5)
    local whole = math.floor(n / 100)
    local frac = n % 100
    local fstr = (frac < 10) and ("0" .. tostring(frac)) or tostring(frac)
    return tostring(whole) .. "." .. fstr
end

function fmt_signed(delta)
    if delta >= 0 then
        return "+" .. tostring(delta)
    end
    return tostring(delta)
end

function add_session(wagered, returned, won)
    fullgram.storage_set("sess_rounds", get_num("sess_rounds", 0) + 1)
    fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + wagered)
    fullgram.storage_set("sess_returned", get_num("sess_returned", 0) + returned)
    if won then
        fullgram.storage_set("sess_wins", get_num("sess_wins", 0) + 1)
    end
end

function pick_weighted(tbl)
    local total = 0
    for i = 1, #tbl do
        total = total + tbl[i][2]
    end
    if total <= 0 then return tbl[1][1] end
    local roll = math.random(0, total - 1)
    for i = 1, #tbl do
        local w = tbl[i][2]
        if roll < w then
            return tbl[i][1]
        end
        roll = roll - w
    end
    return tbl[1][1]
end

function pick_zeus_orb()
    local roll = math.random(0, 999)
    if roll < 480 then return 2 end
    if roll < 720 then return 3 end
    if roll < 860 then return 5 end
    if roll < 940 then return 10 end
    if roll < 980 then return 25 end
    if roll < 995 then return 50 end
    return 100
end

function is_red_pocket(num)
    local reds = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}
    for i = 1, #reds do
        if reds[i] == num then return true end
    end
    return false
end

function parse_bet(raw_str, bal)
    local num = tonumber(string.match(tostring(raw_str or ""), "(%d+)"))
    local bet = num or 100
    if bet < 10 then bet = 10 end
    if bal > 0 and bet > bal then bet = bal end
    return math.floor(bet + 0.5)
end

function ensure_playable_balance()
    local bal = get_balance()
    if bal < 10 then
        bal = set_balance(500)
        return bal, true
    end
    return bal, false
end

function status_header()
    local bal = get_balance()
    local best = math.floor(get_num("best_balance", 1000) + 0.5)
    local ante = (get_num("ante_bet", 0) == 1)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)
    local rounds = math.floor(get_num("sess_rounds", 0) + 0.5)
    local wins = math.floor(get_num("sess_wins", 0) + 0.5)
    local wag = get_num("sess_wagered", 0)
    local ret = get_num("sess_returned", 0)
    local win_pct = (rounds > 0) and fmt2((wins / rounds) * 100) or "0.00"
    local sess_rtp = (wag > 0) and fmt2((ret / wag) * 100) or "—"
    local line = "💰 Баланс: " .. tostring(bal) .. " 🪙 | 🏆 Рекорд: " .. tostring(best) .. " 🪙"
    line = line .. "\\n⚡ Ante Bet (+25%): " .. (ante and "ВКЛ" or "ВЫКЛ")
    if fs > 0 then
        line = line .. " | 🎁 FS: " .. tostring(fs) .. " (x" .. tostring(gmult) .. ")"
    end
    line = line .. "\\n📊 Сессия: " .. tostring(rounds) .. " раунд. · Побед " .. win_pct .. "% · RTP " .. sess_rtp .. "%"
    return line
end

function play_zeus(raw_arg)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local is_fs = (fs > 0)
    local bal, refilled = ensure_playable_balance()
    local ante = (get_num("ante_bet", 0) == 1)
    local base_bet = is_fs and math.floor(get_num("bonus_bet", 100) + 0.5) or parse_bet(raw_arg, bal)
    local spin_cost = is_fs and 0 or math.min(bal, ante and math.floor(base_bet * 1.25 + 0.5) or base_bet)

    local weights = (ante or is_fs)
        and {{"💎", 26}, {"⏳", 21}, {"🏆", 17}, {"💍", 14}, {"👑", 10}, {"⚡", 12}}
        or  {{"💎", 30}, {"⏳", 23}, {"🏆", 18}, {"💍", 14}, {"👑", 9},  {"⚡", 6}}

    if not is_fs then
        bal = set_balance(bal - spin_cost)
    else
        fs = fs - 1
        fullgram.storage_set("free_spins", fs)
    end

    local grid = {}
    local counts = {}
    for i = 1, 15 do
        local s = pick_weighted(weights)
        grid[i] = s
        counts[s] = (counts[s] or 0) + 1
    end

    local bolts = counts["⚡"] or 0
    local sym_base = { ["💎"] = 0.4, ["⏳"] = 0.6, ["🏆"] = 0.9, ["💍"] = 1.3, ["👑"] = 2.2 }
    local syms = {"💎", "⏳", "🏆", "💍", "👑"}
    local best_pay = 0.0
    local best_sym = nil
    for i = 1, #syms do
        local s = syms[i]
        local cnt = counts[s] or 0
        if cnt >= 6 then
            local cand = sym_base[s] * (1.0 + (cnt - 6) * 0.65)
            if cand > best_pay then
                best_pay = cand
                best_sym = s
            end
        end
    end

    local mult = 0.0
    local status = "❌ Пустой спин"
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)

    if best_pay > 0.0 then
        local orb = (bolts > 0 or is_fs) and pick_zeus_orb() or 1
        if is_fs and orb > 1 then
            gmult = gmult + orb
            fullgram.storage_set("bonus_mult", gmult)
        end
        local eff_orb = is_fs and math.max(1, gmult) or orb
        mult = best_pay * eff_orb
        if eff_orb >= 25 then
            status = "🔥 MAX ОРБ ЗЕВСА x" .. tostring(eff_orb) .. "!"
        elseif eff_orb > 1 then
            status = "⚡ МОЛНИЯ ЗЕВСА x" .. tostring(eff_orb) .. "!"
        else
            status = "👑 СЫГРОВКА " .. best_sym .. " x" .. fmt2(mult) .. "!"
        end
    end

    if bolts >= 4 and not is_fs then
        fullgram.storage_set("bonus_bet", base_bet)
        fullgram.storage_set("free_spins", fs + 10)
        fullgram.storage_set("bonus_mult", 1)
        if mult < 3.0 then mult = 3.0 end
        status = "⚡ 4+ SCATTER! БОНУС 10 ФРИСПИНОВ!"
    elseif bolts >= 4 and is_fs then
        fullgram.storage_set("free_spins", fs + 5)
        status = "⚡ РЕТРИГГЕР +5 ФРИСПИНОВ!"
    end

    local payout = math.floor(base_bet * mult + 0.5)
    bal = set_balance(bal + payout)
    add_session(spin_cost, payout, payout > spin_cost)
    local net = payout - spin_cost

    local r1 = grid[1] .. " " .. grid[2] .. " " .. grid[3] .. " " .. grid[4] .. " " .. grid[5]
    local r2 = grid[6] .. " " .. grid[7] .. " " .. grid[8] .. " " .. grid[9] .. " " .. grid[10]
    local r3 = grid[11] .. " " .. grid[12] .. " " .. grid[13] .. " " .. grid[14] .. " " .. grid[15]
    local fs_left = math.floor(get_num("free_spins", 0) + 0.5)
    local tag = is_fs and ("🎁 ФРИСПИН (ост. " .. tostring(fs_left) .. ")") or ("Ставка: " .. tostring(spin_cost) .. " 🪙")
    local note = refilled and "\\n🎁 Фрибет +500 🪙 на старте" or ""

    return "⚡ GATES OF OLYMPUS (RTP 96.50%) | " .. tag .. "\\n"
        .. r1 .. "\\n" .. r2 .. "\\n" .. r3 .. "\\n"
        .. status .. " (выплата " .. tostring(payout) .. " 🪙, " .. fmt_signed(net) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_dogs(raw_arg)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local is_fs = (fs > 0)
    local bal, refilled = ensure_playable_balance()
    local ante = (get_num("ante_bet", 0) == 1)
    local base_bet = is_fs and math.floor(get_num("bonus_bet", 100) + 0.5) or parse_bet(raw_arg, bal)
    local spin_cost = is_fs and 0 or math.min(bal, ante and math.floor(base_bet * 1.25 + 0.5) or base_bet)

    local weights = (ante or is_fs)
        and {{"🦴", 23}, {"🐾", 20}, {"🎾", 17}, {"💎", 14}, {"🐶", 11}, {"🏠", 15}}
        or  {{"🦴", 27}, {"🐾", 22}, {"🎾", 18}, {"💎", 14}, {"🐶", 11}, {"🏠", 8}}

    if not is_fs then
        bal = set_balance(bal - spin_cost)
    else
        fs = fs - 1
        fullgram.storage_set("free_spins", fs)
    end

    local grid = {}
    local kennels = 0
    local dogs_cnt = 0
    for i = 1, 15 do
        local s = pick_weighted(weights)
        grid[i] = s
        if s == "🏠" then kennels = kennels + 1 end
        if s == "🐶" then dogs_cnt = dogs_cnt + 1 end
    end

    local line_w = { ["🦴"] = 0.4, ["🐾"] = 0.6, ["🎾"] = 0.85, ["💎"] = 1.4, ["🐶"] = 2.4 }
    local line_sum = 0.0
    for r = 0, 2 do
        local anchor = "🐶"
        for c = 1, 5 do
            local sym = grid[r * 5 + c]
            if sym ~= "🏠" then
                anchor = sym
                break
            end
        end
        local streak = 0
        for c = 1, 5 do
            local sym = grid[r * 5 + c]
            if sym == anchor or sym == "🏠" then
                streak = streak + 1
            else
                break
            end
        end
        if streak >= 3 then
            line_sum = line_sum + (line_w[anchor] or 0.6) * (streak - 1)
        end
    end

    local mult = 0.0
    local status = "❌ Пустой спин"
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)

    if line_sum > 0.0 then
        local km = 1
        if kennels > 0 then
            local sum_w = 0
            local cap = math.min(kennels, 4)
            for i = 1, cap do
                sum_w = sum_w + ((math.random(0, 9) < 7) and 2 or 3)
            end
            km = math.max(1, sum_w)
        end
        if is_fs and kennels > 0 then
            gmult = math.min(27, gmult + km)
            fullgram.storage_set("bonus_mult", gmult)
            km = gmult
        end
        mult = line_sum * km
        status = (km > 1) and ("🐶 БУДКИ x" .. tostring(km) .. " · ЗАНОС!") or "🐶 ЛИНИЯ СЫГРАЛА!"
    elseif dogs_cnt >= 5 then
        mult = 2.5
        status = "🐶 СТАЯ СОБАК x2.5!"
    end

    if kennels >= 4 and not is_fs then
        fullgram.storage_set("bonus_bet", base_bet)
        fullgram.storage_set("free_spins", fs + 10)
        fullgram.storage_set("bonus_mult", 1)
        if mult < 2.0 then mult = 2.0 end
        status = "🏠 БОНУС 10 ФРИСПИНОВ СОБАК!"
    elseif kennels >= 4 and is_fs then
        fullgram.storage_set("free_spins", fs + 5)
        status = "🏠 РЕТРИГГЕР +5 ФРИСПИНОВ!"
    end

    local payout = math.floor(base_bet * mult + 0.5)
    bal = set_balance(bal + payout)
    add_session(spin_cost, payout, payout > spin_cost)
    local net = payout - spin_cost

    local r1 = grid[1] .. " " .. grid[2] .. " " .. grid[3] .. " " .. grid[4] .. " " .. grid[5]
    local r2 = grid[6] .. " " .. grid[7] .. " " .. grid[8] .. " " .. grid[9] .. " " .. grid[10]
    local r3 = grid[11] .. " " .. grid[12] .. " " .. grid[13] .. " " .. grid[14] .. " " .. grid[15]
    local fs_left = math.floor(get_num("free_spins", 0) + 0.5)
    local tag = is_fs and ("🎁 ФРИСПИН (ост. " .. tostring(fs_left) .. ")") or ("Ставка: " .. tostring(spin_cost) .. " 🪙")
    local note = refilled and "\\n🎁 Фрибет +500 🪙 на старте" or ""

    return "🐶 THE DOG HOUSE (RTP 96.51%) | " .. tag .. "\\n"
        .. r1 .. "\\n" .. r2 .. "\\n" .. r3 .. "\\n"
        .. status .. " (выплата " .. tostring(payout) .. " 🪙, " .. fmt_signed(net) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_classic(raw_arg)
    local bal, refilled = ensure_playable_balance()
    local bet = parse_bet(raw_arg, bal)
    local weights = {{"🍒", 36}, {"🍋", 26}, {"🔔", 18}, {"💎", 13}, {"7️⃣", 7}}
    local s1 = pick_weighted(weights)
    local s2 = pick_weighted(weights)
    local s3 = pick_weighted(weights)

    local sevens = ((s1 == "7️⃣") and 1 or 0) + ((s2 == "7️⃣") and 1 or 0) + ((s3 == "7️⃣") and 1 or 0)
    local diamonds = ((s1 == "💎") and 1 or 0) + ((s2 == "💎") and 1 or 0) + ((s3 == "💎") and 1 or 0)

    local mult = 0.0
    local status = "❌ Мимо!"
    if s1 == s2 and s2 == s3 then
        if s1 == "7️⃣" then mult = 50.0; status = "🔥 МЕГА ДЖЕКПОТ 777 (x50)!"
        elseif s1 == "💎" then mult = 15.0; status = "💎 АЛМАЗНЫЙ ДЖЕКПОТ (x15)!"
        elseif s1 == "🔔" then mult = 8.0; status = "🔔 3 КОЛОКОЛА (x8)!"
        elseif s1 == "🍋" then mult = 5.0; status = "🍋 3 ЛИМОНА (x5)!"
        else mult = 3.0; status = "🍒 3 ВИШНИ (x3)!"
        end
    elseif sevens == 2 then
        mult = 3.0; status = "7️⃣ Две Семёрки (x3)!"
    elseif diamonds == 2 then
        mult = 2.0; status = "💎 Два Алмаза (x2)!"
    elseif s1 == s2 or s2 == s3 or s1 == s3 then
        mult = 1.2; status = "✨ Пара (x1.2)!"
    end

    local payout = math.floor(bet * mult + 0.5)
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, delta > 0)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""

    return "🎰 3 БАРАБАНА (RTP 96.20%) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. "┏━━━━━━━━━━━┓\\n┃  " .. s1 .. " │ " .. s2 .. " │ " .. s3 .. "  ┃\\n┗━━━━━━━━━━━┛\\n"
        .. status .. " (" .. fmt_signed(delta) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_crash(raw_arg, default_target)
    local bal, refilled = ensure_playable_balance()
    local s = tostring(raw_arg or "")
    local target = default_target or 2.0
    local bet = 100

    local n1 = string.match(s, "^%s*([%d%.]+)%s+%d+")
    local n2 = string.match(s, "^%s*[%d%.]+%s+(%d+)")
    if n1 and n2 then
        target = tonumber(n1) or target
        bet = tonumber(n2) or bet
    else
        local with_x = string.match(s, "([%d%.]+)[xXхХ]")
        if with_x then
            target = tonumber(with_x) or target
        else
            local single = tonumber(string.match(s, "([%d%.]+)"))
            if single then
                if string.find(s, ".", 1, true) then
                    target = single
                else
                    bet = single
                end
            end
        end
    end
    if target < 1.05 then target = 1.05 end
    if target > 100.0 then target = 100.0 end
    if bet < 10 then bet = 10 end
    if bet > bal then bet = bal end
    bet = math.floor(bet + 0.5)

    local crash_pt = 1.00
    if math.random(0, 99) >= 3 then
        local u = math.random(1, 990) / 1000.0
        crash_pt = math.min(100.0, math.max(1.03, 0.97 / (1.0 - u)))
    end

    local won = (crash_pt >= target)
    local payout = won and math.floor(bet * target + 0.5) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""

    local res_line = won
        and ("✅ Забрал на " .. fmt2(target) .. "x (краш был " .. fmt2(crash_pt) .. "x): +" .. tostring(delta) .. " 🪙")
        or  ("💥 КРАШ на " .. fmt2(crash_pt) .. "x (цель " .. fmt2(target) .. "x): " .. tostring(delta) .. " 🪙")

    return "🚀 CRASH (RTP 97.00% · 3% инста-краш) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. res_line .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_roulette(choice_arg, bet_arg)
    local bal, refilled = ensure_playable_balance()
    local c = string.lower(tostring(choice_arg or "red"))
    local bet = parse_bet(bet_arg, bal)
    local num = math.random(0, 36)

    local color = "black"
    local badge = "⚫️ Чёрное"
    if num == 0 then
        color = "green"
        badge = "🟢 Зеро (0)"
    elseif is_red_pocket(num) then
        color = "red"
        badge = "🔴 Красное"
    end

    local exact_num = tonumber(c)
    local won = false
    local mult = 2
    local bet_label = "🔴 Красное"
    if exact_num ~= nil and exact_num >= 0 and exact_num <= 36 then
        mult = 36
        bet_label = "🎯 Число [" .. tostring(exact_num) .. "]"
        won = (num == exact_num)
    elseif c == "green" or c == "0" or c == "зеро" or c == "зеленое" then
        mult = 36
        bet_label = "🟢 Зеро [0]"
        won = (color == "green")
    elseif c == "black" or c == "черное" or c == "ч" then
        mult = 2
        bet_label = "⚫️ Чёрное"
        won = (color == "black")
    else
        mult = 2
        bet_label = "🔴 Красное"
        won = (color == "red")
    end

    local payout = won and (bet * mult) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""
    local outcome = won
        and ("✅ Выигрыш x" .. tostring(mult) .. ": +" .. tostring(delta) .. " 🪙!")
        or  ("❌ Мимо: " .. tostring(delta) .. " 🪙")

    return "🎡 ЕВРОПЕЙСКАЯ РУЛЕТКА (RTP 97.30%) | " .. bet_label .. " · " .. tostring(bet) .. " 🪙\\n"
        .. "Выпало: " .. badge .. " [" .. tostring(num) .. "]\\n"
        .. outcome .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_coin(side_arg, bet_arg)
    local bal, refilled = ensure_playable_balance()
    local bet = parse_bet(bet_arg, bal)
    local pick_tails = (string.find(string.lower(tostring(side_arg or "")), "реш") ~= nil)
        or (string.find(string.lower(tostring(side_arg or "")), "tail") ~= nil)
    local won = (math.random(0, 99) < 49)
    local landed_tails = false
    if pick_tails then
        landed_tails = won
    else
        landed_tails = not won
    end
    local landed_str = landed_tails and "🪙 Решка" or "🦅 Орёл"

    local payout = won and (bet * 2) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""
    local res = won and ("✅ Победа (49% шанс, x2): +" .. tostring(delta) .. " 🪙!") or ("❌ Не угадали: " .. tostring(delta) .. " 🪙")

    return "🪙 МОНЕТКА (RTP 98.00%) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. "Выпал: " .. landed_str .. "\\n"
        .. res .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function rtp_summary()
    return "📊 ЧЕСТНЫЕ ШАНСЫ И RTP КАЗИНО:\\n"
        .. "• ⚡ Gates of Olympus — RTP 96.50% (орбы x2..x100, 4+ ⚡ = 10 FS)\\n"
        .. "• 🐶 The Dog House — RTP 96.51% (линии + будки Wild x2/x3, до x27 в FS)\\n"
        .. "• 🎰 3 Барабана — RTP 96.20% (777: x50, 💎: x15, 🔔: x8, пара: x1.2)\\n"
        .. "• 🚀 Crash — RTP 97.00% (3% краш на 1.00x, хвост до x100)\\n"
        .. "• 🎡 Рулетка (37 сект.) — RTP 97.30% (🔴/⚫️ 48.65% x2, 🟢 2.70% x36)\\n"
        .. "• 🪙 Монетка — RTP 98.00% (49.0% победа, x2)\\n"
        .. "ℹ️ Выдача баланса (.setbal <сумма>) НЕ меняет шансы.\\n\\n"
        .. status_header()
end

function handle_set_balance(raw)
    local s = tostring(raw or "")
    local add_num = tonumber(string.match(s, "^%s*%+%s*(%d+)"))
    if add_num ~= nil then
        local nb = set_balance(get_balance() + add_num)
        return "💰 Добавлено +" .. tostring(add_num) .. " 🪙!\\nБаланс: " .. tostring(nb) .. " 🪙 (шансы те же)"
    end
    local exact = tonumber(string.match(s, "(%d+)"))
    if exact ~= nil then
        local nb = set_balance(exact)
        return "💰 Баланс установлен: " .. tostring(nb) .. " 🪙\\n(шансы и RTP без изменений!)"
    end
    local nb = set_balance(get_balance() + 10000)
    return "🎁 Начислено +10000 🪙!\\nБаланс: " .. tostring(nb) .. " 🪙\\n(введите любое число в поле для точной выдачи)"
end

function open_casino_ui(game_id)
    local g = tostring(game_id or "lobby")
    fullgram.open_ui({
        kind = "webview",
        url = "https://fullgram.korsakovx.workers.dev/casino?game=" .. g,
        title = "PARIMATCH · BETON"
    })
end

function on_ui_event(ctx)
    local act = tostring(ctx.action or "")
    local inp = tostring(ctx.input or "")

    if act == "bonus" then
        local nb = set_balance(get_balance() + 1000)
        return { balance = nb, best_balance = get_num("best_balance", 1000), text = "🎁 +1000 🪙!\\n" .. status_header() }
    elseif act == "spin_zeus" then
        return play_zeus(inp)
    elseif act == "spin_dogs" then
        return play_dogs(inp)
    elseif act == "spin_classic" then
        return play_classic(inp)
    elseif act == "spin_crash" then
        return play_crash(inp, 2.0)
    elseif act == "spin_red" then
        return play_roulette("red", inp)
    elseif act == "spin_black" then
        return play_roulette("black", inp)
    elseif act == "spin_green" then
        return play_roulette("green", inp)
    elseif act == "spin_coin" then
        return play_coin("eagle", inp)
    elseif act == "toggle_ante" then
        if get_num("free_spins", 0) > 0 then
            return "⚠️ Нельзя менять Ante Bet во время фриспинов!\\n" .. status_header()
        end
        local cur = (get_num("ante_bet", 0) == 1) and 0 or 1
        fullgram.storage_set("ante_bet", cur)
        return (cur == 1 and "⚡ Ante Bet ВКЛ (+25% к ставке, x2 шанс бонуса)" or "⚡ Ante Bet ВЫКЛ") .. "\\n\\n" .. status_header()
    elseif act == "buy_bonus" then
        local bal = get_balance()
        local bet = parse_bet(inp, bal)
        local cost = bet * 100
        if bal < cost then
            return "❌ Нужно " .. tostring(cost) .. " 🪙 для покупки бонуса (x100 ставки).\\nВы можете выдать себе баланс кнопкой «💰 Выдать баланс»!\\n\\n" .. status_header()
        end
        set_balance(bal - cost)
        fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + cost)
        fullgram.storage_set("bonus_bet", bet)
        fullgram.storage_set("free_spins", get_num("free_spins", 0) + 10)
        fullgram.storage_set("bonus_mult", 1)
        return "🎁 БОНУС КУПЛЕН! 10 ФРИСПИНОВ по ставке " .. tostring(bet) .. " 🪙!\\nЖмите «⚡ Зевс» или «🐶 Собаки»!\\n\\n" .. status_header()
    elseif act == "set_balance" then
        return handle_set_balance(inp) .. "\\n\\n" .. status_header()
    elseif act == "rtp_info" then
        return rtp_summary()
    end

    return status_header()
end

function on_command(ctx)
    local aliases = { roul = "roulette", givebal = "setbal", balance = "bal", odds = "rtp" }
    local cmd = aliases[ctx.command] or ctx.command
    local args = tostring(ctx.args or "")

    if cmd == "casino" then
        open_casino_ui(args ~= "" and args or "lobby")
        return { cancel = true }
    elseif cmd == "zeus" then
        open_casino_ui("zeus")
        return { cancel = true }
    elseif cmd == "dogs" then
        open_casino_ui("zeus")
        return { cancel = true }
    elseif cmd == "slots" then
        open_casino_ui("zeus")
        return { cancel = true }
    elseif cmd == "crash" then
        open_casino_ui("crash")
        return { cancel = true }
    elseif cmd == "roulette" then
        open_casino_ui("roulette")
        return { cancel = true }
    elseif cmd == "mines" then
        open_casino_ui("mines")
        return { cancel = true }
    elseif cmd == "coin" then
        open_casino_ui("lobby")
        return { cancel = true }
    elseif cmd == "setbal" then
        local exact = tonumber(string.match(args, "(%d+)"))
        if exact == nil then
            return { cancel = true, toast = "Формат: .setbal <сумма> (например: .setbal 100000)" }
        end
        local nb = set_balance(exact)
        return { cancel = true, toast = "💰 Баланс установлен: " .. tostring(nb) .. " 🪙 (шансы не изменены)" }
    elseif cmd == "bal" then
        local lower = string.lower(args)
        if string.sub(lower, 1, 4) == "set " then
            local exact = tonumber(string.match(args, "(%d+)"))
            if exact ~= nil then
                local nb = set_balance(exact)
                return { cancel = true, toast = "💰 Баланс: " .. tostring(nb) .. " 🪙 (шансы прежние)" }
            end
        elseif string.sub(lower, 1, 4) == "add " or string.sub(lower, 1, 1) == "+" then
            local add_v = tonumber(string.match(args, "(%d+)"))
            if add_v ~= nil then
                local nb = set_balance(get_balance() + add_v)
                return { cancel = true, toast = "💰 +" .. tostring(add_v) .. " 🪙 → Баланс: " .. tostring(nb) .. " 🪙" }
            end
        elseif lower == "bonus" then
            local nb = set_balance(get_balance() + 1000)
            return { cancel = true, toast = "🎁 +1000 🪙 → Баланс: " .. tostring(nb) .. " 🪙" }
        end
        return status_header()
    elseif cmd == "ante" then
        local cur = (get_num("ante_bet", 0) == 1) and 0 or 1
        fullgram.storage_set("ante_bet", cur)
        return { cancel = true, toast = cur == 1 and "⚡ Ante Bet ВКЛ (+25%, x2 шанс бонуса)" or "⚡ Ante Bet ВЫКЛ" }
    elseif cmd == "buybonus" then
        local bal = get_balance()
        local bet = parse_bet(args, bal)
        local cost = bet * 100
        if bal < cost then
            return { cancel = true, toast = "Нужно " .. tostring(cost) .. " 🪙 (можно выдать: .setbal " .. tostring(cost) .. ")" }
        end
        set_balance(bal - cost)
        fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + cost)
        fullgram.storage_set("bonus_bet", bet)
        fullgram.storage_set("free_spins", get_num("free_spins", 0) + 10)
        fullgram.storage_set("bonus_mult", 1)
        return { cancel = true, toast = "🎁 Куплено 10 фриспинов по ставке " .. tostring(bet) .. " 🪙! Играйте .zeus или .dogs" }
    elseif cmd == "rtp" then
        return rtp_summary()
    end

    return nil
end`
    },
    {
      id: "fg_anti_typos",
      name: "Анти-опечатки",
      language: "python",
      version: "2.0",
      author: "FullGram",
      description: "Автоматически исправляет частые клавиатурные опечатки, двойные заглавные буквы и лишние пробелы перед знаками препинания.",
      code: `# @name Анти-опечатки
# @id fg_anti_typos
# @version 2.0
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

def clean_line(line):
    if not line:
        return line
    out = re.sub(r"[ \\t]{2,}", " ", line)
    for p in [",", ".", ":", ";", "!", "?"]:
        out = out.replace(" " + p, p)
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
        res = res + [fix_word(core) + punct]
    if len(res) == 0:
        return line
    return " ".join(res)

def clean_text(text):
    if not text or text.startswith("."):
        return text
    lines = text.split("\\n")
    fixed_lines = []
    for ln in lines:
        fixed_lines = fixed_lines + [clean_line(ln)]
    result = "\\n".join(fixed_lines)
    if not result:
        return text
    return result

def on_outgoing_message(ctx):
    original = str(ctx["text"])
    if not original or original.startswith("."):
        return None
    fixed = clean_text(original)
    if fixed and fixed != original:
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
      version: "2.0",
      author: "FullGram",
      description: "Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear.",
      code: `# @name Дедлайны (.dl / .deadline)
# @id fg_deadlines
# @version 2.0
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
        lines = lines + [f"{num}. {status} [{due}] — {task}"]
    return "\\n".join(lines)

def on_command(ctx):
    cmd = ctx["command"]
    if cmd != "dl" and cmd != "deadline":
        return None

    raw = str(ctx["args"]).strip()
    items = load_items()

    if not raw or raw == "list":
        if fullgram.get("open_ui"):
            fullgram.open_ui({"kind": "deadlines", "title": "Дедлайны FullGram"})
            return {"cancel": True}
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
                    updated = updated + [{"due": cur.get("due", ""), "task": cur.get("task", ""), "done": True}]
                else:
                    updated = updated + [it]
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
                    updated = updated + [it]
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
    return { version: parsed.version || 1, flags: merged };
  } catch {
    return { version: 1, flags: base };
  }
}

async function saveFeatureFlags(env, flagsObj) {
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("feature_flags.json", JSON.stringify(flagsObj, null, 2));
}

async function loadNfts(env) {
  const empty = { version: 1, users: {} };
  if (!env.FULLGRAM_KV) return empty;
  const raw = await env.FULLGRAM_KV.get("nfts.json");
  if (!raw) return empty;
  try {
    const parsed = JSON.parse(raw);
    return {
      version: parsed.version || 1,
      users: parsed.users && typeof parsed.users === "object" ? parsed.users : {}
    };
  } catch {
    return empty;
  }
}

async function saveNfts(env, nfts) {
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("nfts.json", JSON.stringify(nfts, null, 2));
}

async function loadBadges(env) {
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
    return {
      version: parsed.version || 1,
      roles: { ...DEFAULT_BADGES.roles, ...(parsed.roles || {}) },
      users,
      usernames: parsed.usernames && typeof parsed.usernames === "object" ? { ...parsed.usernames } : { ...DEFAULT_BADGES.usernames }
    };
  } catch {
    return structuredClone(DEFAULT_BADGES);
  }
}

async function saveBadges(env, badges) {
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("badges.json", JSON.stringify(badges, null, 2));
}

async function loadCosmetics(env) {
  const empty = { version: 1, users: {} };
  if (!env.FULLGRAM_KV) return empty;
  const raw = await env.FULLGRAM_KV.get("cosmetics.json");
  if (!raw) return empty;
  try {
    const parsed = JSON.parse(raw);
    return {
      version: parsed.version || 1,
      users: parsed.users && typeof parsed.users === "object" ? parsed.users : {}
    };
  } catch {
    return empty;
  }
}

async function saveCosmetics(env, cosmetics) {
  if (!env.FULLGRAM_KV) return;
  await env.FULLGRAM_KV.put("cosmetics.json", JSON.stringify(cosmetics, null, 2));
}

async function applyCosmeticChange(env, body) {
  const peerId = body.peerId != null ? String(body.peerId).trim() : "";
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

  // Strict owner-only access: nobody except the owner can use this bot
  if (!senderIsAdmin) {
    await sendTelegramMessage(env, chatId, "⛔ Этот бот доступен только владельцу FullGram.");
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
          "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Telegram-Init-Data"
        }
      });
    }

    if (request.method === "GET" && path === "/health") {
      return jsonResponse({ ok: true, service: "fullgram-worker" });
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
      return privateJsonResponse(await loadBadges(env));
    }

    if (request.method === "GET" && path === "/cosmetics.json") {
      return privateJsonResponse(await loadCosmetics(env));
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

    if (request.method === "GET" && path === "/nfts.json") {
      return privateJsonResponse(await loadNfts(env));
    }

    if (request.method === "POST" && path === "/decorations/batch") {
      try {
        const body = await request.json();
        const rawIds = Array.isArray(body.peerIds) ? body.peerIds : [];
        const peerIds = Array.from(new Set(
          rawIds.map((v) => String(v || "").trim()).filter((v) => /^-?\d{1,20}$/.test(v))
        )).slice(0, 100);
        const [badges, cosmetics, nfts] = await Promise.all([
          loadBadges(env),
          loadCosmetics(env),
          loadNfts(env)
        ]);
        const users = {};
        for (const id of peerIds) {
          const roleId = badges.users[id] || null;
          const badge = roleId && badges.roles[roleId] ? { roleId, ...badges.roles[roleId] } : null;
          const cosmetic = cosmetics.users[id] || null;
          const userNfts = Array.isArray(nfts.users[id]) ? nfts.users[id] : [];
          if (badge || cosmetic || userNfts.length) {
            users[id] = { badge, cosmetics: cosmetic, nfts: userNfts };
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
        const requestedPeerId = body.peerId != null ? String(body.peerId).trim() : "";
        if (!auth.isAdmin && requestedPeerId !== auth.uid) {
          return jsonResponse({ ok: false, error: "Forbidden: can only modify your own cosmetics" }, 403);
        }
        const user = await applyCosmeticChange(env, body);
        return jsonResponse({ ok: true, user });
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

      if (request.method === "POST" && path === "/admin/nft") {
        try {
          const body = await request.json();
          const peerId = body.peerId != null ? String(body.peerId).trim() : "";
          if (!/^-?\d{1,20}$/.test(peerId)) {
            throw new Error("Invalid peerId");
          }
          const nfts = await loadNfts(env);
          const list = Array.isArray(nfts.users[peerId]) ? nfts.users[peerId] : [];
          const entryId = body.id != null && String(body.id).trim()
            ? String(body.id).trim().slice(0, 64)
            : (body.nftId != null && String(body.nftId).trim()
              ? String(body.nftId).trim().slice(0, 64)
              : `fg_nft_${Date.now()}_${Math.floor(Math.random() * 10000)}`);

          if (body.enabled === false) {
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
            const entry = {
              id: entryId,
              giftId,
              title: typeof body.title === "string" && body.title.trim() ? body.title.trim().slice(0, 64) : "NFT",
              modelName: typeof body.modelName === "string" ? body.modelName.trim().slice(0, 64) : "",
              backdropName: typeof body.backdropName === "string" ? body.backdropName.trim().slice(0, 64) : "",
              backdropId: Number.isFinite(rawBackdropId) ? Math.floor(rawBackdropId) : null,
              patternName: typeof body.patternName === "string" ? body.patternName.trim().slice(0, 64) : "",
              number,
              note: typeof body.note === "string" ? body.note.trim().slice(0, 120) : "",
              pinned: body.pinned !== false,
              grantedBy: auth.uid,
              grantedAt: Math.floor(Date.now() / 1000)
            };
            const idx = list.findIndex((item) => item.id === entryId);
            if (idx >= 0) list[idx] = entry;
            else list.unshift(entry);
            nfts.users[peerId] = list.slice(0, 50);
          }
          await saveNfts(env, nfts);
          return jsonResponse({ ok: true, id: entryId, items: nfts.users[peerId] || [] });
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
