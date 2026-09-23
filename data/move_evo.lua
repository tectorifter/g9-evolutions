-- NO MOVE EVO -- the level a known-move evolution turns into.
--
-- The "hint" family (Aipom, Tangela, Yanma, Piloswine, ...) evolves by leveling
-- up while it KNOWS a particular move.  With the NO MOVE EVO option on, that
-- requirement is replaced by a plain level-up: the Pokemon evolves once it has
-- reached the level at which its own learn-by-level learnset teaches the move,
-- plus one -- a move learned at 40 is an evolution at 41.
--
-- This module answers exactly one question for the row builder: given the
-- species that evolves and the move the data names, what level is that?  It is
-- pure -- it reads national_dex's own records and never mutates anything -- and
-- it is memoized, so the needs pass (which move methods to register) and the
-- row builder (which rows to emit) ask the same question and get the same
-- answer.
--
-- WHAT COUNTS AS "THE LEARNSET"
--   `movesFull`, the COMPLETE modern level-up learnset national_dex publishes
--   (the same table its MOVES=ALL widening reads), so a modern move no cart
--   teaches natively still has a level.  A record with no extras falls back to
--   the native `learnset` (Red/Blue/Yellow) / `levelMoves` (Gold).  A move that
--   appears more than once -- a level-1 relearn row beside a later one -- takes
--   the LOWEST level, because that is the first level the mon can have it.
--
-- WHEN THE MOVE IS NOT IN THE LEARNSET AT ALL
--   The level falls back to the shape of the line, the user's rule:
--     25  the first step of a three-stage line
--     30  a two-stage line (Scyther)
--     35  the last step of a three-stage line (the middle species, e.g.
--         Piloswine or Steenee)
--   A chain that cannot be read at all answers nil, and the row builder then
--   leaves the known-move requirement in place -- reachable-and-later is
--   better than an evolution with no condition at all.
local M = {}

M.FIRST_STAGE = 25
M.TWO_STAGE = 30
M.LAST_STAGE = 35

-- The id a move is compared under: uppercased, every non-alphanumeric character
-- dropped.  `movesFull` rows carry both the separator-free `move` id and the
-- PokeAPI `slug`, so either one can be matched against the slug the evolution
-- data names.
local function bare(value)
  if type(value) ~= "string" then return nil end
  return (value:upper():gsub("[^%u%d]", ""))
end

-- The lowest level this learnset teaches the move at, or nil.
local function lowestLevel(list, slug)
  local target = bare(slug)
  if not target or type(list) ~= "table" then return nil end
  local found
  for _, row in ipairs(list) do
    if type(row) == "table"
        and (row.slug == slug or bare(row.move) == target) then
      local level = tonumber(row.level) or 1
      if not found or level < found then found = level end
    end
  end
  return found
end

-- One resolver over one national_dex install.  Returns a function
-- (fromSpeciesId, moveSlug) -> level or nil.
function M.resolver(exports)
  exports = type(exports) == "table" and exports or {}
  local levels, shapes = {}, {}

  -- The line's shape: the species' own depth (`stage`) and the number of
  -- stages in the whole family.  The chain is walked rather than trusted to be
  -- linear, so a branching family (Applin's) reports three stages, not five.
  local function shapeOf(id)
    if shapes[id] ~= nil then return shapes[id] end
    local value = false
    if type(exports.evolutionsOf) == "function" then
      local ok, record = pcall(exports.evolutionsOf, id)
      if ok and type(record) == "table" then
        local stage = tonumber(record.stage) or 1
        local total = stage
        for _, member in ipairs(type(record.chain) == "table"
            and record.chain or {}) do
          local ok2, memberRecord = pcall(exports.evolutionsOf, member)
          local depth = ok2 and type(memberRecord) == "table"
            and tonumber(memberRecord.stage) or nil
          if depth and depth > total then total = depth end
        end
        value = { stage = stage, total = total }
      end
    end
    shapes[id] = value
    return value
  end

  local function defaultLevel(id)
    local shape = shapeOf(id)
    if not shape then return nil end
    if shape.total >= 3 then
      if shape.stage <= 1 then return M.FIRST_STAGE end
      return M.LAST_STAGE
    end
    return M.TWO_STAGE
  end

  return function(from, move)
    if type(from) ~= "string" or type(move) ~= "string" or move == "" then
      return nil
    end
    local key = from .. "\0" .. move
    local cached = levels[key]
    if cached ~= nil then return cached or nil end
    local level = nil
    if type(exports.statsBySpecies) == "function" then
      local ok, record = pcall(exports.statsBySpecies, from)
      if ok and type(record) == "table" then
        local learned = lowestLevel(record.movesFull, move)
          or lowestLevel(record.learnset, move)
          or lowestLevel(record.levelMoves, move)
        if learned then level = learned + 1 end
      end
    end
    -- The move is not in the learnset (or there is no learnset): the line's
    -- shape decides.  Only a shape we cannot read at all leaves this nil.
    if not level then level = defaultLevel(from) end
    levels[key] = level or false
    return level
  end
end

return M
