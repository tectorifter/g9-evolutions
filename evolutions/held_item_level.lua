-- G9_HELD_ITEM -- level up while HOLDING a particular item (Gen 2 only).
--
-- This is the Razor Claw / Razor Fang / Oval Stone family.  Gold has a real
-- held-item field (`mon.item`) for this to read; Red/Blue/Yellow has none, so
-- on Gen 1 the row-builder emits G9_ITEM_LEVEL (use the item on the mon once it
-- is high enough) instead and this operator is never referenced there.
--
-- The required item rides the row's own `item` field, which is the one place
-- the schema lets an evolution name an item, and is read back through the
-- generation-aware held-item accessor: `mon.item` on Gold, the `g9HeldItem`
-- mark on Red/Blue/Yellow (where items/evolution_items.lua's use effect puts
-- it, because that engine has no held-item field of its own).
return {
  install = function(mod, ctx)
    local Held = ctx.held
    local check
    if ctx.gen == 2 then
      check = function(entry, mon, _)
        if ((mon and mon.level) or 1) < (entry.level or 0) then
          return false, "level"
        end
        if mon and mon.item == "EVERSTONE" then return false, "everstone" end
        if not entry.item or (mon and mon.item) ~= entry.item then
          return false, "wrong item"
        end
        return true
      end
    else
      check = function(_, mon, evo, trigger)
        if trigger and trigger.kind ~= "levelup" then return false end
        if (mon and mon.level or 1) < (evo.level or 0) then return false end
        if not evo.item or Held.of(mon, 1) ~= evo.item then return false end
        return true
      end
    end
    ctx.patchMethod("G9_HELD_ITEM", {
      check = check,
      describe = function(evo)
        return "Level up holding " .. tostring(evo.item)
      end,
    })
  end,
}
