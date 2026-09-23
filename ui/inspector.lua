-- ui/inspector.lua -- the party-menu HAPPINESS and GIMMIGHOUL inspectors.
--
-- Two read-only popups, opened from the party menu's own action list through
-- the engine's `ui.party.submenu` hook (so no engine file is replaced and the
-- rows sit with STATS / SWITCH / the field moves on BOTH generations):
--
--   * HAPPINESS shows the SELECTED Pokemon's friendship -- Gold's real
--     `mon.happiness`, or the invisible `g9Happiness` this mod keeps on
--     Red/Blue/Yellow when GEN 1 FRIENDSHIP is on -- as a figure and a bar
--     against the threshold the evolution data uses (160 / 220), the
--     friendship-gated evolutions it is working toward, and a short list of the
--     ways the value actually rises.
--
--   * GIMMIGHOUL shows a Gimmighoul's saved coin charge
--     (`mon.g9GimmighoulCharge`) as a segmented bar and how many coins are
--     still needed.  The row only ever appears on a Gimmighoul, so the screen
--     is exclusive to the line by construction.
--
-- SURFACE.  Both styles own the same 540x360 page, so an inspector can never be
-- collapsed into a canvas of the wrong shape:
--   * Gen 1 answers :uiSize(); Gold has no :uiSize, so the Gen 2 instance
--     answers :drawsWidescreen() + :wantsFillScale() and paints the whole window
--     in :drawWidescreen (the documented Gen 2 surface contract -- see g9-gui's
--     ui/shell.lua and GEN2-PORT.md).
--   * MODERN draws at that page's own 540x360 scale.  NATIVE draws the classic
--     160x144 Game Boy layout under a scale that fits it to the page, over white
--     paper, so it is a full native-resolution screen rather than a small panel
--     floating in a wide one.
--
-- Both screens are pure viewers: they never write to a Pokemon or a save, so
-- they cannot corrupt anything.  A B press (or the party menu's own cancel)
-- pops them.
return function(mod, ctx)
  local Style = ctx.Style
  local opt = ctx.opt
  local Alt = ctx.alt
  local gen = ctx.gen or 1
  local chargeMax = tonumber(ctx.chargeMax) or 20
  -- Gold's friendship figures.  `Happiness` is the ENGINE'S own module (the one
  -- that moves the byte) when main.lua could require it; `Gains` is
  -- data/happiness_gains.lua -- the transcription of the cart's
  -- data/events/happiness_changes.asm, the labels and the tier rule -- which is
  -- both the fallback for an engine without the module and the one place the
  -- screen's wording lives.  Neither this file nor those numbers are invented
  -- here: every figure is read out of one of them.
  local Happiness = ctx.happiness
  local Gains = ctx.gains
  local chargeField = (Alt and Alt.CHARGE_FIELD) or "g9GimmighoulCharge"
  local isGimmighoul = (Alt and Alt.isGimmighoul) or function(s)
    return type(s) == "string" and s:sub(1, 11) == "GIMMIGHOUL"
  end

  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")
  local C = Style.col

  local M = {}

  local MODERN_W, MODERN_H = 540, 360
  local NATIVE_W, NATIVE_H = 160, 144
  local HAPPY_MAX = 255

  local function on(key)
    local v = opt(key)
    return not (v == "false" or v == false)
  end

  -- The engine's Mod Manager stores a choice's SECOND tuple element
  -- (src/mods/ManagerState.lua: `setOption(..., choices[index][2])`) and its
  -- menu prints the FIRST, so `opt("inspector_style")` answers with a value
  -- from options.lua's own `default`/choices pair -- "MODERN" / "NATIVE" today.
  -- Read it case-insensitively: earlier 0.5.x rows stored the same upper-case
  -- string (that spelling is kept on purpose, so an existing save's row keeps
  -- matching a choice and the manager prints "NATIVE" back), and a hand-edited
  -- options.lua or a fork that spells it differently must not silently fall
  -- back to MODERN -- the whole point of NATIVE is that whoever picks it gets
  -- the cart's white screen.
  local function styleName()
    local v = opt("inspector_style")
    if type(v) == "string" then
      local s = v:lower()
      if s == "native" then return "native" end
    end
    return "modern"
  end

  -- ------------------------------------------------------------- readings
  local function friendshipOf(mon)
    if type(mon) ~= "table" then return 0 end
    local v = tonumber(mon.happiness)
    if v then return v end
    v = tonumber(mon.g9Happiness)
    if v then return v end
    return 70
  end

  local function nameOf(game, mon)
    if type(mon) ~= "table" then return "?" end
    if mon.nickname and mon.nickname ~= "" then return mon.nickname end
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[mon.species]
    return (def and def.name) or tostring(mon.species or "?")
  end

  local function speciesName(game, species)
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[species]
    return (def and def.name) or tostring(species or "?")
  end

  -- Which pair of party/page a mon belongs to is not what this screen shows:
  -- it shows ONE mon, the one the party menu's submenu was opened on.
  local function routesOf(game, species)
    local out = {}
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[species]
    for _, row in ipairs((def and def.evolutions) or {}) do
      local threshold
      if type(row.method) == "string" then
        threshold = tonumber(row.method:match("^G9_HAPPINESS_(%d+)$"))
          or tonumber(row.method:match("^G9_HAPPINESS_STONE_(%d+)$"))
      end
      threshold = threshold or tonumber(row.minHappiness)
      if threshold then
        out[#out + 1] = {
          name = speciesName(game, row.species or row.into),
          threshold = math.floor(threshold),
        }
      end
    end
    return out
  end

  -- The thresholds worth marking on the bar: the ones the data uses, or the
  -- canonical 160 / 220 when the species has no friendship route at all.
  local function thresholdsOf(routes)
    local seen, out = {}, {}
    for _, r in ipairs(routes) do
      if not seen[r.threshold] then
        seen[r.threshold] = true
        out[#out + 1] = r.threshold
      end
    end
    if #out == 0 then out = { 160, 220 } end
    table.sort(out)
    return out
  end

  local function metColor(value, th)
    if value >= th then return C.good end
    if value >= th * 0.75 then return C.warn end
    return C.bad
  end

  -- ------------------------------------------------- how the value rises
  -- Each action, with the figure it actually pays.
  --
  -- Gen 1 has no friendship byte at all, so the value is THIS MOD'S OWN tracker
  -- (see main.lua): a flat +10 a level and +2 a win.  Its list is that pair
  -- plus the ceiling and the value a fresh mon starts on.
  local function gen1Methods()
    return {
      { label = "LEVEL UP",   text = "+10" },
      { label = "BATTLE WIN", text = "+2" },
      { label = "MAXIMUM",    text = "255" },
      { label = "STARTS AT",  text = "70" },
    }
  end

  -- Gold's real friendship, and its steps are the CART'S OWN -- not flat.  The
  -- value BEFORE the change picks one of three columns of
  -- data/events/happiness_changes.asm (under 100 / under 200 / 200 up), so the
  -- same action is worth less to a mon that already adores you.  One figure
  -- would therefore be a lie, which is why the wide page prints the whole
  -- three-column table and lights the column the mon is in.  Every number comes
  -- out of the engine's Happiness module or out of data/happiness_gains.lua --
  -- never out of this file.
  local TIER_HEAD = { "<100", "100+", "200+" }
  local TIER_TOKEN = { "<100", "100-199", "200+" }

  -- "+5" for a single figure, "+1..10" when the row covers several styles
  -- (HAIRCUT's six cuts pay anywhere in that range), "0" for a step that
  -- rounds to nothing (an X item at 200 up).
  local function figure(span)
    if not span then return "" end
    local lo = tonumber(span[1]) or 0
    local hi = tonumber(span[2]) or lo
    if lo == 0 and hi == 0 then return "0" end
    if lo == hi then return "+" .. tostring(lo) end
    return "+" .. tostring(lo) .. ".." .. tostring(hi)
  end

  -- One row per raising action, in data/happiness_gains.lua's order, each with
  -- its three tier spans.  Empty when that module did not load -- the caller
  -- then prints a short built-in list of labels with no figures rather than
  -- dropping the whole screen.
  local function gen2Methods()
    local out = {}
    if type(Gains) == "table" and type(Gains.RAISERS) == "table" then
      for _, entry in ipairs(Gains.RAISERS) do
        out[#out + 1] = {
          label = entry.label, short = entry.short,
          spans = Gains.spansOf(Happiness, entry),
        }
      end
    end
    return out
  end

  -- The column a value reads.  The data module owns the boundaries (the cart's
  -- 100 / 200); the literals are the same rule, for the case it did not load.
  local function tierOf(value)
    if type(Gains) == "table" and type(Gains.tierOf) == "function" then
      return Gains.tierOf(value)
    end
    if (value or 0) < 100 then return 1 end
    if (value or 0) < 200 then return 2 end
    return 3
  end

  -- The bar's colour reads against the LOWEST threshold the species is working
  -- toward: red until it is close, amber near it, green once met.
  local function routeColor(value, routes)
    local ths = thresholdsOf(routes)
    return metColor(value, ths[1] or 160)
  end

  -- ------------------------------------------------- modern: 540x360 page
  local function drawModernHappiness(self, W, H)
    local fonts = Style.fonts(self.game, "modern")
    local mon = self.mon
    local value = friendshipOf(mon)
    local routes = routesOf(self.game, mon and mon.species)

    Style.set(C.black, 0.55)
    Style.rect("fill", 0, 0, W, H, 0)

    local PW, PH = 470, 310
    local X = math.floor((W - PW) * 0.5)
    local Y = math.floor((H - PH) * 0.5)
    Style.panel(X, Y, PW, PH, { radius = 8, shadow = 5,
      color = C.panelLit, border = C.borderLit })
    Style.set(C.panelDeep, 0.95)
    Style.rect("fill", X + 1, Y + 1, PW - 2, 34, 7)
    Style.set(C.accent, 0.4)
    Style.rect("fill", X + 1, Y + 35, PW - 2, 1, 0)
    Style.text("HAPPINESS", X + 18, Y + 10, fonts.title, "left", C.accent)

    local pad = 18
    local name = nameOf(self.game, mon) .. "   Lv" .. tostring(mon and mon.level or 0)
    Style.text(Style.fit(name, fonts.body, PW - 190), X + pad, Y + 48,
      fonts.body, "left", C.ink)
    local col = routeColor(value, routes)
    Style.text(tostring(value), X + PW - pad - 74, Y + 46, fonts.title, "right", col)
    Style.text("/" .. HAPPY_MAX, X + PW - pad, Y + 50, fonts.small, "right", C.inkFaint)

    -- the bar, with a tick at every threshold the data actually uses
    local barX, barY, barW, barH = X + pad, Y + 92, PW - pad * 2, 13
    Style.bar(barX, barY, barW, barH, value / HAPPY_MAX, col,
      { bg = C.panelDeep, border = C.border, radius = 6 })
    for _, th in ipairs(thresholdsOf(routes)) do
      local tx = math.floor(barX + barW * (th / HAPPY_MAX))
      Style.set(value >= th and C.good or C.borderLit, 0.95)
      Style.rect("fill", tx, barY - 3, 2, barH + 6, 0)
      Style.text(tostring(th), tx, barY + barH + 3, fonts.small, "center",
        value >= th and C.good or C.inkFaint)
    end

    -- two columns: the evolutions being worked toward, and how it rises
    local colW = math.floor((PW - pad * 2 - 18) * 0.5)
    local lx = X + pad
    local rx = X + pad + colW + 18
    local top = Y + 136
    Style.text("EVOLUTIONS", lx, top, fonts.small, "left", C.accentDim)
    local ry = top + 20
    if #routes == 0 then
      Style.text("No friendship evolution.", lx, ry, fonts.small, "left", C.inkFaint)
    end
    for i = 1, math.min(#routes, 6) do
      local r = routes[i]
      local met = value >= r.threshold
      Style.text(Style.fit(r.name, fonts.small, colW - 60), lx, ry,
        fonts.small, "left", met and C.good or C.inkDim)
      Style.text((met and "MET " or "NEED ") .. tostring(r.threshold),
        lx + colW, ry, fonts.small, "right", met and C.good or C.gold)
      ry = ry + 18
    end

    Style.text("HOW IT RISES", rx, top, fonts.small, "left", C.accentDim)
    local my = top + 20
    if gen == 2 then
      -- the cart's three columns, the one the mon is in lit: friendship pays
      -- less once it is high, so one figure per action could not be true
      local tier = tierOf(value)
      local cx = { rx + colW - 88, rx + colW - 44, rx + colW }
      for i = 1, 3 do
        Style.text(TIER_HEAD[i], cx[i], top, fonts.small, "right",
          i == tier and C.accent or C.inkFaint)
      end
      local rows = gen2Methods()
      if #rows == 0 then
        Style.text("How it rises is in the game's own hands.", rx, my,
          fonts.small, "left", C.inkFaint)
      end
      -- a label has to end before the first figure column begins, so budget it
      -- from the WIDEST figure this font actually draws, never a guess
      local figW = 0
      for _, row in ipairs(rows) do
        for i = 1, 3 do
          local w = Style.w(figure(row.spans and row.spans[i]), fonts.small)
          if w > figW then figW = w end
        end
      end
      local labelMax = math.max(24, (colW - 88) - figW - 8)
      for _, row in ipairs(rows) do
        Style.text(Style.fit(row.label, fonts.small, labelMax), rx, my,
          fonts.small, "left", C.inkDim)
        for i = 1, 3 do
          Style.text(figure(row.spans and row.spans[i]), cx[i], my,
            fonts.small, "right", i == tier and C.gold or C.inkFaint)
        end
        my = my + 15
      end
    else
      for _, row in ipairs(gen1Methods()) do
        Style.text(row.label, rx, my, fonts.small, "left", C.inkDim)
        Style.text(row.text, rx + colW, my, fonts.small, "right", C.gold)
        my = my + 18
      end
    end

    if gen == 2 then
      Style.text("SHRINKS AS FRIENDSHIP GROWS", X + PW - pad, Y + PH - 22,
        fonts.small, "right", C.inkFaint)
    end
    Style.text("B  BACK", X + pad, Y + PH - 22, fonts.small, "left", C.inkFaint)
  end

  local function drawModernCharge(self, W, H)
    local fonts = Style.fonts(self.game, "modern")
    local mon = self.mon

    Style.set(C.black, 0.55)
    Style.rect("fill", 0, 0, W, H, 0)

    local PW, PH = 470, 250
    local X = math.floor((W - PW) * 0.5)
    local Y = math.floor((H - PH) * 0.5)
    Style.panel(X, Y, PW, PH, { radius = 8, shadow = 5,
      color = C.panelLit, border = C.borderLit })
    Style.set(C.panelDeep, 0.95)
    Style.rect("fill", X + 1, Y + 1, PW - 2, 34, 7)
    Style.set(C.accent, 0.4)
    Style.rect("fill", X + 1, Y + 35, PW - 2, 1, 0)
    Style.text("COIN CHARGE", X + 18, Y + 10, fonts.title, "left", C.accent)

    local pad = 18
    if not (mon and isGimmighoul(mon.species)) then
      Style.text("Not a Gimmighoul.", X + pad, Y + 60, fonts.body, "left", C.bad)
    else
      local charge = tonumber(mon[chargeField]) or 0
      if charge < 0 then charge = 0 end
      if charge > chargeMax then charge = chargeMax end
      Style.text(nameOf(self.game, mon), X + pad, Y + 48, fonts.body, "left", C.ink)
      local col = charge >= chargeMax and C.good or C.gold
      Style.text(tostring(charge) .. " / " .. tostring(chargeMax),
        X + PW - pad, Y + 46, fonts.title, "right", col)

      -- one segment per charge, so the count is legible at a glance
      local segs = math.max(1, chargeMax)
      local gap = 2
      local total = PW - pad * 2 - gap * (segs - 1)
      local segW = math.max(2, total / segs)
      local sy = Y + 96
      for i = 1, segs do
        local lit = i <= charge
        Style.set(lit and C.gold or C.panelDeep, lit and 1 or 0.9)
        Style.rect("fill", math.floor(X + pad + (i - 1) * (segW + gap)),
          math.floor(sy), math.max(1, math.floor(segW)), 12, 2)
      end

      local left = math.max(0, chargeMax - charge)
      Style.text(left == 0 and "Ready!  Use the Gimmighoul Coin."
        or (tostring(left) .. " coin(s) to go"), X + pad, Y + 132,
        fonts.body, "left", left == 0 and C.good or C.inkDim)
      Style.text("Each use spends one coin.", X + pad, Y + 164, fonts.small,
        "left", C.inkFaint)
    end

    Style.text("B  BACK", X + pad, Y + PH - 22, fonts.small, "left", C.inkFaint)
  end

  -- ------------------------------------------------- native: 160x144 layout
  -- The classic Game Boy layout, drawn in its own 160x144 coordinates (white
  -- paper, a black double border, the engine's pixel face); paintNative below
  -- scales this whole page up to fill the surface.
  local function nativePaper(W, H)
    Style.set(C.white)
    Style.rect("fill", 0, 0, W, H, 0)
    Style.set(C.black)
    Style.rect("line", 0.5, 0.5, W - 1, H - 1, 0)
    Style.rect("line", 1.5, 1.5, W - 3, H - 3, 0)
  end

  local function drawNativeHappiness(self, W, H)
    local fonts = Style.fonts(self.game, "native")
    local mon = self.mon
    local value = friendshipOf(mon)
    local routes = routesOf(self.game, mon and mon.species)
    nativePaper(W, H)
    local pad = 6

    Style.text("HAPPINESS", math.floor(W * 0.5), 5, fonts.title, "center", C.black)
    local name = nameOf(self.game, mon) .. " " .. tostring(mon and mon.level or 0)
    Style.text(Style.fit(name, fonts.body, W - pad * 2 - 40), pad, 18,
      fonts.body, "left", C.black)
    Style.text(tostring(value), W - pad, 18, fonts.body, "right", C.black)

    local barX, barY, barW, barH = pad, 33, W - pad * 2, 6
    Style.bar(barX, barY, barW, barH, value / HAPPY_MAX, C.black,
      { bg = C.white, border = C.black })
    for _, th in ipairs(thresholdsOf(routes)) do
      local tx = math.floor(barX + barW * (th / HAPPY_MAX))
      Style.set(C.black)
      Style.rect("fill", tx, barY - 2, 1, barH + 4, 0)
    end

    local y = 45
    Style.text("EVOLVE", pad, y, fonts.small, "left", C.black)
    y = y + 10
    if #routes == 0 then
      Style.text("none", pad, y, fonts.small, "left", C.black)
      y = y + 10
    end
    for i = 1, math.min(#routes, 2) do
      local r = routes[i]
      local met = value >= r.threshold
      Style.text(Style.fit(r.name, fonts.small, W - pad * 2 - 40), pad, y,
        fonts.small, "left", C.black)
      Style.text((met and "YES " or "no ") .. tostring(r.threshold),
        W - pad, y, fonts.small, "right", C.black)
      y = y + 10
    end

    y = y + 3
    Style.text("RAISE", pad, y, fonts.small, "left", C.black)
    local tier = tierOf(value)
    if gen == 2 then
      -- the tier the figures below hold for, so a gain that shrinks later is
      -- not a mystery
      Style.text(TIER_TOKEN[tier], W - pad, y, fonts.small, "right", C.black)
    end
    y = y + 10
    if gen == 2 then
      -- seven actions on a 160-wide page: two columns of four, each cell the
      -- short label with the figure for the mon's CURRENT tier.  The wide page
      -- prints all three columns -- this is the summarised cut of that table.
      local rows = gen2Methods()
      local cw = math.floor((W - pad * 2 - 8) / 2)
      if #rows == 0 then
        Style.text("in the game's hands", pad, y, fonts.small, "left", C.black)
      end
      -- the cell's label budget comes off the widest figure for THIS tier, so
      -- the two never collide however wide the cart's own font measures
      local figW = 0
      for _, row in ipairs(rows) do
        local w = Style.w(figure(row.spans and row.spans[tier]), fonts.small)
        if w > figW then figW = w end
      end
      local labelMax = math.max(16, cw - figW - 5)
      for i, row in ipairs(rows) do
        local cx = pad + ((i - 1) % 2) * (cw + 8)
        local cy = y + math.floor((i - 1) / 2) * 9
        Style.text(Style.fit(row.short or row.label, fonts.small, labelMax),
          cx, cy, fonts.small, "left", C.black)
        Style.text(figure(row.spans and row.spans[tier]), cx + cw, cy,
          fonts.small, "right", C.black)
      end
    else
      for _, row in ipairs(gen1Methods()) do
        if y > H - 22 then break end
        Style.text(row.label, pad, y, fonts.small, "left", C.black)
        Style.text(row.text, W - pad, y, fonts.small, "right", C.black)
        y = y + 10
      end
    end

    Style.text("B BACK", pad, H - 10, fonts.small, "left", C.black)
  end

  local function drawNativeCharge(self, W, H)
    local fonts = Style.fonts(self.game, "native")
    local mon = self.mon
    nativePaper(W, H)
    local pad = 6

    Style.text("GIMMIGHOUL", math.floor(W * 0.5), 5, fonts.title, "center", C.black)
    if not (mon and isGimmighoul(mon.species)) then
      Style.text("Not a Gimmighoul.", pad, 30, fonts.body, "left", C.black)
    else
      local charge = tonumber(mon[chargeField]) or 0
      if charge < 0 then charge = 0 end
      if charge > chargeMax then charge = chargeMax end
      Style.text("CHARGE " .. tostring(charge) .. "/" .. tostring(chargeMax),
        pad, 22, fonts.body, "left", C.black)
      Style.bar(pad, 40, W - pad * 2, 8, charge / math.max(1, chargeMax),
        C.black, { bg = C.white, border = C.black })
      local left = math.max(0, chargeMax - charge)
      Style.text(left == 0 and "READY!" or (tostring(left) .. " TO GO"),
        pad, 56, fonts.body, "left", C.black)
      Style.text("USE ONE COIN", pad, 72, fonts.small, "left", C.black)
    end
    Style.text("B BACK", pad, H - 14, fonts.small, "left", C.black)
  end

  -- ------------------------------------------------------------- painting
  -- NATIVE renders the 160x144 Game Boy layout at native proportions, scaled
  -- to fill the page, over white paper: a classic screen drawn full-screen.
  local function paintNative(self, surfaceW, surfaceH)
    local scale = math.min(surfaceW / NATIVE_W, surfaceH / NATIVE_H)
    if not (scale and scale > 0) then scale = 1 end
    -- the page's paper, edge to edge
    Style.set(C.white)
    Style.rect("fill", 0, 0, surfaceW, surfaceH, 0)
    local pw, ph = NATIVE_W * scale, NATIVE_H * scale
    local ox = math.floor((surfaceW - pw) * 0.5 + 0.5)
    local oy = math.floor((surfaceH - ph) * 0.5 + 0.5)
    local G = love.graphics
    if G.push then G.push() end
    G.translate(ox, oy)
    G.scale(scale, scale)
    if self.kind == "happiness" then
      drawNativeHappiness(self, NATIVE_W, NATIVE_H)
    else
      drawNativeCharge(self, NATIVE_W, NATIVE_H)
    end
    if G.pop then G.pop() end
    Style.set(C.white)
  end

  local function paint(self)
    if styleName() == "native" then
      paintNative(self, MODERN_W, MODERN_H)
    elseif self.kind == "happiness" then
      drawModernHappiness(self, MODERN_W, MODERN_H)
    else
      drawModernCharge(self, MODERN_W, MODERN_H)
    end
    Style.set(C.white)
  end

  function M.draw(self)
    paint(self)
  end

  -- --------------------------------------------------------------- surface
  -- Both styles own the same 540x360 page, so neither can be squeezed into a
  -- canvas of the wrong shape: Gen 1 answers :uiSize(); Gold has no :uiSize, so
  -- the instance answers :drawsWidescreen() + :wantsFillScale() and paints the
  -- whole window in :drawWidescreen (the documented Gen 2 surface contract --
  -- see g9-gui's ui/shell.lua and GEN2-PORT.md).
  local function installSurface(self)
    function self:sgbPalettes() return {} end
    if gen == 1 then
      function self:uiSize() return MODERN_W, MODERN_H end
      function self:isWideBattleLayout() return true end
      function self:wantsFillScale() return true end
      self.draw = function(s) paint(s) end
    else
      self.draw = function() end
      self.drawsWidescreen = function() return true end
      self.wantsFillScale = function() return true end
      self.drawWidescreen = function(s, winW, winH)
        winW = tonumber(winW) or MODERN_W
        winH = tonumber(winH) or MODERN_H
        local scale = math.min(winW / MODERN_W, winH / MODERN_H)
        if not (scale and scale > 0) then scale = 1 end
        local ox = math.floor((winW - MODERN_W * scale) * 0.5 + 0.5)
        local oy = math.floor((winH - MODERN_H * scale) * 0.5 + 0.5)
        -- the window behind the page: NATIVE is white paper edge to edge (a
        -- full Game Boy screen), MODERN the suite's deep void so its panel
        -- floats in the dark.
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

  -- ------------------------------------------------------------ the object
  local function make(kind, game, opts)
    opts = opts or {}
    local self = {
      game = game, kind = kind, mon = opts.mon, __t = 0,
      isOpaque = false,
    }
    function self:update()
      self.__t = (self.__t or 0) + 1
      local input = self.game and self.game.input
      if input and input:wasPressed("b") then
        local stack = self.game.stack
        if stack and stack:top() == self then stack:pop() end
      end
    end
    installSurface(self)
    return self
  end

  M.create = make

  -- ------------------------------------------------------------- install
  M.install = function()
    local okReg = pcall(function()
      mod.content.screens:register("G9Happiness", {
        new = function(game, o) return make("happiness", game, o or {}) end,
      })
      mod.content.screens:register("G9Gimmighoul", {
        new = function(game, o) return make("charge", game, o or {}) end,
      })
    end)
    if not okReg then
      mod.log:warn("g9-evolutions: could not register the inspector screens")
      return false
    end

    mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, sctx)
      local list = next(game, items, mon, sctx)
      if type(list) ~= "table" then return list end
      -- the battle switch list is not the field party list
      if sctx and sctx.battle then return list end
      if on("happiness_inspector") then
        list[#list + 1] = {
          id = "G9HAPPINESS", label = Strings("HAPPINESS"),
          onSelect = function(m, g)
            Screens.push(g, "G9Happiness", { mon = m })
          end,
        }
      end
      if on("gimmighoul_inspector") and type(mon) == "table"
          and isGimmighoul(mon.species) then
        list[#list + 1] = {
          id = "G9GIMMIGHOUL", label = Strings("COIN CHARGE"),
          onSelect = function(m, g)
            Screens.push(g, "G9Gimmighoul", { mon = m })
          end,
        }
      end
      return list
    end, 0)
    return true
  end

  return M
end
