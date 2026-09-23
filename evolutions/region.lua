-- G9_REGION_<REGION> -- the mod's headline operator: a regional form is chosen
-- by HOLDING that region's item through a level-up.
--
-- The three items are PRIMALAMBER (Hisui), SOVEREIGNCROWN (Galar) and
-- SOLSTICENECTAR (Alola).  A mon holding one of them that reaches the row's
-- level evolves into that region's variant; a mon without one evolves the
-- ordinary way (or not at all), because the region row simply does not fire.
-- Because the region rows are emitted FIRST among a species' rows, the engine's
-- first-match walk makes the item the tie-break between "Samurott" and
-- "Samurott-Hisui" -- exactly the choice the item exists to express.
--
-- On Gold the item is a real held item (`mon.item`, given through the party
-- menu).  On Red/Blue/Yellow the item is placed on the mon with a USE effect
-- (items/regional_items.lua) and read back through the g9HeldItem mark; it is
-- never consumed, so the same Amber can carry a whole team up their lines.
local REGIONS = { "hisui", "galar", "alola" }

return {
  REGIONS = REGIONS,

  install = function(mod, ctx)
    local Held = ctx.held
    for _, region in ipairs(REGIONS) do
      local itemId = ctx.regionItems[region]
      local check
      if ctx.gen == 2 then
        check = function(entry, mon, _)
          if ((mon and mon.level) or 1) < (entry.level or 0) then
            return false, "level"
          end
          if mon and mon.item == "EVERSTONE" then return false, "everstone" end
          if (mon and mon.item) ~= itemId then return false, "region item" end
          return true
        end
      else
        check = function(_, mon, evo, trigger)
          if trigger and trigger.kind ~= "levelup" then return false end
          if (mon and mon.level or 1) < (evo.level or 0) then return false end
          return Held.of(mon, 1) == itemId
        end
      end
      ctx.patchMethod("G9_REGION_" .. region:upper(), {
        check = check,
        describe = function() return "Hold " .. tostring(itemId) end,
      })
    end
  end,
}
