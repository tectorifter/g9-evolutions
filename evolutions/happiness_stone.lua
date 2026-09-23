-- G9_HAPPINESS_STONE_<N> -- a friendship evolution reached by USING a stone.
--
-- The day/night friendship routes (Eevee into Espeon and Umbreon, Budew,
-- Riolu, Chingling, Snom) normally fire on a level-up inside the data's
-- time-of-day window.  Red/Blue/Yellow has no clock, and Gold's window is easy
-- to miss, so the row builder also emits a stone route: the Sun Stone for a
-- day route, the Dusk Stone for a night route, still gated on the friendship
-- the data demands (Espeon = Sun Stone + friendship).
--
-- This file owns that route on GOLD, where the engine's own stone machinery
-- reaches it: the stone's use calls Evolution.checkMon with `force = true` and
-- the stone in hand, and Gold's rowMatches runs a method whose record declares
-- `requiresForce` (see src/core/gen2/Evolution.lua).  So this check reads the
-- stone the row names from `ctx.item`, honours the forced-use gate and the
-- friendship threshold, and -- being a real method -- lets the engine play its
-- own evolution animation and consume the stone exactly as a native stone
-- would.
--
-- On Red/Blue/Yellow the row reuses the engine's own ITEM operator instead
-- (its stone picker keys off that spelling), so this method is not referenced
-- there and is not registered -- see data/row_builder.lua and
-- items/evolution_items.lua's Gen 1 happiness gate.
local DEFAULTS = { 160, 220 }

return {
  DEFAULTS = DEFAULTS,

  install = function(_, ctx, need)
    if ctx.gen ~= 2 then return end

    local function friendshipOf(mon)
      if type(mon) ~= "table" then return 0 end
      local value = tonumber(mon.happiness)
      if value then return value end
      value = tonumber(mon.g9Happiness)
      if value then return value end
      return 70
    end

    local thresholds = {}
    for n in pairs((need and need.happinessStones) or {}) do
      thresholds[math.floor(n)] = true
    end
    -- Nothing to register when no day/night friendship route made it into the
    -- payload, but the two documented tiers stay available so a future dex
    -- that adds one only has to emit the row.
    if next(thresholds) == nil then
      for _, n in ipairs(DEFAULTS) do thresholds[n] = true end
    end

    for n in pairs(thresholds) do
      local threshold = math.floor(n)
      local id = "G9_HAPPINESS_STONE_" .. tostring(threshold)
      ctx.patchMethod(id, {
        requiresForce = true,
        check = function(entry, mon, context)
          if entry.item and context and context.item ~= entry.item then
            return false, "wrong item"
          end
          if not (context and context.force) then return false, "not forced" end
          if friendshipOf(mon) < threshold then return false, "happiness" end
          if mon and mon.item == "EVERSTONE" then return false, "everstone" end
          return true
        end,
        describe = function()
          return "Use a stone (friendship " .. tostring(threshold) .. ")"
        end,
      })
    end
  end,
}
