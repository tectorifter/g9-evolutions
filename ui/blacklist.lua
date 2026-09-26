-- ui/blacklist.lua -- the FALLBACK blacklist window.
--
-- g9-battle-sample owns the BLACKLIST window (an OPTIONS-menu row that pushes a
-- screen with screenId "G9Blacklist"), and g9-gui re-skins that screen.  The
-- player asked g9-evolutions to be able to offer THE SAME button and THE SAME
-- window when that mod is not installed, and to show NO second row when it is.
-- So this file is a faithful copy of the sample's native window, wired to
-- data/blacklist.lua instead of the sample's own closures:
--
--   * the SAME screenId ("G9Blacklist") and the SAME instance fields the g9-gui
--     modern skin reads (gen, letter, focus, listIndex, listScroll, filtered,
--     gridRow, gridCol, status, broken, game), so g9-gui dresses this window
--     with its modern look exactly as it dresses the sample's -- "the same GUI
--     native/modern";
--   * the SAME geometry, draw and input (START/SELECT filter, arrow grid
--     navigation, A toggles, B backs out), so the native window is byte-for-
--     byte the sample's look when g9-gui is absent;
--   * the SAME surface contract on both generations (Gen 1's uiSize /
--     isWideBattleLayout, Gold's drawsWidescreen / panelSize trio).
--
-- The ROW is only added when g9-battle-sample is not installed; when it is,
-- that mod's row wins and this mod merely READS its list for the wonder trade's
-- own filter (see data/blacklist.lua).
return function(mod, ctx)
  local Blacklist = ctx.blacklist
  if type(Blacklist) ~= "table" then return nil end
  local Font = require("src.render.Font")

  local M = {}

  -- The request fixes the grid at three generations per row, nine cells.
  local GEN_COUNT = Blacklist.GEN_COUNT or 9
  local LETTER_COUNT = Blacklist.LETTER_COUNT or 26
  local VISIBLE_NAMES = 9
  local NAME_MAX = 21

  -- A 16:9 surface that IS the whole playfield at the game's native 960x540
  -- window: 960/320 = 3 and 540/180 = 3, so the renderer's integer fit scale
  -- lands on a clean 3x with NO letterbox and every 8px frame and glyph stays
  -- on the grid.  The classic 160x144 window is 20x18 tiles; this is 40x22.5.
  local UI_W, UI_H = 320, 180

  local function frame(x, y, w, h, level)
    love.graphics.rectangle("line", x, y, w, h)
    if (level or 1) > 1 then
      love.graphics.rectangle("line", x + 1, y + 1,
        math.max(0, w - 2), math.max(0, h - 2))
    end
  end
  local function cell(text, x, y)
    return Font.draw(text, x, y)
  end

  -- A native Game Boy window ring, tiled from the engine's own border glyphs.
  -- Font.drawBox is the usual way to get this look, but it takes TILE counts,
  -- and this surface's 180-pixel height is 22.5 tiles -- drawBox would put its
  -- bottom row at y=168 and leave a 4px gap down the sides.  Tiling the ring
  -- here is exact at ANY size and lays down the same corner and edge glyphs
  -- drawBox uses.
  local function drawBorder(w, h)
    local B = Font.BORDER
    if not (B and B.tl and B.tr and B.bl and B.br and B.h and B.v) then
      Font.drawBox(0, 0, w / 8, h / 8)
      return
    end
    Font.drawCode(B.tl, 0, 0)
    Font.drawCode(B.tr, w - 8, 0)
    Font.drawCode(B.bl, 0, h - 8)
    Font.drawCode(B.br, w - 8, h - 8)
    for x = 8, w - 16, 8 do
      Font.drawCode(B.h, x, 0)
      Font.drawCode(B.h, x, h - 8)
    end
    for y = 8, h - 8, 8 do
      Font.drawCode(B.v, 0, y)
      Font.drawCode(B.v, w - 8, y)
    end
  end

  -- The border ring is one 8px tile thick, so every band lives inside
  -- [MARGIN, UI_W - MARGIN] / [MARGIN, UI_H - MARGIN] and the header, the name
  -- rows, the grid and the hints all clear it.
  local MARGIN = 12
  local CONTENT_R = UI_W - MARGIN
  -- Header: the two filters in the top corners (START/SELECT cycle them)
  -- with the title centred between, then a hairline rule.
  local HEADER_Y, DIVIDER_Y = 12, 24
  -- Nine name rows down the left, each framed; the cursor's row is framed
  -- twice.  A 180-wide column fits a 21-glyph name at this font.
  local NAME_X, NAME_W = MARGIN, 180
  local NAME_Y0, NAME_STEP, NAME_H = 34, 12, 11
  local NAME_PAD = 4
  -- The 3x3 generation grid down the right, then a [MEGA] [GIGA] row, then the
  -- RESET bar under it.
  local GRID_X = { 202, 238, 274 }
  local GRID_Y = { 34, 53, 72 }
  local GRID_W, GRID_H = 34, 15
  local FORM_Y, FORM_W, FORM_GAP = 94, 52, 2
  local FORM_X = { 202, 202 + FORM_W + FORM_GAP }
  local RESET_X, RESET_Y, RESET_W = 202, 113, 106
  local DIVIDER_Y2 = 148
  local HINT_Y1, HINT_Y2 = 154, 164

  -- Rows 1..3 are the 3x3 generation grid, row 4 the [MEGA] [GIGA] pair and
  -- row 5 the full-width RESET bar.
  local ROW_FORMS, ROW_RESET = 4, 5

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = true
  Screen.screenId = "G9Blacklist"

  function Screen:uiSize() return UI_W, UI_H end

  -- This is a WIDE owner: it tells the engine the whole 320x180 surface is its
  -- own layout, the same marker the engine's own wide battle carries.
  function Screen:isWideBattleLayout() return true end
  Screen.letterboxWhite = true

  -- Gen 2's panel contract.  src/core/Game2.lua composes the window itself and
  -- NEVER reads a state's uiSize() or calls Renderer:setUISize, so a screen
  -- wider than 160x144 has to supply this generation's own contract.
  function Screen:panelSize() return UI_W, UI_H end
  function Screen:battlePanelScale(winW, winH) return self:panelScale(winW, winH) end

  -- Whole window pixels per surface pixel.  Chrome owns the playfield/skin
  -- maths, so it is preferred; the plain floor is the same answer without one.
  function Screen:panelScale(winW, winH)
    local ok, Chrome = pcall(require, "src.ui.gen2.Chrome")
    if ok and type(Chrome) == "table" and Chrome.fitScaleFor then
      local okScale, scale = pcall(Chrome.fitScaleFor, winW, winH,
        UI_W / 8, UI_H / 8)
      if okScale and type(scale) == "number" and scale >= 1 then
        return scale
      end
    end
    if not (winW > 0 and winH > 0) then return 1 end
    return math.max(1, math.floor(math.min(winW / UI_W, winH / UI_H)))
  end

  function Screen:drawsWidescreen() return true end

  function Screen:drawWidescreen(winW, winH)
    local G = love.graphics
    local scale = self:panelScale(winW, winH)
    local ox, oy = 0, 0
    local ok, Chrome = pcall(require, "src.ui.gen2.Chrome")
    if ok and type(Chrome) == "table" and Chrome.letterbox then
      pcall(Chrome.letterbox, winW, winH, 1, 1, 1)
      local okO, x, y = pcall(Chrome.fitOriginFor, winW, winH, scale,
        UI_W / 8, UI_H / 8)
      if okO and type(x) == "number" then ox, oy = x, y end
    else
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", 0, 0, winW, winH)
      ox = math.floor((winW - UI_W * scale) / 2 + 0.5)
      oy = math.floor((winH - UI_H * scale) / 2 + 0.5)
    end
    G.push("all")
    G.translate(ox, oy)
    G.scale(scale, scale)
    self:draw()
    G.pop()
  end

  function Screen:gridCellCount(row)
    if row >= ROW_RESET then return 1 end
    if row == ROW_FORMS then return 2 end
    return 3
  end

  function Screen:clampGridCol()
    local n = self:gridCellCount(self.gridRow)
    if self.gridCol > n then self.gridCol = n end
    if self.gridCol < 1 then self.gridCol = 1 end
  end

  function Screen:clampScroll()
    local n = #self.filtered
    if self.listIndex < 1 then self.listIndex = 1 end
    if n > 0 and self.listIndex > n then self.listIndex = n end
    if self.listIndex <= self.listScroll then
      self.listScroll = self.listIndex
    end
    if self.listIndex > self.listScroll + VISIBLE_NAMES - 1 then
      self.listScroll = self.listIndex - VISIBLE_NAMES + 1
    end
    local maxScroll = math.max(1, n - VISIBLE_NAMES + 1)
    if self.listScroll > maxScroll then self.listScroll = maxScroll end
    if self.listScroll < 1 then self.listScroll = 1 end
  end

  -- The current filter's list: generation AND starting letter, both active at
  -- once (the sample's own example filters gen 1 on the letter A).
  function Screen:rebuild()
    self.filtered = {}
    local pokemon = self.game and self.game.data and self.game.data.pokemon
    local index = Blacklist.buildIndex(pokemon)
    local letter = string.char(64 + self.letter)
    for _, entry in ipairs(index or {}) do
      if entry.gen == self.gen then
        local first = string.sub(entry.name, 1, 1):upper()
        if first == letter then self.filtered[#self.filtered + 1] = entry end
      end
    end
    self.listScroll = 1
    self.listIndex = #self.filtered > 0 and 1 or 0
  end

  function Screen.new(game)
    local self = setmetatable({
      game = game, gen = 1, letter = 1,
      focus = "list", listIndex = 1, listScroll = 1, filtered = {},
      gridRow = 1, gridCol = 1, status = "", broken = false,
    }, Screen)
    pcall(self.rebuild, self)
    return self
  end

  local function safeCall(self, label, fn)
    local ok, err = pcall(fn)
    if not ok then
      mod.log:warn("g9-evolutions: blacklist_screen: %s errored, closing (%s)",
        label, tostring(err))
      self.broken = true
    end
  end

  -- The two stores the screen reads: the registry for the index, the save for
  -- the list.  Both are read fresh, so a write is visible on the next draw.
  local function stores(self)
    local game = self.game
    return game and game.data and game.data.pokemon, game and game.save
  end

  -- LEFT/RIGHT cross between the name list and the generation grid, which the
  -- sample reads as one horizontal run of options: the list is the leftmost
  -- column, and RIGHT walks it into that row's cells -- G1 > G2 > G3 -- then
  -- back to the list.  The [MEGA] [GIGA] row and the RESET bar are rows of
  -- their own that only UP/DOWN reach.
  function Screen:enterGrid(col)
    self.focus = "grid"
    if self.gridRow < 1 or self.gridRow > 3 then self.gridRow = 1 end
    if col < 0 then col = self:gridCellCount(self.gridRow) end
    self.gridCol = col
  end

  function Screen:leaveGrid()
    self.focus = "list"
    if self.gridRow >= ROW_RESET then self.gridRow = 1 end
  end

  function Screen:updateList(input)
    if input:wasPressed("up") then
      if self.listIndex <= 1 then
        self.focus = "grid"
        self.gridRow = ROW_RESET
        self:clampGridCol()
      else
        self.listIndex = self.listIndex - 1
        self:clampScroll()
      end
    elseif input:wasPressed("down") then
      if #self.filtered == 0 or self.listIndex >= #self.filtered then
        self.focus = "grid"
        self.gridRow = 1
        self:clampGridCol()
      else
        self.listIndex = self.listIndex + 1
        self:clampScroll()
      end
    elseif input:wasPressed("right") then
      self:enterGrid(1)
    elseif input:wasPressed("left") then
      self:enterGrid(-1)
    elseif input:wasPressed("a") then
      local entry = self.filtered[self.listIndex]
      if entry then
        local pokemon, save = stores(self)
        Blacklist.toggle(mod, save, pokemon, entry.id)
        self.status = ""
      end
    end
  end

  function Screen:updateGrid(input)
    if input:wasPressed("up") then
      if self.gridRow > 1 then
        self.gridRow = self.gridRow - 1
        self:clampGridCol()
      end
    elseif input:wasPressed("down") then
      if self.gridRow < ROW_RESET then
        self.gridRow = self.gridRow + 1
        self:clampGridCol()
      else
        self.focus = "list"
      end
    elseif input:wasPressed("left") then
      if self.gridCol <= 1 then
        self:leaveGrid()
      else
        self.gridCol = self.gridCol - 1
      end
    elseif input:wasPressed("right") then
      if self.gridCol >= self:gridCellCount(self.gridRow) then
        self:leaveGrid()
      else
        self.gridCol = self.gridCol + 1
      end
    elseif input:wasPressed("a") then
      local pokemon, save = stores(self)
      if self.gridRow >= ROW_RESET then
        Blacklist.reset(mod, save, pokemon)
        self.status = "RESET"
      elseif self.gridRow == ROW_FORMS then
        Blacklist.formGroupToggle(mod, save, pokemon,
          self.gridCol == 2 and "gmax" or "mega")
        self.status = ""
      else
        local g = (self.gridRow - 1) * 3 + self.gridCol
        Blacklist.genToggle(mod, save, pokemon, g)
        self.status = ""
      end
    end
  end

  function Screen:update(dt)
    if self.broken then
      if self.game and self.game.stack then self.game.stack:pop() end
      return
    end
    safeCall(self, "update", function()
      local input = self.game and self.game.input
      if not input then return end
      -- START cycles the generation filter 1>2>...>9>1; SELECT cycles the
      -- starting letter a>b>...>z>a.  Both work from either focus.
      if input:wasPressed("start") then
        self.gen = (self.gen % GEN_COUNT) + 1
        self:rebuild()
        self.status = ""
        return
      end
      if input:wasPressed("select") then
        self.letter = (self.letter % LETTER_COUNT) + 1
        self:rebuild()
        self.status = ""
        return
      end
      if input:wasPressed("b") then
        if self.focus == "grid" then
          self.focus = "list"
          self.status = ""
        elseif self.game and self.game.stack then
          self.game.stack:pop()
        end
        return
      end
      if self.focus == "list" then
        self:updateList(input)
      else
        self:updateGrid(input)
      end
    end)
  end

  function Screen:drawHeader()
    cell(string.format("GEN:[%d]", self.gen), NAME_X, HEADER_Y)
    local letter = string.char(64 + self.letter)
    local letterText = string.format("LET:[%s]", letter)
    cell(letterText, CONTENT_R - Font.width(letterText), HEADER_Y)
    local title = "BLACKLIST"
    cell(title, math.floor((UI_W - Font.width(title)) / 2 + 0.5), HEADER_Y)
    love.graphics.rectangle("fill", MARGIN, DIVIDER_Y, CONTENT_R - MARGIN, 1)
  end

  function Screen:drawNames(set)
    for slot = 1, VISIBLE_NAMES do
      local index = self.listScroll + slot - 1
      local entry = self.filtered[index]
      local y = NAME_Y0 + (slot - 1) * NAME_STEP
      local level = (self.focus == "list" and entry
        and index == self.listIndex) and 2 or 1
      frame(NAME_X, y, NAME_W, NAME_H, level)
      if entry then
        cell(string.sub(entry.name, 1, NAME_MAX), NAME_X + NAME_PAD, y + 2)
        -- The delist mark, right-aligned in the row and read from the raw set
        -- so the row the player actually toggled is the row marked.
        if set[entry.id] then
          local mark = "[x]"
          cell(mark, NAME_X + NAME_W - NAME_PAD - Font.width(mark), y + 2)
        end
      end
    end
  end

  function Screen:drawGrid(set, index)
    local labelY = 3
    for g = 1, GEN_COUNT do
      local row = math.floor((g - 1) / 3) + 1
      local col = ((g - 1) % 3) + 1
      local x, y = GRID_X[col], GRID_Y[row]
      local selected = (self.focus == "grid" and self.gridRow == row
        and self.gridCol == col)
      frame(x, y, GRID_W, GRID_H, selected and 2 or 1)
      local label = string.format("G%d", g)
      cell(label, x + math.floor((GRID_W - Font.width(label)) / 2 + 0.5),
        y + labelY)
      if Blacklist.genComplete(index, set, g) then
        local mark = "X"
        cell(mark, x + GRID_W - 4 - Font.width(mark), y + labelY)
      end
    end
    local forms = { { "MEGA", "mega" }, { "GIGA", "gmax" } }
    for i = 1, #forms do
      local x = FORM_X[i]
      local selected = (self.focus == "grid" and self.gridRow == ROW_FORMS
        and self.gridCol == i)
      frame(x, FORM_Y, FORM_W, GRID_H, selected and 2 or 1)
      local label = forms[i][1]
      cell(label, x + math.floor((FORM_W - Font.width(label)) / 2 + 0.5),
        FORM_Y + labelY)
      if Blacklist.formGroupComplete(index, set, forms[i][2]) then
        local mark = "X"
        cell(mark, x + FORM_W - 4 - Font.width(mark), FORM_Y + labelY)
      end
    end
    local selected = (self.focus == "grid" and self.gridRow >= ROW_RESET)
    frame(RESET_X, RESET_Y, RESET_W, GRID_H, selected and 2 or 1)
    local resetLabel = "RESET"
    cell(resetLabel,
      RESET_X + math.floor((RESET_W - Font.width(resetLabel)) / 2 + 0.5),
      RESET_Y + labelY)
  end

  function Screen:draw()
    if self.broken then return end
    safeCall(self, "draw", function()
      -- A plain native window, drawn the way the engine's own screens draw
      -- theirs: a white interior with the border tiles tiled around the WHOLE
      -- surface.  NEVER call Renderer:setUISize / setCanvas from a draw --
      -- Game:draw has already sized the surface from Screen:uiSize().
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, UI_W, UI_H)
      drawBorder(UI_W, UI_H)
      love.graphics.setColor(0, 0, 0, 1)
      local pokemon, save = stores(self)
      local set = Blacklist.readSet(mod, save, pokemon)
      local index = Blacklist.buildIndex(pokemon)
      self:drawHeader()
      self:drawNames(set)
      self:drawGrid(set, index)
      love.graphics.rectangle("fill", MARGIN, DIVIDER_Y2, CONTENT_R - MARGIN, 1)
      cell("START:GEN  SELECT:LETTER", MARGIN, HINT_Y1)
      cell("A:TOGGLE  B:BACK  L/R:MOVE", MARGIN, HINT_Y2)
      if self.status ~= "" then
        cell(self.status, CONTENT_R - Font.width(self.status), HINT_Y2)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  -- --------------------------------------------------------------- the row
  -- The same descriptor shape the engine's own OPTIONS rows use, so A opens
  -- the screen on BOTH generations' menus.  The row is NOT added when
  -- g9-battle-sample is installed: that mod's own BLACKLIST row is the one the
  -- player sees ("we let the sample win its register"), while this mod still
  -- READS that list for the wonder trade's filter.
  M.install = function()
    local okHook = pcall(function()
      mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
        local result = nextFn(game, rows)
        if type(result) ~= "table" then result = rows end
        if type(result) ~= "table" then return result end
        -- The sample owns the button when it is here.
        if Blacklist.samplePresent(mod) then return result end
        -- A second guard: never add a duplicate of a row another provider
        -- already put on the menu.
        for _, row in ipairs(result) do
          if type(row) == "table" and row.id == "blacklist" then
            return result
          end
        end
        result[#result + 1] = {
          id = "blacklist",
          label = "BLACKLIST",
          value = function(g)
            local pokemon = g and g.data and g.data.pokemon
            local save = g and g.save
            local index = Blacklist.buildIndex(pokemon)
            local set = Blacklist.readSet(mod, save, pokemon)
            return string.format("%d HELD",
              Blacklist.heldCount(index, set))
          end,
          activate = function(g)
            local target = g or game
            local ok, screen = pcall(Screen.new, target)
            if ok and type(screen) == "table" then
              local stack = target and target.stack
              if stack and type(stack.push) == "function" then
                stack:push(screen)
              end
            else
              mod.log:warn(
                "g9-evolutions: BLACKLIST screen failed to open (%s)",
                tostring(screen))
            end
          end,
        }
        return result
      end, 0)
    end)
    if not okHook then
      mod.log:warn("g9-evolutions: could not wrap ui.options.rows for the "
        .. "BLACKLIST row")
    end
    return okHook
  end

  M.Screen = Screen
  M.screenId = "G9Blacklist"
  return M
end
