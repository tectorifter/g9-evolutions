-- data/blacklist.lua -- the species blacklist the WONDER TRADE honours, and the
-- one vocabulary the in-game BLACKLIST window is drawn from.
--
-- WHY THIS EXISTS.  g9-battle-sample ships an OPTIONS-menu BLACKLIST window
-- that filters ITS randomizer, and g9-gui re-skins that window.  The player's
-- request: the wonder trade must honour the same list, and g9-evolutions must
-- ALSO be able to offer the same OPTIONS button and window when g9-battle-
-- sample is not installed -- without ever showing a SECOND BLACKLIST row when
-- it is.  So this module owns the list only when it has to, and reads the
-- sample's list when the sample is the one showing the button.
--
-- ONE ARRAY OF IDS.  The list is stored under the key "blacklist" on the
-- save's per-mod bucket -- save.modData[<mod>].blacklist, the very table
-- mod.save is backed by (src.mods.Loader: `loader.modSave = save.modData`) --
-- which is exactly the shape g9-battle-sample writes and g9-gui reads.  That
-- one convention is what lets three mods share one list with no glue:
--   * g9-battle-sample installed -> ITS bucket is the active list (the sample
--     owns the button and every write), and this module only READS it, through
--     the same direct-modData read g9-gui's own blacklist skin uses;
--   * not installed -> this module OWNS the list in g9-evolutions' own bucket,
--     seeds the shipped default on first use, and g9-gui's skin still finds it
--     (its readSet scans every bucket for a "blacklist" array).
--
-- THE DEFAULT is every Mega and Gigantamax form, the same default the sample
-- ships.  A fresh install's wonder trade therefore cannot hand out a
-- battle-only Mega or Gigantamax form -- the round-13 form rule (deliver the
-- base + its enabling item / G-FACTOR) only ever runs for a form the player
-- has deliberately UN-blacklisted in the window.
--
-- THE SEMANTICS are the sample's, verbatim: delisting a BASE species hides its
-- forms too (delisting CHARIZARD hides CHARIZARD_MEGA_X); delisting a form
-- covers only that form; a generation cell delists that generation's whole
-- roster; the [MEGA] / [GIGA] cells flip a whole form group at once.  The list
-- is a FILTER ONLY -- nothing here ever touches a battle or a species record.
local M = {}

-- The key every participant stores the array under (see the header).
M.KEY = "blacklist"
-- The mod whose list wins when it is installed, and our own id (the fallback
-- for a caller whose `mod` has no `id`).
M.SAMPLE_ID = "g9-battle-sample"
M.OWN_ID = "g9-evolutions"

