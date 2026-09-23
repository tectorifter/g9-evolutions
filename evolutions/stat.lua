-- G9_STAT_<COMPARISON> -- the Tyrogue family: level up when attack vs defence
-- compares a given way.
--
-- Three ids, one per comparison the data can name (ATK_GT_DEF / ATK_LT_DEF /
-- ATK_EQ_DEF), because the row shape has no comparison field on Gen 1 and the
-- value belongs somewhere stable.  On Gen 2 the row ALSO carries
-- `comparison`, so the row is self-describing there too, but the check reads
-- the same method id on both generations -- one truth, not two.
--
-- The comparison is on the mon's CURRENT stats (engine's Tyrogue path compares
-- the live attack/defence values, not base stats or DVs), which is exactly
-- what mon.stats holds on both generations.
local ORDER = { "ATK_GT_DEF", "ATK_LT_DEF", "ATK_EQ_DEF" }

local function comparisonOf(mon)
  local stats = (type(mon) == "table" and mon.stats) or {}
  local attack, defense = stats.attack or 0, stats.defense or 0
  if attack == defense then return "ATK_EQ_DEF" end
  if attack < defense then return "ATK_LT_DEF" end
  return "ATK_GT_DEF"
end

return {
  ORDER = ORDER,

  install = function(mod, ctx)
    for _, comparison in ipairs(ORDER) do
      local check
      if ctx.gen == 2 then
        check = function(entry, mon, _)
          if ((mon and mon.level) or 1) < (entry.level or 0) then
            return false, "level"
          end
          if mon and mon.item == "EVERSTONE" then return false, "everstone" end
          if comparisonOf(mon) ~= comparison then return false, "stats" end
          return true
        end
      else
        check = function(_, mon, evo, trigger)
          if trigger and trigger.kind ~= "levelup" then return false end
          if (mon and mon.level or 1) < (evo.level or 0) then return false end
          return comparisonOf(mon) == comparison
        end
      end
      ctx.patchMethod("G9_STAT_" .. comparison, {
        check = check,
        describe = function() return "Level up (" .. comparison .. ")" end,
      })
    end
  end,
}
