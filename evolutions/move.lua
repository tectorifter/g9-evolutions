-- G9_KNOWN_MOVE_<MOVE> -- level up while the Pokemon knows a particular move.
--
-- The Ancient Power / Mimic / Rollout / Stomp family.  One id per move the
-- data names (15 in the current payload), so the move lives in the id without
-- the row needing a field for it -- the evolution record shape has none.
--
-- Move ids are spelled differently per generation (Red calls Ancient Power
-- ANCIENTPOWER, Gold calls it ANCIENT_POWER), and the two id spaces only
-- differ by separators for every move national_dex names here.  Rather than
-- carry a translation table, the check accepts BOTH spellings from the
-- Pokemon's moveset, so it matches on whichever generation is running and on
-- either spelling a peer mod might have registered.
return {
  install = function(mod, ctx, need)
    local function accepted(slug)
      local bare = (slug:upper():gsub("[^%u%d]", ""))
      local underscored = (slug:upper():gsub("[^%u%d]", "_"))
      return bare, underscored
    end

    local function knows(mon, slug)
      if type(mon) ~= "table" then return false end
      local bare, underscored = accepted(slug)
      for _, move in ipairs(mon.moves or {}) do
        local id = type(move) == "table" and move.id or nil
        if id == bare or id == underscored then return true end
      end
      return false
    end

    local registered = 0
    for slug in pairs((need and need.moves) or {}) do
      if type(slug) == "string" and slug ~= "" then
        local id = "G9_KNOWN_MOVE_" .. (slug:upper():gsub("[^%u%d]", ""))
        local check
        if ctx.gen == 2 then
          check = function(entry, mon, _)
            if ((mon and mon.level) or 1) < (entry.level or 0) then
              return false, "level"
            end
            if mon and mon.item == "EVERSTONE" then
              return false, "everstone"
            end
            if not knows(mon, slug) then return false, "move" end
            return true
          end
        else
          check = function(_, mon, evo, trigger)
            if trigger and trigger.kind ~= "levelup" then return false end
            if (mon and mon.level or 1) < (evo.level or 0) then return false end
            return knows(mon, slug)
          end
        end
        ctx.patchMethod(id, {
          check = check,
          describe = function() return "Level up knowing " .. slug end,
        })
        registered = registered + 1
      end
    end
    if registered == 0 then
      if ctx.noMoveEvo then
        -- NO MOVE EVO turned every known-move evolution into a plain level-up,
        -- so there is simply nothing for this unit to register -- not a
        -- problem, and not the "dex data had none" warning below.
        mod.log:info("g9-evolutions: NO MOVE EVO is on -- every known-move "
          .. "evolution is a plain level-up, so no G9_KNOWN_MOVE_* methods "
          .. "are needed")
      else
        mod.log:warn("g9-evolutions: no known-move evolutions were found in the "
          .. "dex data -- no G9_KNOWN_MOVE_* methods registered")
      end
    end
  end,
}