-- National-dex ranges -> generation.  A form is placed by its BASE species'
-- dex (a form record's own dex is synthetic), which is what makes the
-- generation filter and the 3x3 cell grid agree with the real games.
local GEN_RANGES = {
  { 1, 1, 151 }, { 2, 152, 251 }, { 3, 252, 386 }, { 4, 387, 493 },
  { 5, 494, 649 }, { 6, 650, 721 }, { 7, 722, 809 }, { 8, 810, 905 },
  { 9, 906, 1025 },
}
M.GEN_RANGES = GEN_RANGES
M.GEN_COUNT = #GEN_RANGES
M.LETTER_COUNT = 26

function M.generationOfDex(dex)
  dex = tonumber(dex)
  if not dex then return nil end
  for _, range in ipairs(GEN_RANGES) do
    if dex >= range[2] and dex <= range[3] then return range[1] end
  end
  return nil
end

-- Mega / Gigantamax are the two form GROUPS the window toggles at once, and
-- the two delisted by default.  Detected from the record's own `form` label,
-- which the merged registry spells "MEGA" / "MEGA_X" / "MEGA_Y" / "MEGA_Z"
-- (plus this project's own variants, e.g. "MALE_MEGA") and "GMAX" /
-- "..._GMAX"; the id suffix is the fallback for a record with no label.
-- Eternamax, Primal, Crowned and the regional variants are deliberately NOT
-- here: the request named Megas and Gigantamax only.  (This is the sample's
-- own formGroupOf, reproduced so both sides classify a form identically.)
function M.formGroupOf(id, rec)
  local form = type(rec) == "table" and rec.form
  if type(form) == "string" and form ~= "" then
    local f = form:upper()
    if f == "GMAX" or f:sub(-5) == "_GMAX" then return "gmax" end
    if f:find("MEGA", 1, true) then return "mega" end
  end
  if type(id) == "string" then
    local u = id:upper()
    if u:sub(-5) == "_GMAX" then return "gmax" end
    if u:sub(-5) == "_MEGA" or u:find("_MEGA_", 1, true) then return "mega" end
  end
  return nil
end

-- A form's own base species, read off the registry.  "" collapses to nil so a
-- record that spells "no base" as an empty string is not mistaken for one.
function M.baseOf(pokemon, id)
  local rec = type(pokemon) == "table" and pokemon[id] or nil
  local base = type(rec) == "table" and rec.baseSpecies or nil
  if base == "" then base = nil end
  return base
end

-- Every displayable species/form, as a name-sorted array of
--   { id, name, base, form, dex, group, gen }
-- The index is memoised per registry table (the registry does not change after
-- load), because every draw of the window walks it.
local indexCache = setmetatable({}, { __mode = "k" })
function M.buildIndex(pokemon)
  if type(pokemon) ~= "table" then return {} end
  local cached = indexCache[pokemon]
  if cached then return cached end
  local out = {}
  for id, rec in pairs(pokemon) do
    if type(id) == "string" and type(rec) == "table" then
      local name = rec.name
      if type(name) ~= "string" or name == "" then name = id end
      local base = type(rec.baseSpecies) == "string" and rec.baseSpecies or nil
      if base == "" then base = nil end
      -- A form is placed by its base species' dex (the record's own dex is
      -- synthetic for a form), the same rule the sample's own index uses.
      local dex = rec.baseDex
      if type(dex) ~= "number" and base then
        local parent = pokemon[base]
        if type(parent) == "table" and type(parent.dex) == "number" then
          dex = parent.dex
        end
      end
      if type(dex) ~= "number" then dex = rec.dex end
      out[#out + 1] = { id = id, name = name, base = base, form = base ~= nil,
        dex = dex, group = M.formGroupOf(id, rec),
        gen = M.generationOfDex(dex) }
    end
  end
  table.sort(out, function(a, b)
    local an, bn = a.name:upper(), b.name:upper()
    if an ~= bn then return an < bn end
    return tostring(a.id) < tostring(b.id)
  end)
  indexCache[pokemon] = out
  return out
end

-- The shipped default: every Mega and Gigantamax form the registry carries.
-- `nil` (never an empty list) when there is no registry yet, so a caller can
-- retry rather than persist an empty "default".
function M.defaults(pokemon)
  if type(pokemon) ~= "table" then return nil end
  local ids = {}
  for id, rec in pairs(pokemon) do
    if type(id) == "string" and M.formGroupOf(id, rec) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

-- A plain array -> a membership set.
function M.asSet(list)
  local set = {}
  for _, id in ipairs(list or {}) do
    if type(id) == "string" then set[id] = true end
  end
  return set
end

-- The one predicate the wonder trade consults: an id is delisted when it is in
-- the set itself OR when its base species is (a delisted species hides its own
-- forms too).
function M.isIn(set, pokemon, id)
  if type(id) ~= "string" or type(set) ~= "table" then return false end
  if set[id] == true then return true end
  local base = M.baseOf(pokemon, id)
  return base ~= nil and set[base] == true
end

-- A generation / form-group cell is "complete" only when every indexed id of
-- that bucket is delisted (its own id, or through a delisted base), so the
-- cell's check mark and its toggle always agree.
function M.genComplete(index, set, gen)
  if type(set) ~= "table" then return false end
  local any = false
  for _, entry in ipairs(index or {}) do
    if entry.gen == gen then
      any = true
      if not (set[entry.id] or (entry.base and set[entry.base])) then
        return false
      end
    end
  end
  return any
end

function M.formGroupComplete(index, set, group)
  if type(set) ~= "table" then return false end
  local any = false
  for _, entry in ipairs(index or {}) do
    if entry.group == group then
      any = true
      if not (set[entry.id] or (entry.base and set[entry.base])) then
        return false
      end
    end
  end
  return any
end

-- How many indexed ids the set holds -- the OPTIONS row's and the window's
-- "N HELD" figure.  Counted through the index, so a stale id left by an older
-- registry is not reported.
function M.heldCount(index, set)
  if type(set) ~= "table" then return 0 end
  local n = 0
  for _, entry in ipairs(index or {}) do
    if set[entry.id] then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------- persistence
-- Which mod owns the list on this install.  `mod.find` is the engine's peer
-- lookup; it answers nil for a mod that is absent, disabled, failed or has not
-- run yet -- and the OPTIONS hook this gates runs long after every mod loaded,
-- so by the time it matters the answer is settled.
function M.samplePresent(mod)
  if type(mod) ~= "table" or type(mod.find) ~= "function" then return false end
  -- Called as mod.find(id) (no self): the engine's own api.find accepts both
  -- that and mod:find(id), and the former is what a peer-stub answers.
  local ok, found = pcall(mod.find, M.SAMPLE_ID)
  return ok and found ~= nil
end

function M.ownId(mod)
  if type(mod) == "table" and type(mod.id) == "string" and mod.id ~= "" then
    return mod.id
  end
  if type(mod) == "table" and type(mod.manifest) == "table"
      and type(mod.manifest.id) == "string" then
    return mod.manifest.id
  end
  return M.OWN_ID
end

-- The ACTIVE array, or nil when none has ever been written.  Read-only: this
-- never writes and never seeds.  The sample's bucket wins while the sample is
-- installed (it owns the writes); otherwise our own bucket is preferred, and a
-- scan for any bucket carrying a "blacklist" array is the same last resort
-- g9-gui's skin uses (so a fork that renames the sample is still read).
function M.readList(mod, save)
  local modData = type(save) == "table" and save.modData or nil
  if type(modData) == "table" then
    if M.samplePresent(mod) then
      local bucket = modData[M.SAMPLE_ID]
      if type(bucket) == "table" and type(bucket[ M.KEY ]) == "table" then
        return bucket[ M.KEY ]
      end
      return nil
    end
    local own = modData[M.ownId(mod)]
    if type(own) == "table" and type(own[ M.KEY ]) == "table" then
      return own[ M.KEY ]
    end
    for _, bucket in pairs(modData) do
      if type(bucket) == "table" and type(bucket[ M.KEY ]) == "table" then
        return bucket[ M.KEY ]
      end
    end
    return nil
  end
  -- No live save in hand: our own mod.save is the one store we may read.
  if type(mod) == "table" and type(mod.save) == "table"
      and type(mod.save.get) == "function" then
    local ok, list = pcall(mod.save.get, mod.save, M.KEY)
    if ok and type(list) == "table" then return list end
  end
  return nil
end

-- Writes OUR OWN bucket.  Only ever reached when this mod owns the button (the
-- sample absent); while the sample is installed its own window does the
-- writing and this module stays read-only.
function M.writeList(mod, list)
  if type(mod) ~= "table" or type(mod.save) ~= "table"
      or type(mod.save.set) ~= "function" then
    return false
  end
  local ok = pcall(mod.save.set, mod.save, M.KEY, list)
  return ok == true
end

-- The set the WONDER TRADE filters by (and the window draws): the active list
-- when one exists, else the shipped default.  NEVER writes -- a default that
-- could not be persisted is still honoured for this trade.
function M.readSet(mod, save, pokemon)
  local list = M.readList(mod, save)
  if type(list) == "table" then return M.asSet(list) end
  local ids = M.defaults(pokemon)
  return ids and M.asSet(ids) or {}
end

-- The set the WINDOW owns: the active list, or the shipped default SEEDED and
-- persisted on first use.  A later RESET ALL persists an EMPTY array rather
-- than a nil one, so that deliberate reset is never re-seeded.
function M.ownedSet(mod, save, pokemon)
  local list = M.readList(mod, save)
  if type(list) == "table" then return M.asSet(list) end
  local ids = M.defaults(pokemon)
  if not ids then return {} end
  M.writeList(mod, ids)
  return M.asSet(ids)
end

-- ------------------------------------------------------------------- writes
-- One writer for every toggle: read the owned set, mutate it, persist it as a
-- sorted array (the same shape the sample writes).
local function mutate(mod, save, pokemon, fn)
  local set = M.ownedSet(mod, save, pokemon)
  fn(set, M.buildIndex(pokemon))
  local list = {}
  for id in pairs(set) do list[#list + 1] = id end
  table.sort(list)
  M.writeList(mod, list)
  return set
end

-- A base species carries its forms along (so the window's own rows and the
-- wonder trade agree); a form stands alone.  The flip is decided from the id
-- itself, once, so the whole group moves together.
function M.toggle(mod, save, pokemon, id)
  if type(id) ~= "string" then return end
  return mutate(mod, save, pokemon, function(set, index)
    local turnOn = not set[id]
    set[id] = turnOn and true or nil
    for _, entry in ipairs(index or {}) do
      if entry.base == id then set[entry.id] = turnOn and true or nil end
    end
  end)
end

function M.genToggle(mod, save, pokemon, gen)
  return mutate(mod, save, pokemon, function(set, index)
    local complete = M.genComplete(index, set, gen)
    for _, entry in ipairs(index or {}) do
      if entry.gen == gen then
        if complete then set[entry.id] = nil else set[entry.id] = true end
      end
    end
  end)
end

function M.formGroupToggle(mod, save, pokemon, group)
  if type(group) ~= "string" then return end
  return mutate(mod, save, pokemon, function(set, index)
    local complete = M.formGroupComplete(index, set, group)
    for _, entry in ipairs(index or {}) do
      if entry.group == group then
        if complete then set[entry.id] = nil else set[entry.id] = true end
      end
    end
  end)
end

function M.reset(mod, save, pokemon)
  return mutate(mod, save, pokemon, function(set)
    for id in pairs(set) do set[id] = nil end
  end)
end

return M
