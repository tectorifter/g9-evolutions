-- G9_HAPPINESS_<N> -- a friendship evolution.
--
-- One method id per threshold the data actually asks for (160 and 220 in the
-- current national_dex payload), so the exact number the evolution demands
-- lives in the id and the row stays schema-legal (its own record shape has no
-- `minHappiness` field).
--
-- Gold has a real per-Pokemon friendship value in `mon.happiness`, gained the
-- usual ways (berries, walking, levelling), and the check honours the day/night
-- window the row carries.  Red/Blue/Yellow has no friendship system at all, so
-- on that generation g9-evolutions keeps its own invisible value in
-- `mon.g9Happiness` (see main.lua's friendship tracker) and a mon starts at 70.
-- A mon whose record already carries a `happiness` -- Gold's shape, or a Gen 1
-- save another mod blessed -- is read from there on BOTH generations, so this
-- mod can never disagree with a real value that exists.
local DEFAULTS = { 160, 220 }

return {
  -- The tiers to register even when the data names neither, so the ids this mod
  -- documents always resolve.
  DEFAULTS = DEFAULTS,

  install = function(mod, ctx, need)
    local values = {}
    for _, n in ipairs(DEFAULTS) do values[n] = true end
    for n in pairs((need and need.happiness) or {}) do values[n] = true end

    local function friendshipOf(mon)
      if type(mon) ~= "table" then return 0 end
      local value = tonumber(mon.happiness)
      if value then return value end
      value = tonumber(mon.g9Happiness)
      if value then return value end
      return 70
    end
    -- Published so main.lua's tracker and the tests read the exact same value
    -- the checks do.
    ctx.friendshipOf = friendshipOf

    for n in pairs(values) do
      local threshold = math.floor(n)
      local id = "G9_HAPPINESS_" .. tostring(threshold)
      local check
      if ctx.gen == 2 then
        check = function(entry, mon, context)
          if friendshipOf(mon) < threshold then return false, "happiness" end
          if mon and mon.item == "EVERSTONE" then return false, "everstone" end
          local window = entry.time or "ANYTIME"
          local timeOfDay = context and context.timeOfDay
          local night = timeOfDay == "NITE" or timeOfDay == "NITE_F"
          if window == "NITE" and not night then return false, "daytime" end
          if window == "MORNDAY" and night then return false, "night" end
          return true
        end
      else
        check = function(_, mon, _evo, trigger)
          if trigger and trigger.kind ~= "levelup" then return false end
          return friendshipOf(mon) >= threshold
        end
      end
      ctx.patchMethod(id, {
        check = check,
        describe = function() return "Friendship " .. tostring(threshold) end,
      })
    end
  end,
}
