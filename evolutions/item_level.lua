-- G9_ITEM_LEVEL -- "use the required item on the Pokemon once it is strong
-- enough".
--
-- This is the Gen 1 answer to a held-item (or item-trade) evolution.  Red/
-- Blue/Yellow has no held-item field for a "level up while holding X" check to
-- read, and a link trade is not a single-player route, so the row becomes
-- "the item is a tool you use on the Pokemon, gated on its level" -- exactly
-- how a native evolution stone already behaves, plus a level requirement.  The
-- item is consumed on success.
--
-- The row itself never fires from the engine's level-up walk: the trigger is
-- the item use, which items/evolution_items.lua performs (it scans the target
-- species for THIS method id + the used item, checks `mon.level`, and returns
-- `evolveTo`).  The `check` here is therefore deliberately inert -- it exists
-- because every row's method id must resolve to a registered evolution_methods
-- entry for cross-validation, and so a level-up never silently evolves a mon
-- that has not been handed the item.
return {
  install = function(_, ctx)
    ctx.patchMethod("G9_ITEM_LEVEL", {
      check = function() return false, "use-item" end,
      describe = function(evo)
        return "Use " .. tostring(evo.item or "the item")
          .. " at level " .. tostring(evo.level or 0)
      end,
    })
  end,
}
