-- G9_TRADE_LEVEL -- the single-player alternative to a trade evolution.
--
-- The engine already owns the real trade operator (`TRADE` on Gen 1,
-- `EVOLVE_TRADE` on Gen 2) and the row-builder emits that row unchanged, so a
-- genuine link trade keeps working exactly as before.  This method is emitted
-- as a SECOND row for the same target and fires on a level-up at the TRADE
-- LEVEL option (40 by default) or higher, which is what makes Kadabra,
-- Machoke, Graveler, Haunter, Onix, Scyther, Seadra, Porygon and the whole
-- item-trade family reachable without a second Game Boy.
--
-- A trade that demands a held item still demands it: `item` rode onto this row
-- too, and the check reads it through the generation-aware held-item accessor
-- (mon.item on Gold, the g9HeldItem mark on Red/Blue/Yellow).  The item is
-- deliberately NOT consumed on this route -- the engine's trade path owns
-- consumption, and an alternative route that quietly ate an item the player
-- never traded would be a worse surprise than leaving it on.
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
        if entry.item and (mon and mon.item) ~= entry.item then
          return false, "item"
        end
        return true
      end
    else
      check = function(_, mon, evo, trigger)
        if trigger and trigger.kind ~= "levelup" then return false end
        if (mon and mon.level or 1) < (evo.level or 0) then return false end
        if evo.item and Held.of(mon, 1) ~= evo.item then return false end
        return true
      end
    end
    ctx.patchMethod("G9_TRADE_LEVEL", {
      check = check,
      describe = function(evo)
        return "Level " .. tostring(evo.level or 0)
      end,
    })
  end,
}
