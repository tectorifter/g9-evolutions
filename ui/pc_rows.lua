-- The whose-PC menu's two g9 rows: MAX-FACTOR and TRADE.
--
-- WHERE THEY LIVE.  Both rows belong to the screen the request names -- the
-- "Access whose PC?" list (attachment 1): BILL's PC / <PLAYER>'s PC /
-- PROF.OAK's PC / ... / TURN OFF.  On Red/Blue/Yellow that list is
-- OverworldState:openPC, whose rows DO travel the engine's own `ui.pc.items`
-- hook (the "same name, different menu" seam) and carry a `label` and no id.
-- On Gold it is src/ui/gen2/CenterPcMenu.lua, which never raises that hook and
-- whose rows carry `id`s.
--
-- So the hook is only half the job.  A list with IDs is one of the OTHER PC
-- menus (PcMenu's storage rows, ItemPcMenu's), and this mod deliberately adds
-- NOTHING there any more -- the rows were MOVED off them.  A list without IDs
-- is the Gen 1 whose-PC screen, and gets both rows.  Gold's whose-PC screen is
-- reached by patching CenterPcMenu itself: buildEntries gets the two rows
-- spliced in just above TURN OFF, and choose is wrapped so a row carrying
-- `onSelect` dispatches through it (the engine's own choose only knows its four
-- ids and would otherwise play the selection sound and do nothing).
--
-- Both patched verbs are strict additions.  A CenterPcMenu with no onSelect row
-- reaches the original choose untouched, and the entries list keeps the engine's
-- own order and its exit row last.
--
-- THE DIALOG is the engine's OWN TextBox with `opts.choice` -- the yes/no widget
-- every script on both generations already uses -- so no second dialog is
-- invented here.  NO leaves the PC exactly where it was; YES converts only when
-- ten candies are really in the bag, and otherwise says so without spending
-- anything.  It is resolved LAZILY, at select time: a build with no mod.ui
-- facade still gets the rows, it simply cannot open the prompt.
return {
  install = function(mod, ctx, opts)
    opts = opts or {}
    local gen = ctx.gen or 1
    local GF = opts.GF
    -- The MAX-FACTOR row needs G-FACTOR's vocabulary (the item id, the candy,
    -- the wording); the TRADE row needs only the screen opener.  Either can be
    -- on while the other is off, and a missing G-FACTOR library costs the
    -- factor row alone rather than the whole whose-PC install.
    local wantFactor = (opts.maxFactor and type(GF) == "table") and true or false
    local wantTrade = opts.trade and true or false
    if not (wantFactor or wantTrade) then return end

    local Bag = require("src.inventory.Bag")

    -- ------------------------------------------------------------ conversion
    -- Exposed so a test (and any peer mod) can run it without a live PC.
    -- Spends COST candies and adds one Factor, or answers false + a reason
    -- having changed nothing.
    if wantFactor then
      mod.exports.maxFactorConvert = function(save, data)
        if type(save) ~= "table" or type(save.inventory) ~= "table" then
          return false, "no_save"
        end
        local have = tonumber(save.inventory[GF.CANDY_ID]) or 0
        if have < GF.COST then return false, "not_enough_candy" end
        Bag.remove(save, GF.CANDY_ID, GF.COST)
        Bag.add(save, GF.ITEM_ID, 1, data)
        return true
      end
    end

    -- --------------------------------------------------------------- dialog
    local function textBox(game, text, onDone, o)
      local Widget = mod.ui and mod.ui.TextBox
      if not (type(Widget) == "table" and type(Widget.new) == "function") then
        return nil
      end
      return Widget.new(game, text, onDone, o)
    end

    local function show(game, text)
      if not (game and game.stack and type(game.stack.push) == "function") then
        return
      end
      local box = textBox(game, text)
      if box then game.stack:push(box) end
    end

    local function answer(game, yes)
      if not yes then return end
      local ok = mod.exports.maxFactorConvert
        and mod.exports.maxFactorConvert(game and game.save, game and game.data)
      if ok then
        show(game, "1 MAX-FACTOR\nwas created!")
      else
        show(game, "You don't have\n10 MAX CANDY.")
      end
    end

    local function askFactor(game)
      if not (game and game.stack and type(game.stack.push) == "function") then
        return
      end
      local box = textBox(game, GF.PC_QUESTION, nil, {
        choice = function(yes) answer(game, yes) end,
      })
      if box then game.stack:push(box) end
    end

    -- The TRADE row opens the trade screen.  The factory is loaded in main.lua
    -- and handed in as `opts.openTrade`, so this file needs no knowledge of it.
    local function openTrade(game)
      if type(opts.openTrade) == "function" then opts.openTrade(game) end
    end

    -- ------------------------------------------------------------ the rows
    -- `forHook` builds the Gen 1 shape (label + keepOpen), `forMenu` the Gen 2
    -- one (id + onSelect(menu, game)).
    local function rowsForHook(game)
      local rows = {}
      if wantFactor then
        rows[#rows + 1] = {
          label = GF.PC_LABEL, keepOpen = true,
          onSelect = function() askFactor(game) end,
        }
      end
      if wantTrade then
        rows[#rows + 1] = {
          label = "TRADE", keepOpen = true,
          onSelect = function() openTrade(game) end,
        }
      end
      return rows
    end

    local function rowsForMenu()
      local rows = {}
      if wantFactor then
        rows[#rows + 1] = {
          id = "g9maxfactor", label = GF.PC_LABEL,
          onSelect = function(_, g) askFactor(g) end,
        }
      end
      if wantTrade then
        rows[#rows + 1] = {
          id = "g9trade", label = "TRADE",
          onSelect = function(_, g) openTrade(g) end,
        }
      end
      return rows
    end

    local function isOurs(entry)
      if type(entry) ~= "table" then return false end
      if entry.id == "g9maxfactor" or entry.id == "g9trade" then return true end
      if wantFactor and entry.label == GF.PC_LABEL then return true end
      return wantTrade and entry.label == "TRADE"
    end

    -- Gen 1 lists carry labels only; every Gen 2 list carries row ids.
    local function isGen2List(items)
      for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.id ~= nil then return true end
      end
      return false
    end

    -- True when a row with this label is already in the list, so the one this
    -- install would add is never stacked on top of it.
    local function hasLabel(items, label)
      for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.label == label then return true end
      end
      return false
    end

    -- ------------------------------------------------------- Gold's whose-PC
    local function patchCenterPc()
      local ok, Center = pcall(require, "src.ui.gen2.CenterPcMenu")
      if not (ok and type(Center) == "table") then return false end
      if Center.__g9pcRowsPatched then return true end

      local baseBuild = Center.buildEntries
      Center.buildEntries = function(self, ...)
        if type(baseBuild) == "function" then baseBuild(self, ...) end
        local entries = self and self.entries
        if type(entries) ~= "table" then return end
        -- Drop any copy a previous run spliced in (a reload, a second install),
        -- so the two rows can never stack.
        local native = {}
        for _, entry in ipairs(entries) do
          if not isOurs(entry) then native[#native + 1] = entry end
        end
        local exit = table.remove(native)
        for _, row in ipairs(rowsForMenu()) do native[#native + 1] = row end
        if exit then native[#native + 1] = exit end
        self.entries = native
      end

      local baseChoose = Center.choose
      Center.choose = function(self, ...)
        local entry = self and self.entries and self.entries[self.index]
        if type(entry) == "table" and type(entry.onSelect) == "function" then
          if type(self.playSfx) == "function" then
            self:playSfx("Sfx_ChoosePcOption")
          end
          entry.onSelect(self, self.game)
          return
        end
        if type(baseChoose) == "function" then return baseChoose(self, ...) end
      end

      Center.__g9pcRowsPatched = true
      return true
    end

    if gen == 2 then patchCenterPc() end

    -- Gen 1's whose-PC screen is the only label-only `ui.pc.items` list, so the
    -- hook is where its rows go.  (On Gold the same hook still fires -- for the
    -- storage and item PCs -- and those lists carry ids, so they are
    -- deliberately left alone.)  Each row is appended only when its own label
    -- is absent, so a list that already names one of them (a peer mod's copy, a
    -- second install) never gets a stack of it.
    return mod.hooks:wrap("ui.pc.items", function(next, game, items)
      if type(items) == "table" and not isGen2List(items) then
        for _, row in ipairs(rowsForHook(game)) do
          if not hasLabel(items, row.label) then items[#items + 1] = row end
        end
      end
      if type(next) == "function" then return next(game, items) end
      return items
    end)
  end,
}
