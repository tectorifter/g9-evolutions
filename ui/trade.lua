-- ui/trade.lua -- the TRADE screen, and the flow behind its two options.
--
-- Reached from the whose-PC menu (the MAX-FACTOR row's new home -- see
-- ui/pc_rows.lua), this is the page the request describes:
--
--   TRADE                                   <- title
--   select the pokemon you wish to trade to evolve it   <- description, no caps
--     TRADE EVO      (a real trade-evolution round trip; see trades/evo.lua)
--     WONDER TRADE   (one-way; a random Pokemon; see trades/wonder.lua)
--
-- Picking an option then asks WHICH Pokemon, from an inline party list drawn
-- with the pack's own icons -- the g9-battle-sprites ones when it is
-- installed, the engine's own otherwise, at a fixed design size either way
-- (ui/mon_art.lua owns that rule).
--
-- THE SCREEN ITSELF IS ALWAYS THE SUITE'S PAGE.  It is a new screen, so there
-- is no cart look for it to fall back to; only the trade ANIMATION has a
-- MODERN/NATIVE choice (the TRADE STYLE row), and that is ui/trade_anim.lua's
-- business -- this file just forwards the row to it.
return function(mod, ctx)
  local Style = ctx.Style
  local MonArt = ctx.monArt
  local TradeAnim = ctx.tradeAnim
  local Wonder = ctx.wonder
  local Evo = ctx.evo
  local gen = ctx.gen or 1
  local opt = ctx.opt
  local Screens = require("src.ui.Screens")
  local C = Style.col

  local W, H = 540, 360
  -- The classic Game Boy page the NATIVE style draws on, scaled to fill the
  -- 540x360 surface above (the same shape ui/inspector.lua's native rung uses).
  local NATIVE_W, NATIVE_H = 160, 144
  local M = {}

  local function on(key)
    local v = opt and opt(key)
    return not (v == "false" or v == false)
  end

  -- The trade ANIMATION's presentation.  Read exactly like the inspectors read
  -- their style row (case-insensitively, defaulting to MODERN), so a stored
  -- "NATIVE" written by the Mod Manager routes to the cart's own animation.
  local function styleName()
    local v = opt and opt("trade_style")
    if type(v) == "string" and v:lower() == "native" then return "native" end
    return "modern"
  end

  -- ---------------------------------------------------------------- money
  -- The wonder trade's fee (the WONDER COST row).  0 means free and no check
  -- runs at all.  The wallet is save.player.money on Gold and save.money on
  -- Gen 1 -- the same two places ui/shell.lua's own money readout reads.
  local function wonderCost()
    local v = opt and opt("wonder_cost")
    local n = tonumber(v)
    if not n or n < 0 then n = 0 end
    return math.floor(n)
  end
  local function moneyOf(save)
    if type(save) ~= "table" then return 0 end
    local player = save.player
    local m = (player and tonumber(player.money)) or tonumber(save.money)
    return m or 0
  end
  local function spendMoney(save, amount)
    if amount <= 0 or type(save) ~= "table" then return end
    local player = save.player
    if player and tonumber(player.money) ~= nil then
      player.money = math.max(0, (tonumber(player.money) or 0) - amount)
    else
      save.money = math.max(0, (tonumber(save.money) or 0) - amount)
    end
  end

  local function nameOf(game, mon)
    if type(mon) ~= "table" then return "?" end
    if mon.nickname and mon.nickname ~= "" then return mon.nickname end
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[mon.species]
    return (def and def.name) or mon.name or tostring(mon.species or "?")
  end

  local function isEgg(mon)
    return type(mon) == "table" and mon.isEgg == true
  end

  -- Greedy word-wrap against a pixel budget, for the NATIVE page's narrow
  -- 160px line (the modern page truncates with Style.fit instead).  Returns a
  -- list of lines; a single over-long word still gets its own line.
  local function wrap(str, font, maxW)
    -- Translate the WHOLE sentence before splitting it: the localizer keys on a
    -- complete source string, so a line broken into English fragments first
    -- would come back untranslated (and the modern page needs the same).  The
    -- per-line Style.w below then localizes each fragment again, which is a
    -- no-op for a string no catalog carries.
    if Style.localize then str = Style.localize(tostring(str or "")) end
    local out, line = {}, ""
    for word in tostring(str or ""):gmatch("%S+") do
      local trial = (line == "") and word or (line .. " " .. word)
      if line == "" or Style.w(trial, font) <= maxW then
        line = trial
      else
        out[#out + 1] = line
        line = word
      end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
  end

  local function itemExists(game, id)
    if type(id) ~= "string" or id == "" then return false end
    local items = game and game.data and game.data.items
    if type(items) == "table" and items[id] then return true end
    local ok, reg = pcall(function() return mod.content.items end)
    if ok and type(reg) == "table" and type(reg.get) == "function" then
      local okG, record = pcall(reg.get, reg, id)
      if okG and record then return true end
    end
    return false
  end

  local function itemLabel(game, id)
    if type(id) ~= "string" then return nil end
    local items = game and game.data and game.data.items
    local record = type(items) == "table" and items[id] or nil
    return (record and record.name) or id
  end

  -- --------------------------------------------------------------- the pool
  -- Rebuilt on EVERY trade (it walks the whole registry, which is cheap at one
  -- trade at a time).  It is deliberately NOT memoised across trades: the
  -- BLACKLIST can be edited in the BLACKLIST window between two wonder trades,
  -- and a cached pool would keep drawing a species the player just delisted.
  -- The blacklist is passed in as wonder_pool.build's `exclude` predicate, so
  -- a delisted species -- or a delisted base's forms -- is simply not in the
  -- pool at all.
  local function poolFor(game)
    local pokemon = game and game.data and game.data.pokemon
    local wp = ctx.wonderPool
    if type(pokemon) ~= "table" or type(wp) ~= "table"
        or type(wp.build) ~= "function" then
      return nil
    end
    local exclude
    if type(ctx.blacklist) == "table"
        and type(ctx.blacklist.readSet) == "function"
        and type(ctx.blacklist.isIn) == "function" then
      local set = ctx.blacklist.readSet(mod, game.save, pokemon)
      if type(set) == "table" and next(set) ~= nil then
        exclude = function(id) return ctx.blacklist.isIn(set, pokemon, id) end
      end
    end
    local ok, built = pcall(wp.build, pokemon, ctx.legendary, ctx.pity,
      exclude, gen)
    if not ok then return nil end
    if type(Wonder.ready) == "function" and Wonder.ready(built) then
      return built
    end
    return nil
  end

  -- ---------------------------------------------------------------- drawing
  local function backdrop()
    Style.set(C.void, 1)
    Style.rect("fill", 0, 0, W, H, 0)
    Style.set(C.panel, 0.35)
    for i = 1, 3 do
      local rw, rh = 190 + i * 92, 150 + i * 70
      Style.rect("line", W * 0.5 - rw * 0.5, H * 0.5 - rh * 0.5, rw, rh, 16)
    end
  end

  local function header(fonts, caption)
    Style.panel(16, 12, W - 32, 66, { radius = 8, shadow = 5,
      color = C.panelLit, border = C.borderLit })
    Style.set(C.panelDeep, 0.95)
    Style.rect("fill", 17, 13, W - 34, 30, 7)
    Style.set(C.accent, 0.4)
    Style.rect("fill", 17, 44, W - 34, 1, 0)
    Style.text("TRADE", 34, 18, fonts.title, "left", C.accent)
    Style.text(caption or "", 34, 50, fonts.body, "left", C.inkDim)
  end

  local function footer(fonts, hints)
    Style.text(hints or "", 34, H - 26, fonts.small, "left", C.inkFaint)
  end

  -- A five-pointed star, filled or hollow.  Drawn rather than typed: the Saira
  -- face ships no U+2605 glyph, so a text star would come out as tofu.
  --
  -- The cart's love.graphics.polygon mangles a CONCAVE polygon handed to it as
  -- a vertex TABLE -- it turned this ten-vertex star into a four-pointed
  -- sparkle in both styles, which a player reported -- so the outline is drawn
  -- edge by edge and the fill is fanned by hand into convex triangles, all
  -- with VARIADIC coordinates (the form Style.chevrons has always used and
  -- that does render correctly).  A star is star-shaped about its own centre,
  -- so it splits exactly into five point-triangles plus five seam-triangles:
  -- each point is its outer vertex flanked by the two INNER vertices either
  -- side of it, and each seam spans centre + the next pair of inners.
  local function star(cx, cy, r, filled)
    local outer, inner = {}, {}
    for i = 1, 5 do
      local a = -math.pi / 2 + (i - 1) * (2 * math.pi / 5)
      local b = a + math.pi / 5
      outer[i] = { cx + math.cos(a) * r, cy + math.sin(a) * r }
      inner[i] = { cx + math.cos(b) * r * 0.45, cy + math.sin(b) * r * 0.45 }
    end
    for i = 1, 5 do
      local o = outer[i]
      local p = inner[i]
      local oNext = outer[i % 5 + 1]
      if filled then
        local oLast = inner[(i + 3) % 5 + 1]      -- inner[i - 1], wrapped
        local iNext = inner[i % 5 + 1]
        love.graphics.polygon("fill", oLast[1], oLast[2], o[1], o[2], p[1],
          p[2])
        love.graphics.polygon("fill", cx, cy, p[1], p[2], iNext[1], iNext[2])
      else
        love.graphics.line(o[1], o[2], p[1], p[2])
        love.graphics.line(p[1], p[2], oNext[1], oNext[2])
      end
    end
  end

  local function starRow(x, y, count, r, color)
    Style.set(color or C.gold)
    for i = 1, 5 do star(x + (i - 1) * (r * 2.4), y, r, i <= count) end
  end

  local OPTIONS = {
    { label = "TRADE EVO",
      blurb = "Trade the Pokemon out and back, so it evolves exactly as a "
        .. "link trade would." },
    { label = "WONDER TRADE",
      blurb = "A one-way trade for a random Pokemon from the whole pool, "
        .. "rarity and all." },
  }

  local function drawMenu(self, fonts)
    header(fonts, "select the pokemon you wish to trade to evolve it")
    local LX, LY, LW, LH = 16, 92, 262, 200
    Style.panel(LX, LY, LW, LH, { radius = 8, shadow = 5,
      color = C.panel, border = C.border })
    for i, option in ipairs(OPTIONS) do
      local ry = LY + 16 + (i - 1) * 44
      local lit = i == self.index
      if lit then
        Style.set(C.rowLit, 0.85)
        Style.rect("fill", LX + 8, ry, LW - 16, 36, 6)
        Style.set(C.accent, 0.85)
        Style.rect("fill", LX + 8, ry, 3, 36, 1)
      end
      Style.text(option.label, LX + 26, ry + 9, fonts.bold, "left",
        lit and C.accent or C.inkDim)
    end
    -- the wider story of each option, and where the pity clock stands
    local RX, RW = 292, W - 16 - 292
    Style.panel(RX, LY, RW, LH, { radius = 8, shadow = 5,
      color = C.panel, border = C.border })
    local sel = OPTIONS[self.index]
    Style.text("OPTION", RX + 16, LY + 14, fonts.small, "left", C.accentDim)
    Style.text(Style.fit(sel and sel.label or "", fonts.bold, RW - 32),
      RX + 16, LY + 32, fonts.bold, "left", C.ink)
    local y = LY + 62
    for _, line in ipairs({ sel and sel.blurb or "" }) do
      Style.text(Style.fit(line, fonts.small, RW - 32), RX + 16, y,
        fonts.small, "left", C.inkDim)
      y = y + 16
    end
    local save = self.game and self.game.save
    local since = tonumber(save and save.g9WonderPity) or 0
    local max = (ctx.pity and ctx.pity.PITY_MAX) or 70
    -- the wonder trade's own fee, when one is set (WONDER COST)
    if sel and sel.label == "WONDER TRADE" and wonderCost() > 0 then
      Style.text("COST", RX + 16, LY + LH - 78, fonts.small, "left",
        C.accentDim)
      Style.text(("¥%d"):format(wonderCost()), RX + RW - 16, LY + LH - 78,
        fonts.small, "right", C.gold)
    end
    Style.text("WONDER PITY", RX + 16, LY + LH - 54, fonts.small, "left",
      C.accentDim)
    Style.bar(RX + 16, LY + LH - 34, RW - 32, 10, since / math.max(1, max),
      C.accent, { bg = C.panelDeep, border = C.border, radius = 5 })
    Style.text(("%d / %d"):format(since, max), RX + RW - 16, LY + LH - 54,
      fonts.small, "right", C.inkFaint)
    footer(fonts, "\xe2\x86\x91\xe2\x86\x93  SELECT     A  OK     B  BACK")
  end

  local function rowsOf(self)
    return self.rows or {}
  end

  local function partyRows(game)
    local out = {}
    for index, mon in ipairs((game and game.save and game.save.party) or {}) do
      if not isEgg(mon) then out[#out + 1] = { mon = mon, index = index } end
    end
    return out
  end

  local function drawPick(self, fonts)
    header(fonts, "select the pokemon you wish to trade to evolve it")
    local LX, LY, LW, LH = 16, 92, W - 32, 216
    Style.panel(LX, LY, LW, LH, { radius = 8, shadow = 5,
      color = C.panel, border = C.border })
    local rows = rowsOf(self)
    for i, row in ipairs(rows) do
      local ry = LY + 10 + (i - 1) * 34
      local lit = i == self.index
      if lit then
        Style.set(C.rowLit, 0.85)
        Style.rect("fill", LX + 8, ry, LW - 16, 30, 6)
        Style.set(C.accent, 0.85)
        Style.rect("fill", LX + 8, ry, 3, 30, 1)
      end
      MonArt.icon(mod, self.game, row.mon, LX + 32, ry + 15, 26)
      Style.text(Style.fit(nameOf(self.game, row.mon), fonts.body, LW - 220),
        LX + 56, ry + 6, fonts.body, "left", lit and C.ink or C.inkDim)
      Style.text("Lv" .. tostring(row.mon.level or 1), LX + LW - 190, ry + 8,
        fonts.small, "left", C.inkFaint)
      local species = row.mon.species
      local def = self.game and self.game.data and self.game.data.pokemon
        and self.game.data.pokemon[species]
      if def and def.types then
        Style.text(table.concat(def.types, "/"), LX + LW - 20, ry + 8,
          fonts.small, "right", C.accentDim)
      end
    end
    if #rows == 1 then
      Style.text("(the party holds no other Pokemon)", LX + LW - 16,
        LY + LH - 22, fonts.small, "right", C.inkFaint)
    end
    footer(fonts, "\xe2\x86\x91\xe2\x86\x93  SELECT     A  OK     B  BACK")
  end

  local function drawResult(self, fonts)
    local roll = self.result or {}
    local mon = roll.mon
    header(fonts, "wonder trade complete")
    local LX, LY, LW, LH = 16, 92, 246, 216
    Style.panel(LX, LY, LW, LH, { radius = 8, shadow = 5,
      color = C.panelLit, border = C.borderLit })
    Style.set(C.void, 1)
    Style.rect("fill", LX + 10, LY + 10, LW - 20, 150, 8)
    if mon then
      MonArt.front(mod, self.game, mon, LX + 20, LY + 20, LW - 40, 118)
    end
    Style.text(Style.fit(nameOf(self.game, mon), fonts.bold, LW - 24),
      LX + LW * 0.5, LY + 162, fonts.bold, "center", C.gold)
    -- The cart's own gene total, on its generation's scale (Gen 2 90, Gen 1
    -- 80 -- data/pity.lua).  Rolled independently of the IVs, from the SAME
    -- rung, so the two ladders agree with the rarity the pull announced.
    Style.text(("DV %d/%d"):format(tonumber(roll.dvScore) or 0,
      tonumber(roll.dvMax) or 90), LX + LW * 0.5, LY + 184, fonts.small,
      "center", C.accentDim)

    local RX, RW = 276, W - 16 - 276
    Style.panel(RX, LY, RW, LH, { radius = 8, shadow = 5,
      color = C.panel, border = C.border })
    local y = LY + 14
    Style.text("RARITY", RX + 16, y, fonts.small, "left", C.accentDim)
    starRow(RX + 100, y + 5, tonumber(roll.entry and roll.entry.star) or 1, 9,
      C.gold)
    y = y + 30
    Style.text("IV TOTAL", RX + 16, y, fonts.small, "left", C.accentDim)
    Style.text(("%d / 186"):format(tonumber(roll.raw) or 0), RX + RW - 16, y,
      fonts.body, "right", C.ink)
    y = y + 26
    local bonus = tonumber(roll.bonus) or 0
    Style.text("IV BONUS", RX + 16, y, fonts.small, "left", C.accentDim)
    Style.text("+" .. bonus .. " STAR" .. (bonus == 1 and "" or "S"),
      RX + RW - 16, y, fonts.body, "right", bonus > 0 and C.good or C.inkFaint)
    y = y + 26
    -- the six modern IVs, in a compact two-column grid
    local ivs = roll.ivs or {}
    local keys = { { "hp", "HP" }, { "atk", "ATK" }, { "def", "DEF" },
                   { "spa", "SPA" }, { "spd", "SPD" }, { "spe", "SPE" } }
    local colW = (RW - 32) * 0.5
    for i, pair in ipairs(keys) do
      local cx = RX + 16 + ((i - 1) % 2) * colW
      local cy = y + math.floor((i - 1) / 2) * 15
      Style.text(pair[2], cx, cy, fonts.small, "left", C.inkFaint)
      Style.text(tostring(tonumber(ivs[pair[1]]) or 0), cx + colW - 12, cy,
        fonts.small, "right", C.inkDim)
    end
    y = y + 3 * 15 + 8
    local item = roll.item and itemLabel(self.game, roll.item)
    if item then
      Style.text("COMES WITH", RX + 16, y, fonts.small, "left", C.accentDim)
      Style.text(Style.fit(item, fonts.small, RW - 130), RX + RW - 16, y,
        fonts.small, "right", C.gold)
      y = y + 20
    elseif roll.itemMissing then
      Style.text("The enabling item is not installed here.", RX + 16, y,
        fonts.small, "left", C.warn)
      y = y + 20
    elseif roll.factor then
      -- A Gigantamax form arrives as its base species with the Factor already
      -- switched on (see trades/wonder.lua), so there is no item to name --
      -- what the player gets is the species' own ability to Gigantamax.
      Style.text("G-FACTOR", RX + 16, y, fonts.small, "left", C.accentDim)
      Style.text("ACTIVE", RX + RW - 16, y, fonts.small, "right", C.good)
      y = y + 20
    end
    local save = self.game and self.game.save
    local max = (ctx.pity and ctx.pity.PITY_MAX) or 70
    local since = tonumber(save and save.g9WonderPity) or 0
    Style.text("PITY", RX + 16, LY + LH - 40, fonts.small, "left",
      C.accentDim)
    Style.text(("%d / %d"):format(since, max), RX + RW - 16, LY + LH - 40,
      fonts.small, "right", C.inkFaint)
    Style.bar(RX + 16, LY + LH - 22, RW - 32, 10, since / math.max(1, max),
      C.accent, { bg = C.panelDeep, border = C.border, radius = 5 })
    footer(fonts, "A  OK")
  end

  local function drawNotice(self, fonts)
    header(fonts, self.noticeCaption
      or "select the pokemon you wish to trade to evolve it")
    local PW, PH = 420, 150
    local X, Y = (W - PW) * 0.5, (H - PH) * 0.5
    Style.panel(X, Y, PW, PH, { radius = 8, shadow = 6,
      color = C.panelLit, border = C.borderLit })
    Style.text(Style.fit(self.notice or "", fonts.body, PW - 40),
      X + PW * 0.5, Y + 40, fonts.body, "center", C.ink)
    if self.noticeDetail then
      Style.text(Style.fit(self.noticeDetail, fonts.small, PW - 40),
        X + PW * 0.5, Y + 74, fonts.small, "center", C.inkDim)
    end
    footer(fonts, "A  OK")
  end

  local function paintModern(self)
    local fonts = Style.fonts(self.game, "modern")
    backdrop()
    if self.phase == "pick" then
      drawPick(self, fonts)
    elseif self.phase == "result" then
      drawResult(self, fonts)
    elseif self.phase == "notice" then
      drawNotice(self, fonts)
    else
      drawMenu(self, fonts)
    end
    Style.set(C.white)
  end

  -- ------------------------------------------------------- native: GB page
  -- The cart's own look for the WHOLE trade screen -- white paper, a black
  -- double border, the engine's pixel face -- drawn in the classic 160x144
  -- coordinates and scaled up to fill the surface.  This is what TRADE STYLE
  -- NATIVE now means for the screen itself, not just the animation that
  -- follows it (the request: "trade screen should also be native like when
  -- native is selected for trade").
  local function nativePaper()
    Style.set(C.white)
    Style.rect("fill", 0, 0, NATIVE_W, NATIVE_H, 0)
    Style.set(C.black)
    Style.rect("line", 0.5, 0.5, NATIVE_W - 1, NATIVE_H - 1, 0)
    Style.rect("line", 1.5, 1.5, NATIVE_W - 3, NATIVE_H - 3, 0)
  end

  -- The cart's pixel face sits low in its line box: measured off the running
  -- game, a native row printed at `y` inks from about y+3 to about y+12,
  -- whatever the cut.  The old hand-picked y of 132 therefore put the button
  -- hint's ink UNDER the printed border -- the "A OK is out of the frame"
  -- report -- so every native page now anchors its bottom cluster to these:
  -- the hint's pen, the pity bar just above it, and its caption above that.
  local NATIVE_FOOT = NATIVE_H - 16     -- 128: the pen of the bottom hint row
  local NATIVE_BAR = NATIVE_FOOT - 8    -- 120: the pity bar
  local NATIVE_LABEL = NATIVE_BAR - 13  -- 107: the pity caption

  -- a line of native text centred in the page, walking down by `step`
  local function drawNativeCentred(lines, font, y, step, maxLines)
    for i = 1, math.min(#lines, maxLines or #lines) do
      Style.text(lines[i], math.floor(NATIVE_W * 0.5), y, font, "center",
        C.black)
      y = y + step
    end
    return y
  end

  local function drawNativeMenu(self, fonts)
    nativePaper()
    local pad = 6
    Style.text("TRADE", math.floor(NATIVE_W * 0.5), 4, fonts.title, "center",
      C.black)
    local y = drawNativeCentred(
      wrap("select the pokemon you wish to trade to evolve it", fonts.small,
        NATIVE_W - pad * 2), fonts.small, 17, 10, 2)

    for i, option in ipairs(OPTIONS) do
      local ry = 44 + (i - 1) * 15
      local lit = i == self.index
      if lit then
        Style.set(C.black)
        Style.rect("fill", pad, ry - 1, NATIVE_W - pad * 2, 14, 0)
      end
      Style.text(option.label, pad + 6, ry + 1, fonts.body, "left",
        lit and C.white or C.black)
    end

    local sel = OPTIONS[self.index]
    local blurb = wrap(sel and sel.blurb or "", fonts.small,
      NATIVE_W - pad * 2)
    -- three blurb lines may run from 73 to an ink bottom of ~105, clear of the
    -- pity caption below; the old start of 78 left no room for the caption
    y = NATIVE_LABEL - 34
    for i = 1, math.min(#blurb, 3) do
      Style.text(blurb[i], pad, y, fonts.small, "left", C.black)
      y = y + 10
    end

    local save = self.game and self.game.save
    local since = tonumber(save and save.g9WonderPity) or 0
    local max = (ctx.pity and ctx.pity.PITY_MAX) or 70
    Style.text("PITY", pad, NATIVE_LABEL, fonts.small, "left", C.black)
    Style.text(("%d/%d"):format(since, max), NATIVE_W - pad, NATIVE_LABEL,
      fonts.small, "right", C.black)
    Style.bar(pad, NATIVE_BAR, NATIVE_W - pad * 2, 6, since / math.max(1, max),
      C.black, { bg = C.white, border = C.black })
    Style.text("A OK   B BACK", pad, NATIVE_FOOT, fonts.small, "left", C.black)
  end

  local function drawNativePick(self, fonts)
    nativePaper()
    local pad = 6
    Style.text("TRADE", math.floor(NATIVE_W * 0.5), 4, fonts.title, "center",
      C.black)
    local rows = rowsOf(self)
    for i, row in ipairs(rows) do
      local ry = 20 + (i - 1) * 17
      local lit = i == self.index
      if lit then
        Style.set(C.black)
        Style.rect("fill", pad, ry, NATIVE_W - pad * 2, 16, 0)
      end
      local ink = lit and C.white or C.black
      MonArt.icon(mod, self.game, row.mon, pad + 8, ry + 8, 16)
      Style.text(Style.fit(nameOf(self.game, row.mon), fonts.body, 96),
        pad + 18, ry + 1, fonts.body, "left", ink)
      Style.text("Lv" .. tostring(row.mon.level or 1), NATIVE_W - pad,
        ry + 3, fonts.small, "right", ink)
    end
    Style.text(#rows == 0 and "No Pokemon." or "A OK   B BACK", pad,
      NATIVE_FOOT, fonts.small, "left", C.black)
  end

  local function drawNativeResult(self, fonts)
    nativePaper()
    local pad = 6
    Style.text("WONDER TRADE", math.floor(NATIVE_W * 0.5), 4, fonts.title,
      "center", C.black)
    local roll = self.result or {}
    local mon = roll.mon

    local bx, by, bw, bh = pad, 20, 66, 66
    Style.nativePanel(bx, by, bw, bh)
    if mon then
      MonArt.front(mod, self.game, mon, bx + 3, by + 3, bw - 6, bh - 6)
    end
    Style.text(Style.fit(nameOf(self.game, mon), fonts.body, bw),
      bx + math.floor(bw * 0.5), by + bh + 2, fonts.body, "center", C.black)

    local rx = 80
    local colW = math.floor((NATIVE_W - pad - rx) / 2)
    -- The label takes its own line and the stars the one below it.  Side by
    -- side they did not fit: the five-star row ran past the right margin and
    -- printed the leading star straight through the closing "TY" of RARITY
    -- (the report).  The column below is then spaced so its last row inks
    -- clear of the pity caption at NATIVE_LABEL.
    Style.text("RARITY", rx, 20, fonts.small, "left", C.black)
    Style.text(("DV %d/%d"):format(tonumber(roll.dvScore) or 0,
      tonumber(roll.dvMax) or 90), NATIVE_W - pad, 20, fonts.small, "right",
      C.black)
    starRow(rx + 2, 38, tonumber(roll.entry and roll.entry.star) or 1, 4,
      C.black)
    Style.text("IV", rx, 44, fonts.small, "left", C.black)
    Style.text(("%d/186"):format(tonumber(roll.raw) or 0), NATIVE_W - pad, 44,
      fonts.body, "right", C.black)
    Style.text("BONUS +" .. (tonumber(roll.bonus) or 0), rx, 55, fonts.small,
      "left", C.black)

    local ivs = roll.ivs or {}
    local keys = { { "hp", "HP" }, { "atk", "ATK" }, { "def", "DEF" },
                   { "spa", "SPA" }, { "spd", "SPD" }, { "spe", "SPE" } }
    for i, pair in ipairs(keys) do
      local cx = rx + ((i - 1) % 2) * colW
      local cy = 66 + math.floor((i - 1) / 2) * 10
      Style.text(pair[2], cx, cy, fonts.small, "left", C.black)
      Style.text(tostring(tonumber(ivs[pair[1]]) or 0), cx + colW, cy,
        fonts.small, "right", C.black)
    end

    local item = roll.item and itemLabel(self.game, roll.item)
    if item then
      Style.text(Style.fit("WITH " .. item, fonts.small,
        NATIVE_W - pad - rx), rx, 96, fonts.small, "left", C.black)
    elseif roll.itemMissing then
      Style.text("NO ITEM HERE", rx, 96, fonts.small, "left", C.black)
    elseif roll.factor then
      Style.text("G-FACTOR", rx, 96, fonts.small, "left", C.black)
    end

    local save = self.game and self.game.save
    local max = (ctx.pity and ctx.pity.PITY_MAX) or 70
    local since = tonumber(save and save.g9WonderPity) or 0
    Style.text(("PITY %d/%d"):format(since, max), pad, NATIVE_LABEL,
      fonts.small, "left", C.black)
    Style.bar(pad, NATIVE_BAR, bw, 6, since / math.max(1, max), C.black,
      { bg = C.white, border = C.black })
    Style.text("A OK", pad, NATIVE_FOOT, fonts.small, "left", C.black)
  end

  local function drawNativeNotice(self, fonts)
    nativePaper()
    local pad = 6
    Style.text("TRADE", math.floor(NATIVE_W * 0.5), 4, fonts.title, "center",
      C.black)
    local y = drawNativeCentred(
      wrap(self.notice or "", fonts.body, NATIVE_W - pad * 2),
      fonts.body, 40, 14, 3)
    if self.noticeDetail then
      drawNativeCentred(wrap(self.noticeDetail, fonts.small,
        NATIVE_W - pad * 2), fonts.small, y + 6, 10, 3)
    end
    Style.text("A OK", pad, NATIVE_FOOT, fonts.small, "left", C.black)
  end

  local function paintNative(self)
    -- the page's paper, edge to edge, then the 160x144 layout scaled to sit
    -- inside it
    Style.set(C.white)
    Style.rect("fill", 0, 0, W, H, 0)
    local scale = math.min(W / NATIVE_W, H / NATIVE_H)
    if not (scale and scale > 0) then scale = 1 end
    local ox = math.floor((W - NATIVE_W * scale) * 0.5 + 0.5)
    local oy = math.floor((H - NATIVE_H * scale) * 0.5 + 0.5)
    local G = love.graphics
    if G.push then G.push() end
    G.translate(ox, oy)
    G.scale(scale, scale)
    local fonts = Style.fonts(self.game, "native")
    if self.phase == "pick" then
      drawNativePick(self, fonts)
    elseif self.phase == "result" then
      drawNativeResult(self, fonts)
    elseif self.phase == "notice" then
      drawNativeNotice(self, fonts)
    else
      drawNativeMenu(self, fonts)
    end
    if G.pop then G.pop() end
  end

  local function paint(self)
    if styleName() == "native" then
      paintNative(self)
    else
      paintModern(self)
    end
    Style.set(C.white)
  end

  -- ---------------------------------------------------------------- surface
  local function installSurface(self)
    self.isOpaque = true
    -- COLOR PROTECTION (g9-gui): mark this page as a modern UI so g9-gui's
    -- toggle keeps the native COLORS / COLOR display mode off it.
    self.__g9modern = true
    function self:sgbPalettes() return {} end
    if gen == 1 then
      function self:uiSize() return W, H end
      function self:isWideBattleLayout() return true end
      function self:wantsFillScale() return true end
      self.draw = function(s) paint(s) end
    else
      self.draw = function() end
      self.drawsWidescreen = function() return true end
      self.wantsFillScale = function() return true end
      self.drawWidescreen = function(s, winW, winH)
        winW = tonumber(winW) or W
        winH = tonumber(winH) or H
        local scale = math.min(winW / W, winH / H)
        if not (scale and scale > 0) then scale = 1 end
        local ox = math.floor((winW - W * scale) * 0.5 + 0.5)
        local oy = math.floor((winH - H * scale) * 0.5 + 0.5)
        -- NATIVE is white paper edge to edge (a full Game Boy screen); MODERN
        -- is the suite's deep void, so its page floats in the dark.
        Style.set(styleName() == "native" and C.white or C.void)
        Style.rect("fill", 0, 0, winW, winH, 0)
        local G = love.graphics
        if G.push then G.push() end
        G.translate(ox, oy)
        G.scale(scale, scale)
        paint(s)
        if G.pop then G.pop() end
        Style.set(C.white)
      end
    end
    self.letterboxWhite = (styleName() == "native")
  end

  -- ------------------------------------------------------------------ flow
  local function exit(self)
    local stack = self.game and self.game.stack
    if stack and type(stack.top) == "function" and stack:top() == self then
      stack:pop()
    end
  end

  local function notice(self, text, detail, caption)
    self.notice, self.noticeDetail = text, detail
    self.noticeCaption = caption
    self.phase = "notice"
  end

  -- Back to the TRADE menu, the cursor on the option just used -- the request:
  -- "wonder trade and trade evo should return to trade screen when they are
  -- over, not to pc screen, if wonder trade is used, cursor returns to wonder
  -- trade row".  Only B in the menu itself leaves for the PC.
  local function backToMenu(self)
    self.phase = "menu"
    self.result = nil
    self.notice, self.noticeDetail, self.noticeCaption = nil, nil, nil
    self.rows = {}
    self.index = (self.pending == "wonder") and 2 or 1
  end

  local function startWonder(self, row)
    local game = self.game
    -- The WONDER COST gate: with a fee set, the wallet is checked BEFORE any
    -- roll happens.  Too little and nothing is traded -- the notice names the
    -- price (a template the catalogs translate for every language).  A fee of
    -- 0 skips the check entirely; a fee the player can afford is spent when the
    -- trade is accepted.
    local cost = wonderCost()
    if cost > 0 and moneyOf(game and game.save) < cost then
      return notice(self, ("Not enough ¥, have at least ¥%d."):format(cost),
        nil, "wonder trade")
    end
    local pool2 = poolFor(game)
    if not pool2 then
      return notice(self, "Nobody is around to wonder trade.",
        "this game's dex has no species to draw from.",
        "wonder trade")
    end
    local itemExistsFn = function(id) return itemExists(game, id) end
    local roll, reason = Wonder.pick({
      save = game.save, pool = pool2, pity = ctx.pity,
      wonderPool = ctx.wonderPool, formItems = ctx.formItems,
      exports = ctx.exports, pokemon = game.data.pokemon, data = game.data,
      gen = gen, level = row.mon.level, rng = Wonder.rng(),
      itemExists = itemExistsFn, setFactor = ctx.setGmaxFactor,
    })
    if not roll then
      return notice(self, "The wonder trade found nothing.",
        "(" .. tostring(reason) .. ")", "wonder trade")
    end
    self.result = roll
    -- accepted -- charge the fee (0 is free; a failed roll above is free too)
    if cost > 0 then spendMoney(game and game.save, cost) end
    self.phase = "run"
    TradeAnim.run(game, {
      style = styleName(),
      -- `mystery` keeps the received Pokemon "???" on every label the
      -- animation draws, so this screen's own result page is what reveals it.
      passes = { { sent = row.mon, received = roll.mon,
        verb = "WONDER TRADE", mystery = true } },
      onDone = function()
        Wonder.commit({
          save = game.save, index = row.index, mon = roll.mon,
          item = roll.item, tier = roll.tier, gen = gen, pity = ctx.pity,
          data = game.data, itemExists = itemExistsFn,
        })
        self.phase = "result"
      end,
    })
  end

  local function startEvo(self, row)
    local game = self.game
    if not Evo.canEvolve(game, gen, row.mon) then
      return notice(self, "It cannot be evolved by a trade.",
        nameOf(game, row.mon) .. " has no trade evolution.",
        "trade evo")
    end
    self.phase = "run"
    TradeAnim.run(game, {
      style = styleName(),
      passes = Evo.plan(row.mon),
      onDone = function()
        Evo.evolve(game, gen, row.mon, game.save, row.index,
          function(evolved)
            if evolved then
              notice(self, nameOf(game, row.mon) .. " evolved!",
                nil, "trade evo")
            else
              notice(self, "It cannot be evolved by a trade.",
                "The trade completed, but nothing changed.", "trade evo")
            end
          end)
      end,
    })
  end

  -- ----------------------------------------------------------------- object
  local function make(game, o)
    o = o or {}
    local self = {
      game = game, phase = "menu", index = 1, rows = {},
      result = nil, notice = nil,
    }
    function self:chooseOption()
      self.pending = (self.index == 1) and "evo" or "wonder"
      self.rows = partyRows(game)
      if #self.rows == 0 then
        return notice(self, "The party holds no Pokemon to trade.", nil,
          "trade")
      end
      self.index = 1
      self.phase = "pick"
    end
    function self:pickSelected()
      local row = self.rows[self.index]
      if not row then return end
      if self.pending == "evo" then return startEvo(self, row) end
      return startWonder(self, row)
    end
    function self:update()
      if self.phase == "run" then return end
      local input = game and game.input
      if not input then return end
      local count
      if self.phase == "menu" then count = #OPTIONS
      elseif self.phase == "pick" then count = #self.rows
      else count = 0 end
      if self.phase == "menu" or self.phase == "pick" then
        if input:wasPressed("up") then
          self.index = self.index > 1 and self.index - 1 or math.max(1, count)
        elseif input:wasPressed("down") then
          self.index = self.index < count and self.index + 1 or 1
        elseif input:wasPressed("a") then
          if self.phase == "menu" then self:chooseOption()
          else self:pickSelected() end
        elseif input:wasPressed("b") then
          if self.phase == "pick" then
            self.phase = "menu"
            self.index = 1
          else
            exit(self)
          end
        end
        return
      end
      -- The trade is over: hand the player back the TRADE menu (cursor on the
      -- option they used), NOT the PC screen underneath.
      if input:wasPressed("a") or input:wasPressed("b") then
        backToMenu(self)
      end
    end
    installSurface(self)
    return self
  end

  M.create = make

  M.install = function()
    local ok = pcall(function()
      mod.content.screens:register("G9Trade", {
        new = function(game, o) return make(game, o or {}) end,
      })
    end)
    if not ok then
      mod.log:warn("g9-evolutions: could not register the trade screen")
    end
    return ok
  end

  M.open = function(game, o)
    if not (game and game.stack) then return nil end
    return Screens.push(game, "G9Trade", o or {})
  end

  -- the option's own vocabulary, for main.lua's boot line
  M.style = styleName
  M.enabled = function() return on("trade") end

  return M
end
