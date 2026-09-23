-- The PC's MAX-FACTOR row: mint one Gigantamax Factor from ten Dynamax
-- Candies, behind a YES/NO confirmation.
--
-- WHY THE HOOK.  Both generations route their PC menu rows through the same
-- `ui.pc.items` hook -- the engine's own cross-generation seam, documented as
-- "same name, different menu": Gen 1's OverworldController:openPC (BILL's PC /
-- <PLAYER>'s PC / ...), Gen 2's PcMenu (the storage system) and Gen 2's
-- ItemPcMenu (<PLAYER>'s PC).  Every one of those sites appends its own exit
-- row AFTER the hook, so a row added here lands as the last real option and can
-- never orphan LOG OFF / SEE YA!.  This is the "patch, never override" route:
-- the engine's own list is passed through and extended, not replaced.
--
-- GEN 2's ITEM PC NEEDS ONE MORE PATCH.  PcMenu:choose already dispatches an
-- injected row through its own `onSelect`, but ItemPcMenu:choose did not -- a
-- hook row drew there and then fell through to `close()`, doing nothing.  The
-- first Gen 2 list this hook sees gets the same one-line dispatch installed on
-- ItemPcMenu, guarded by a marker so a second load cannot stack a second
-- wrapper.  It is a STRICT addition: a row with no `onSelect` still reaches the
-- original method untouched.
--
-- THE DIALOG is the engine's OWN TextBox with `opts.choice` -- the dialogue box
-- every script on both generations already uses, and the one yes/no widget that
-- draws correctly on both -- so no second dialog is invented here.  The result
-- is a plain message box.  NO leaves the PC exactly where it was; YES converts
-- only when ten candies are really in the bag, and otherwise says so without
-- spending anything.
--
-- The dialog is resolved lazily, at select time: a build with no mod.ui facade
-- still gets the ROW (and the wrapped hook), it simply cannot open a prompt --
-- the failure is confined to the moment a player picks it.
return {
  install = function(mod, ctx, GF)
    if type(GF) ~= "table" then return end
    local Bag = require("src.inventory.Bag")

    -- The conversion itself, exposed so a test (and any peer mod) can run it
    -- without a live PC.  Spends COST candies and adds one Factor, or answers
    -- false + a reason having changed nothing.
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

    local function textBox(game, text, onDone, opts)
      local Widget = mod.ui and mod.ui.TextBox
      if not (type(Widget) == "table" and type(Widget.new) == "function") then
        return nil
      end
      return Widget.new(game, text, onDone, opts)
    end

    local function show(game, text)
      if not (game and game.stack and type(game.stack.push) == "function") then
        return
      end
      local box = textBox(game, text)
      if box then game.stack:push(box) end
    end

    -- The YES/NO answer.  NO is the cancel path: nothing is spent and the PC
    -- is left exactly as it was (the TextBox has already popped itself).
    local function answer(game, yes)
      if not yes then return end
      local ok = mod.exports.maxFactorConvert(game and game.save,
        game and game.data)
      if ok then
        show(game, "1 MAX-FACTOR\nwas created!")
      else
        show(game, "You don't have\n10 MAX CANDY.")
      end
    end

    local function ask(game)
      if not (game and game.stack and type(game.stack.push) == "function") then
        return
      end
      local box = textBox(game, GF.PC_QUESTION, nil, {
        choice = function(yes) answer(game, yes) end,
      })
      if box then game.stack:push(box) end
    end

    local itemPcPatched = false
    local function patchGen2ItemPc()
      if itemPcPatched then return end
      local ok, ItemPcMenu = pcall(require, "src.ui.gen2.ItemPcMenu")
      if not (ok and type(ItemPcMenu) == "table"
          and type(ItemPcMenu.choose) == "function") then
        return
      end
      if ItemPcMenu.__g9factorPatched then
        itemPcPatched = true
        return
      end
      local base = ItemPcMenu.choose
      ItemPcMenu.choose = function(self, ...)
        local entry = self and self.entries and self.entries[self.index]
        if entry and type(entry.onSelect) == "function" then
          entry.onSelect(self, self.game)
          return
        end
        return base(self, ...)
      end
      ItemPcMenu.__g9factorPatched = true
      itemPcPatched = true
    end

    -- Gen 2 lists carry row `id`s; Gen 1's openPC rows carry labels only.  The
    -- distinction is what decides whether ItemPcMenu needs the dispatch patch
    -- (it is harmless to install it for the storage PC too).
    local function isGen2List(items)
      for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.id ~= nil then return true end
      end
      return false
    end

    local function alreadyListed(items)
      for _, item in ipairs(items or {}) do
        if type(item) == "table" and item.label == GF.PC_LABEL then
          return true
        end
      end
      return false
    end

    return mod.hooks:wrap("ui.pc.items", function(next, game, items)
      if type(items) == "table" and not alreadyListed(items) then
        if isGen2List(items) then patchGen2ItemPc() end
        items[#items + 1] = {
          label = GF.PC_LABEL,
          onSelect = function() ask(game) end,
        }
      end
      if type(next) == "function" then return next(game, items) end
      return items
    end)
  end,
}
