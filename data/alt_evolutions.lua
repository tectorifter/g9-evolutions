-- The evolution rules the generic row builder cannot express, and the shared
-- vocabulary the item effects and the UI inspector read.
--
-- Three families live here:
--
--   * DAY / NIGHT STONES.  national_dex names a day or night window on a
--     level-up (Espeon at day, Umbreon at night, Rockruff's three forms, the
--     Amaura / Tyrunt / Yungoos pair, ...).  Red/Blue/Yellow has no clock at
--     all, and even Gold's window is easy to miss, so each of those routes
--     also gets a STONE: a day/morning route takes the Sun Stone, a
--     night/dusk route takes the Dusk Stone.  The stones are pure use-item
--     rows on both generations; a route that also demanded friendship keeps
--     demanding it (Espeon = Sun Stone + friendship, Umbreon = Dusk Stone +
--     friendship), because the stone replaces the missing clock, not the bond.
--
--   * THE ROCKRUFF LINE on Gen 1.  The data hangs Lycanroc-Midday and
--     Lycanroc-Midnight on the same level-25 row (day and night), and
--     Lycanroc-Dusk on the separate Own Tempo form.  With no clock, both
--     level rows would fire together and the first-listed would always win, so
--     on Red/Blue/Yellow the line is rebuilt explicitly: a plain level-up
--     yields Lycanroc-Midnight, the Sun Stone yields Midday, the Dusk Stone
--     yields Dusk.  The Dusk route is injected as a synthetic target because
--     the data hangs it on a form a normal Rockruff never is.
--
--   * THE GIMMIGHOUL CHARGE.  Gholdengo's own route ("level up carrying enough
--     Gimmighoul Coins") has no seam this engine can fire from, so using the
--     Gimmighoul Coin on a Gimmighoul adds ONE charge to a saved counter
--     (`mon.g9GimmighoulCharge`); at GIMMIGHOUL COST charges (20 by default)
--     the Pokemon evolves.  The coin is deliberately exclusive: it charges a
--     Gimmighoul and NOTHING else -- not a Gholdengo, not any other species --
--     and a re-entrancy mark stops a use that is already mid-evolution from
--     nesting another one.
local M = {}

-- ---------------------------------------------------------------- day / night

M.DAY_STONE = "sun-stone"
M.NIGHT_STONE = "dusk-stone"

-- The stone a route's time-of-day window stands for, or nil when the route
-- names no window (or a window neither stone covers).
function M.stoneForTime(method)
  if type(method) ~= "table" then return nil end
  local t = method.timeOfDay
  if t == "day" or t == "morning" then return M.DAY_STONE end
  if t == "night" or t == "dusk" then return M.NIGHT_STONE end
  return nil
end

-- A day/night level-up the generic builder can safely turn into (or pair with)
-- a stone route: a plain level-up that names a time window and carries no
-- OTHER condition the stone would silently drop.  A held-item or known-move
-- day route (Happiny's Oval Stone, Sneasel's Razor Claw) keeps its own system;
-- a regional route is the region items' job.
function M.stoneEligible(method)
  if type(method) ~= "table" then return false end
  if method.trigger ~= "level-up" then return false end
  if not M.stoneForTime(method) then return false end
  if method.region ~= nil then return false end
  if type(method.heldItem) == "string" then return false end
  if type(method.knownMove) == "string" then return false end
  if method.relativePhysicalStats ~= nil then return false end
  return true
end

-- ------------------------------------------------------------ Rockruff line

M.ROCKRUFF = "ROCKRUFF"
M.LYCANROC = "LYCANROC"
M.LYCANROC_MIDNIGHT = "LYCANROC_MIDNIGHT"
M.LYCANROC_DUSK = "LYCANROC_DUSK"
M.LEVEL = 25

