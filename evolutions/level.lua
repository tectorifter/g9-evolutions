-- G9_LEVEL -- a plain level-up evolution.
--
-- This is the mod's own replacement for the engine's LEVEL / EVOLVE_LEVEL
-- operator, so the mod is the one answering every level evolution it built a
-- row for.  The semantics are the engine's (level >= the row's level; on Gen 2
-- an Everstone still blocks it), and the row order the engine walks is
-- unchanged -- the first matching row wins.
return {
  -- Called once by main.lua with the install context (gen, options, helpers).
  install = function(mod, ctx)
    local check
    if ctx.gen == 2 then
      -- Gold's registerInto signature: check(entry, mon, ctx).
      check = function(entry, mon, _)
        if ((mon and mon.level) or 1) < (entry.level or 0) then
          return false, "level"
        end
        if mon and mon.item == "EVERSTONE" then return false, "everstone" end
        return true
      end
    else
      -- Gen 1's pendingFor signature: check(game, mon, evo, trigger).
      check = function(_, mon, evo, trigger)
        if trigger and trigger.kind ~= "levelup" then return false end
        return (mon and mon.level or 1) >= (evo.level or 0)
      end
    end
    ctx.patchMethod("G9_LEVEL", {
      check = check,
      describe = function(evo) return "Level " .. tostring(evo.level or 0) end,
    })
  end,
}
