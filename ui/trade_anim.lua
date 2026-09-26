-- ui/trade_anim.lua -- the TRADE cinematic.
--
-- TWO PRESENTATIONS, one asset each:
--
--   * MODERN is the suite's own page (the 540x360 canvas ui/style.lua draws
--     on): two terminals linked by an accent cable, the traded Pokemon's ICON
--     -- drawn at a FIXED design size, so it can never be squashed by a wider
--     or narrower window -- riding the cable between them, then a flash and,
--     at the end, the received Pokemon's g9 FRONT BATTLE ART on a lit stage.
--     It plays the same on Red/Blue/Yellow and on Gold; only the page scale
--     differs.  This is the look "matching the style of our modern gui".
--
--   * NATIVE hands the beat to the cart's OWN trade animation -- Gen 1's
--     src/ui/TradeAnim.lua ("InternalClockTradeAnim") or Gold's
--     src/ui/gen2/TradeAnim.lua -- exactly as the request asks ("else it
--     triggers a normal trade animation of gen 1 and gen 2").  Nothing about
--     those screens is reimplemented here; they are pushed by id through the
--     engine's own Screens registry, so a caller that replaced them (or a suite
--     that dresses them) is followed.
--
-- THE PASS LIST.  A caller hands in `passes`, each `{ sent = mon, received =
-- mon, verb = "..." }`, and this state plays them in order.  A wonder trade is
-- one pass; TRADE EVO is two (out and back), which is what makes the trade
-- evolution fire the way it does on a real cable -- the engine evolves the mon
-- the local game RECEIVES (src/link/Protocol.lua TradeSession:apply), so the
-- second pass is the one that hands the player's own Pokemon back through the
-- machine for the evolution to run on.
--
-- The state finishes by popping itself and then calling onDone, so onDone runs
-- with the caller's own screen back on top and is free to push the next thing.
return function(mod, ctx)
  local Style = ctx.Style
  local MonArt = ctx.monArt
  local gen = ctx.gen or 1
  local Screens = require("src.ui.Screens")
  local C = Style.col

  local W, H = 540, 360
  local M = {}

  -- One beat per row.  The frames are design frames, ~60 a second: a whole
  -- pass is about 3.8 seconds, two passes about 7.6.
  local PHASES = {
    { id = "cable", frames = 26 },
    { id = "send", frames = 54 },
    { id = "flash", frames = 18 },
    { id = "recv", frames = 54 },
    { id = "reveal", frames = 84 },
  }

  local function ease(t)
    t = math.max(0, math.min(1, t or 0))
    return t * t * (3 - 2 * t)
  end

  local function nameOf(game, mon)
    if type(mon) ~= "table" then return "?" end
    if mon.nickname and mon.nickname ~= "" then return mon.nickname end
    local def = game and game.data and game.data.pokemon
      and game.data.pokemon[mon.species]
    return (def and def.name) or mon.name or tostring(mon.species or "?")
  end

  -- A wonder trade's received Pokemon stays "???" on every label the
  -- animation draws until the caller's own result page (the one with the IVs
  -- and the rarity stars) names it -- the request: "keep received pokemon as
  -- ??? until received screen displays".  A pass without `mystery` (TRADE EVO,
  -- whose received mon is the player's own coming back) is named throughout.
  local function recvLabel(game, pass, mon)
    if type(pass) == "table" and pass.mystery then return "???" end
    return nameOf(game, mon)
  end

  -- ------------------------------------------------------------- geometry
  local CABLE_Y = 268
  local PORT_A, PORT_B = 118, 422
  local TERM_W, TERM_H, TERM_Y = 148, 148, 78
  local TERM_L = 30
  local TERM_R = W - 30 - TERM_W

  local function terminal(self, fonts, x, mon, label, lit)
    local y = TERM_Y
    Style.panel(x, y, TERM_W, TERM_H, { radius = 8, shadow = 5,
      color = C.panelLit, border = lit and C.borderLit or C.border })
    Style.set(C.void, 1)
    Style.rect("fill", x + 12, y + 12, TERM_W - 24, TERM_H - 46, 6)
    Style.set(lit and C.accent or C.border, lit and 0.5 or 0.25)
    Style.rect("line", x + 12.5, y + 12.5, TERM_W - 25, TERM_H - 47, 6)
    if mon then
      MonArt.icon(mod, self.game, mon, x + TERM_W * 0.5,
        y + 12 + (TERM_H - 46) * 0.5, 58)
    end
    Style.text(Style.fit(label, fonts.small, TERM_W - 14),
      x + TERM_W * 0.5, y + TERM_H - 28, fonts.small, "center",
      lit and C.accent or C.inkDim)
  end

  -- ------------------------------------------------------------------ draw
  local function drawModern(self)
    local game = self.game
    local fonts = Style.fonts(game, "modern")
    local pass = self.passes[self.passIndex] or {}
    local sent, received = pass.sent, pass.received
    local phase = PHASES[self.phase] and PHASES[self.phase].id or "cable"
    local p = math.min(1, (self.t or 0) / (PHASES[self.phase] or { frames = 1 }).frames)

    Style.set(C.void, 1)
    Style.rect("fill", 0, 0, W, H, 0)
    -- a few faint rings so the void is not a flat hole
    Style.set(C.panel, 0.35)
    for i = 1, 3 do
      local rw, rh = 150 + i * 96, 120 + i * 74
      Style.rect("line", W * 0.5 - rw * 0.5, H * 0.5 - rh * 0.5, rw, rh, 16)
    end

    -- top strip
    Style.panel(16, 10, W - 32, 34, { radius = 6, color = C.panel,
      border = C.border })
    Style.text("TRADE", 32, 19, fonts.title, "left", C.accent)
    if #self.passes > 1 then
      Style.text(("%s  %d/%d"):format(pass.verb or "LINK TRADE",
        self.passIndex, #self.passes), W - 34, 19, fonts.small, "right",
        C.inkDim)
    else
      Style.text(pass.verb or "LINK TRADE", W - 34, 21, fonts.small, "right",
        C.inkDim)
    end

    -- the two terminals
    terminal(self, fonts, TERM_L, sent, nameOf(game, sent),
      phase == "send" or phase == "flash")
    terminal(self, fonts, TERM_R, received, recvLabel(game, pass, received),
      phase == "recv" or phase == "reveal")

    -- the cable between them
    local grow = (phase == "cable") and ease(p) or 1
    local reach = math.max(0, (PORT_B - PORT_A) * grow)
    Style.set(C.accentDim, 1)
    Style.rect("fill", PORT_A, CABLE_Y - 11, reach, 22, 11)
    Style.set(C.accent, 0.35)
    Style.rect("fill", PORT_A, CABLE_Y - 7, reach, 3, 2)
    Style.set(C.border, 0.8)
    Style.rect("line", PORT_A, CABLE_Y - 11.5, reach, 23, 11)
    for _, px in ipairs({ PORT_A, PORT_B }) do
      Style.set(C.panelLit, 1)
      Style.rect("fill", px - 9, CABLE_Y - 15, 18, 30, 5)
      Style.set(C.borderLit, 0.9)
      Style.rect("line", px - 9.5, CABLE_Y - 15.5, 19, 31, 5)
    end

    -- the travelling bubble
    local travel
    if phase == "send" then
      travel = { mon = sent, x = PORT_A + (PORT_B - PORT_A) * ease(p) }
    elseif phase == "flash" then
      travel = { mon = received, x = PORT_B }
    elseif phase == "recv" then
      travel = { mon = received, x = PORT_B - (PORT_B - PORT_A) * ease(p) }
    end
    if travel then
      Style.set(C.black, 0.45)
      love.graphics.circle("fill", travel.x, CABLE_Y + 3, 30)
      Style.panel(travel.x - 28, CABLE_Y - 28, 56, 56,
        { radius = 28, highlight = false, color = C.void, border = C.accent })
      if travel.mon then
        MonArt.icon(mod, game, travel.mon, travel.x, CABLE_Y, 42)
      end
    end

    -- the flash at the far port
    if phase == "flash" then
      local r = 12 + 70 * p
      Style.set(C.white, (1 - p) * 0.85)
      love.graphics.circle("line", PORT_B, CABLE_Y, r)
      Style.set(C.accent, (1 - p) * 0.9)
      love.graphics.circle("line", PORT_B, CABLE_Y, r * 0.68)
    end

    -- the reveal: the received Pokemon's own front battle art on a stage
    if phase == "reveal" then
      local sw, sh = 300, 214
      local sx, sy = (W - sw) * 0.5, 56
      Style.set(C.black, 0.55)
      Style.rect("fill", 0, 46, W, H - 46, 0)
      Style.panel(sx, sy, sw, sh, { radius = 10, shadow = 6,
        color = C.panelLit, border = C.borderLit })
      Style.set(C.void, 1)
      Style.rect("fill", sx + 8, sy + 8, sw - 16, sh - 16, 8)
      Style.set(C.accent, 0.20 * (1 - p) + 0.08)
      Style.rect("fill", sx + 8, sy + 8, sw - 16, sh - 16, 8)
      if received then
        MonArt.front(mod, game, received, sx + 22, sy + 16, sw - 44, sh - 62)
      end
      Style.text(Style.fit(recvLabel(game, pass, received), fonts.bold, sw - 40),
        W * 0.5, sy + sh - 34, fonts.bold, "center", C.gold)
    end

    -- caption + footer
    local caption
    if phase == "cable" then
      caption = "Connecting through the link cable..."
    elseif phase == "send" then
      caption = "Sending " .. nameOf(game, sent) .. "..."
    elseif phase == "flash" then
      caption = "..."
    elseif phase == "recv" then
      caption = "Receiving " .. recvLabel(game, pass, received) .. "..."
    else
      caption = recvLabel(game, pass, received) .. " arrived!"
    end
    Style.text(caption, W * 0.5, H - 34, fonts.small, "center",
      phase == "reveal" and C.gold or C.inkDim)
    Style.text("B  SKIP", 22, H - 16, fonts.small, "left", C.inkFaint)
    Style.set(C.white)
  end

  -- --------------------------------------------------------------- surface
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
      self.draw = function(s) drawModern(s) end
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
        Style.set(C.void, 1)
        Style.rect("fill", 0, 0, winW, winH, 0)
        local G = love.graphics
        if G.push then G.push() end
        G.translate(ox, oy)
        G.scale(scale, scale)
        drawModern(s)
        if G.pop then G.pop() end
        Style.set(C.white)
      end
    end
  end

  -- ----------------------------------------------------------------- object
  local function make(game, o)
    o = o or {}
    local self = {
      game = game,
      passes = (type(o.passes) == "table" and #o.passes > 0) and o.passes
        or { {} },
      passIndex = 1, phase = 1, t = 0,
      onDone = o.onDone,
    }
    function self:update()
      if self.done then return end
      self.t = self.t + 1
      local input = game and game.input
      -- B / START fast-forwards the rest of the sequence: the trade itself has
      -- already happened, so this skips only the show.
      if input and (input:wasPressed("start") or input:wasPressed("b")) then
        return self:finish()
      end
      local phase = PHASES[self.phase]
      if self.t >= phase.frames then
        if self.phase < #PHASES then
          self.phase = self.phase + 1
          self.t = 0
        elseif self.passIndex < #self.passes then
          self.passIndex = self.passIndex + 1
          self.phase = 1
          self.t = 0
        else
          return self:finish()
        end
      end
    end
    function self:finish()
      if self.done then return end
      self.done = true
      local stack = game and game.stack
      if stack and type(stack.top) == "function" and stack:top() == self then
        stack:pop()
      end
      if self.onDone then self.onDone() end
    end
    installSurface(self)
    return self
  end

  M.create = make

  -- ---------------------------------------------------------------- native
  -- The cart's own animation, once per pass -- but the engine's screen is
  -- built HERE, patched, then pushed (the same two steps Screens.push does),
  -- so the engine's own factory still constructs it and a caller that
  -- replaced it through the registry is still followed.  Three things are
  -- layered on:
  --
  --   * the travelling mon's ICON comes from MonArt.icon -- the g9-battle-
  --     sprites cell when that mod is installed.  The cart draws its own
  --     16x16 registry icon in the bubble, and for a species that registry
  --     never learned (the whole g9 roster) that is an empty bubble.  This is
  --     the request's "between trade is still empty ... it MUST use
  --     g9-battle-sprite icon of the respective pokemons" for NATIVE mode.
  --   * the mon's FRONT PIC in the movie (the engine's own 56x56 battle sprite
  --     at (56,16), drawn by Gen 1's TradeAnim:draw / Gold's
  --     TradeAnimView:drawPic) is replaced by the pack's front art, so the
  --     native style shows the same art the modern style and the trade screens
  --     do (the request: "native is using native battle sprites, it should be
  --     g9-battle-sprites front sprites of respective pokemons").  With no
  --     pack, or before its sheet finishes baking, the engine's own sprite
  --     stands untouched -- never a hole.
  --   * a WONDER TRADE's received Pokemon is named "???" in the animation's
  --     text, so only the caller's result page reveals it.
  --
  -- Every patch is an instance field shadowing the class method and is
  -- guarded, so an engine shape this does not know simply plays the vanilla
  -- animation rather than erroring mid-trade.

  -- The engine's pic slot on BOTH generations: a 7x7 tile box (56px) whose
  -- top-left is (56,16), the cart's sprite bottom-aligned in it.  The pack's
  -- portrait is trimmed to the creature, so it is drawn into a slightly taller
  -- box of its own, bottom-anchored on the cart's floor line so a Weedle and an
  -- Onix stand on the same ground; 64 design units is what lets a whole 64px
  -- sheet frame land at 1:1 instead of being stepped down to half.
  local PIC_X, PIC_W, PIC_FLOOR = 52, 64, 78
  local function drawPackPortrait(game, mon, px)
    if not MonArt.hasPortrait(mod, mon) then return false end
    local ok, drawn, dx, dy, dw, dh = pcall(MonArt.front, mod, game, mon,
      px, PIC_FLOOR - PIC_W, PIC_W, PIC_W, { anchor = "bottom" })
    if not (ok and drawn) then return false end
    -- full-colour opt-out for the SGB/GBC zone post-pass, exactly as the icon
    -- arm (and g9-battle-sprites' own party-icon arm) does: without it the
    -- pack's true-colour art would be recoloured by the zone pass.
    local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
    if okP and type(PaletteFX) == "table"
        and type(PaletteFX.markTrueColor) == "function" then
      pcall(PaletteFX.markTrueColor, dx, dy, dw or PIC_W, dh or PIC_W)
    end
    return true
  end

  local function patchNative(inst, pass)
    if type(inst) ~= "table" then return inst end
    local mystery = type(pass) == "table" and pass.mystery == true
    local game = inst.game

    if gen == 2 then
      -- The received record feeds BOTH the dialog buffers (TradeAnimView
      -- buffers) and the stats panel (drawStats) through its `name`; the pic
      -- path reads `species`, not `name`, so masking the one field is the
      -- whole job.  The icon is drawn through TradeAnimView:drawIcon, which
      -- reads the gen2 icon registry -- patched here to ask MonArt first.
      if mystery and type(inst.get) == "table" then inst.get.name = "???" end
      if type(inst.drawIcon) == "function" then
        local vanilla = inst.drawIcon
        inst.drawIcon = function(self, record, x, y)
          if type(record) == "table"
              and MonArt.icon(mod, self.game or game, record,
                (tonumber(x) or 0) + 8, (tonumber(y) or 0) + 8, 16) then
            return true
          end
          return vanilla(self, record, x, y)
        end
      end
      -- The movie's own front pic (TradeAnim_ShowFrontpic -> drawPic, the 7x7
      -- box at (56,16), bottom-aligned and slid by `offset`).  Shadowing the
      -- ONE method keeps every other beat of Gold's movie -- the ball, the
      -- tube, the stats window, the pic ANIMATION -- untouched; the pack's
      -- portrait simply stands where the cart's sprite would have.
      if type(inst.drawPic) == "function" then
        local vanillaPic = inst.drawPic
        inst.drawPic = function(self, record, offset)
          local px = PIC_X - (tonumber(offset) or 0)
          if drawPackPortrait(self.game or game, record, px) then return end
          return vanillaPic(self, record, offset)
        end
      end
      return inst
    end

    -- Gen 1: the bubble's icon is drawn by PartyMenu.drawIcon (a MODULE
    -- function) from inside the engine's drawIconInBubble.  Swap that module
    -- function only for the duration of the one call, so the bubble art the
    -- engine draws around it is untouched, then put the real one back.
    if type(inst.drawIconInBubble) == "function" then
      local vanillaBubble = inst.drawIconInBubble
      inst.drawIconInBubble = function(self, mon, x, y)
        local okP, PartyMenu = pcall(require, "src.ui.PartyMenu")
        if not (okP and type(PartyMenu) == "table") then
          return vanillaBubble(self, mon, x, y)
        end
        local saved = PartyMenu.drawIcon
        PartyMenu.drawIcon = function(g, m, ix, iy)
          if MonArt.icon(mod, g or self.game or game, m or mon,
              (tonumber(ix) or tonumber(x) or 0) + 8,
              (tonumber(iy) or tonumber(y) or 0) + 8, 16) then
            -- full-colour opt-out for the SGB/GBC zone post-pass, exactly as
            -- g9-battle-sprites' own party-icon arm does: without it the pack's
            -- true-colour cell can be recoloured by the zone pass.
            local okP2, PaletteFX = pcall(require, "src.render.PaletteFX")
            if okP2 and type(PaletteFX) == "table"
                and type(PaletteFX.markTrueColor) == "function" then
              pcall(PaletteFX.markTrueColor, tonumber(ix) or 0,
                tonumber(iy) or 0, 16, 16)
            end
            return true
          end
          if type(saved) == "function" then return saved(g, m, ix, iy) end
          return false
        end
        local ok, err = pcall(vanillaBubble, self, mon, x, y)
        PartyMenu.drawIcon = saved
        if not ok then error(err) end
      end
    end

    -- The received name rides in the dialog text the engine's own update
    -- builds and in the stats panel drawMonInfo prints.  Rewrite the text
    -- after update; for the panel, shadow the species' display name for the
    -- one synchronous draw.  Only the RECEIVED mon (by identity) is touched,
    -- so the player's own mon keeps its name.
    if mystery then
      local label = nameOf(game, pass.received)
      if type(label) == "string" and label ~= "" and label ~= "?" then
        local pattern = label:gsub("(%W)", "%%%1")
        if type(inst.update) == "function" then
          local vanillaUpdate = inst.update
          inst.update = function(self, dt)
            vanillaUpdate(self, dt)
            if type(self.dialogText) == "string" then
              self.dialogText = self.dialogText:gsub(pattern, "???")
            end
          end
        end
        if type(inst.drawMonInfo) == "function" then
          local vanillaInfo = inst.drawMonInfo
          inst.drawMonInfo = function(self, mon, ot, otId, boxTy)
            if mon == pass.received then
              local def = self.game and self.game.data and self.game.data.pokemon
                and self.game.data.pokemon[mon.species]
              if def and def.name then
                local saved = def.name
                def.name = "???"
                local ok, err = pcall(vanillaInfo, self, mon, ot, otId, boxTy)
                def.name = saved
                if not ok then error(err) end
                return
              end
            end
            return vanillaInfo(self, mon, ot, otId, boxTy)
          end
        end
      end
    end

    -- Gen 1 draws the two Pokemon's front pics inline in TradeAnim:draw -- the
    -- player's while the phase is "show_player" (inside a push/translate of
    -- -scx, mirrored) and the received one in "show_enemy" (no translate, also
    -- mirrored).  There is no pic method to shadow, so the frame is wrapped
    -- instead: hide the engine's own sprite for the one call, run the movie,
    -- put the fields back, then stand the pack's portrait on the same floor.
    -- Only the field the engine is about to read is hidden, and only for a
    -- toggle the pack can actually fill, so an absent pack is byte-for-byte
    -- the vanilla movie.
    if type(inst.draw) == "function" then
      local vanillaDraw = inst.draw
      inst.draw = function(self)
        local showSent = self.monVisible and self.phase == "show_player"
          and MonArt.hasPortrait(mod, self.sent) or false
        local showRecv = self.monVisible and self.phase == "show_enemy"
          and MonArt.hasPortrait(mod, self.received) or false
        local sentSprite, sentTC = self.sentSprite, self.sentSpriteTrueColor
        local recvSprite, recvTC = self.recvSprite, self.recvSpriteTrueColor
        if showSent then self.sentSprite, self.sentSpriteTrueColor = nil, nil end
        if showRecv then self.recvSprite, self.recvSpriteTrueColor = nil, nil end
        local ok, err = pcall(vanillaDraw, self)
        self.sentSprite, self.sentSpriteTrueColor = sentSprite, sentTC
        self.recvSprite, self.recvSpriteTrueColor = recvSprite, recvTC
        if showSent then
          drawPackPortrait(self.game or game, self.sent,
            PIC_X - (tonumber(self.scx) or 0))
        elseif showRecv then
          drawPackPortrait(self.game or game, self.received, PIC_X)
        end
        if not ok then error(err) end
      end
    end
    return inst
  end

  -- Build the engine's screen, patch the instance, push it -- exactly the
  -- pair Screens.push performs, so the registry/fallback resolution is the
  -- engine's own.
  local function pushNative(game, id, opts, pass)
    if type(Screens.build) == "function" then
      local ok, inst = pcall(Screens.build, game, id, opts)
      if ok and type(inst) == "table" then
        patchNative(inst, pass)
        local stack = game and game.stack
        if stack and type(stack.push) == "function" then
          stack:push(inst)
          return inst
        end
      end
    end
    return Screens.push(game, id, opts)
  end

  -- The cart's own animation, once per pass.  Gen 1's TradeAnim pops itself
  -- when it is done; Gold's finishes without popping, so its onDone pops --
  -- exactly the shape src/ui/gen2/TradeMenu.lua uses.
  local function runNative(game, o)
    local passes = o.passes or {}
    local i = 0
    local function nextPass()
      i = i + 1
      local pass = passes[i]
      if not pass then
        if o.onDone then o.onDone() end
        return
      end
      if gen == 2 then
        pushNative(game, "Gen2TradeAnim", {
          given = pass.sent, received = pass.received,
          save = game and game.save,
          eventTables = game and game.world and game.world.eventTables,
          onDone = function()
            local stack = game and game.stack
            if stack and type(stack.pop) == "function" then stack:pop() end
            nextPass()
          end,
        }, pass)
      else
        pushNative(game, "TradeAnim", {
          sent = pass.sent, received = pass.received,
          onDone = nextPass,
        }, pass)
      end
    end
    nextPass()
  end

  -- ------------------------------------------------------------------ run
  -- opts: passes, style ("modern"|"native"), onDone
  M.run = function(game, o)
    o = o or {}
    if o.style == "native" then return runNative(game, o) end
    return Screens.push(game, "G9TradeAnim", {
      passes = o.passes, onDone = o.onDone,
    })
  end

  M.install = function()
    local ok = pcall(function()
      mod.content.screens:register("G9TradeAnim", {
        new = function(game, o) return make(game, o or {}) end,
      })
    end)
    if not ok then
      mod.log:warn("g9-evolutions: could not register the trade animation")
    end
    return ok
  end

  return M
end