-- The synthetic specs a generation's spec list must gain.  Gen 1 only: the
-- Dusk Stone route to Lycanroc-Dusk, which the dex hangs on the Own Tempo form.
function M.extraSpecs(gen, registered)
  if gen ~= 1 then return {} end
  if type(registered) == "function" and not registered(M.LYCANROC_DUSK) then
    return {}
  end
  return {
    {
      from = M.ROCKRUFF,
      target = M.LYCANROC_DUSK,
      targetName = "Lycanroc-Dusk",
      method = { trigger = "use-item", item = M.NIGHT_STONE },
    },
  }
end

-- The Rockruff line's explicit rows on Gen 1, keyed by the target the spec
-- names.  Answers a row list, or nil to let the generic path run (Gen 2, and
-- any species that is not Rockruff).
function M.override(spec, ctx)
  if type(spec) ~= "table" or type(ctx) ~= "table" then return nil end
  if ctx.gen ~= 1 or spec.from ~= M.ROCKRUFF then return nil end
  local target = spec.target
  if target == M.LYCANROC then
    -- the day form: the Sun Stone is the only route (plain level is Midnight)
    local item = ctx.itemId and ctx.itemId(M.DAY_STONE)
    if not item then return nil end
    return { { method = "ITEM", species = target, item = item } }
  end
  if target == M.LYCANROC_MIDNIGHT then
    local level = tonumber(spec.method and spec.method.level) or M.LEVEL
    return { { method = "G9_LEVEL", species = target, level = level } }
  end
  if target == M.LYCANROC_DUSK then
    local item = ctx.itemId and ctx.itemId(M.NIGHT_STONE)
    if not item then return nil end
    return { { method = "ITEM", species = target, item = item } }
  end
  return nil
end

-- ------------------------------------------------------------ Gimmighoul

M.GIMMIGHOUL = "GIMMIGHOUL"
M.CHARGE_FIELD = "g9GimmighoulCharge"

-- Is this the species the coin charges?  A prefix match so a future
-- GIMMIGHOUL_ROAMING form is included, and deliberately NOT a contains match:
-- "GHOLDENGO" must answer false, because the coin may never be used on the
-- thing a Gimmighoul becomes.
function M.isGimmighoul(species)
  if type(species) ~= "string" then return false end
  return species:sub(1, #M.GIMMIGHOUL) == M.GIMMIGHOUL
end

-- The saved charge on a mon, clamped to [0, max] so a corrupted or hand-edited
-- save can never push the counter past the threshold (which is what would make
-- a "keep charging" loop never terminate).
function M.chargeOf(mon, max)
  if type(mon) ~= "table" then return 0 end
  local n = tonumber(mon[M.CHARGE_FIELD])
  n = n and math.floor(n) or 0
  if n < 0 then n = 0 end
  if max and n > max then n = max end
  return n
end

-- The re-entrancy mark.  A coin use that reaches the threshold hands the
-- evolution to the engine, and the engine's own animation path can run the
-- item/level machinery again; the mark makes the nested call a no-op instead
-- of a second evolution, which is the "stack overflow" the charge could
-- otherwise create.  Weak keys, so a discarded party record is not pinned.
local EVOLVING = setmetatable({}, { __mode = "k" })

function M.markEvolving(mon)
  if type(mon) == "table" then EVOLVING[mon] = true end
  return mon
end

function M.clearEvolving(mon)
  if type(mon) == "table" then EVOLVING[mon] = nil end
  return mon
end

function M.isEvolving(mon)
  return type(mon) == "table" and EVOLVING[mon] == true
end

-- The target a Gimmighoul evolves into, read from the species' own evolution
-- rows (the row this mod emitted for the coin).  Two-argument: the row's item
-- so a species with several item rows answers the right one.
function M.evolveTargetOf(speciesDef, itemId)
  for _, evo in ipairs((speciesDef and speciesDef.evolutions) or {}) do
    if evo.item == itemId then
      return evo.species or evo.into
    end
  end
  return nil
end

return M
