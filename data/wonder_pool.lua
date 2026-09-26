-- data/wonder_pool.lua -- the wonder trade's pool: every species the running
-- game has registered, sorted into the five rarity brackets data/pity.lua
-- defines, plus the rule that turns a rolled ALTERNATE FORM into the base
-- Pokemon and the item that enables it.
--
-- THE POOL IS THE REGISTRY, NOT A LIST.  The running game registers a record
-- for every species AND every alternate form it knows -- the cart's own dex,
-- expanded by national_dex when that mod is installed (CHARIZARD,
-- CHARIZARD_MEGA_X, RAICHU_ALOLA, KOMMO_O_TOTEM, ...) -- so walking
-- `data.pokemon` really is the "all pokemon pool (including alternate forms)"
-- the request asks for: no second roster to keep in step, and no national_dex
-- needed (with it absent the pool is simply the cart's own species).  A record
-- without base stats or types is skipped rather than guessed at.
--
-- THE FORM RULE.  A battle TRANSFORMATION is never handed to a party slot as
-- itself; every one is turned back into the Pokemon a player can actually
-- keep, and the roll's answer says which rule fired:
--
--   * a MEGA form becomes its base species plus the Mega Stone that enables
--     it (a stone this install does not have is simply not handed over);
--   * a TOTEM becomes its base species plus the Z-Crystal that species is
--     known for (its signature crystal, else the crystal for its own type);
--   * a GIGANTAMAX form -- and Eternatus's ETERNAMAX -- becomes its base
--     species with its Gigantamax Factor ACTIVATED (`factor = true`),
--     because the Factor is exactly what this game's own G-FACTOR system
--     uses to turn a Gigantamax-capable species into one;
--   * a STELLAR / TERASTAL form (Terapagos's two battle formes, and the
--     terastallized spelling of any future species) becomes its base species
--     with nothing attached (`source` "stellar" / "terastal").
--
-- Everything else -- regional variants, the cosmetic forms -- is handed over
-- as rolled.  The item id tables are vendored beside this file
-- (data/form_items.lua); a national_dex new enough to publish itemFlags() is
-- asked first for a Mega Stone, so a form added after that table was
-- generated still resolves.
--
-- `factor = true` is a REQUEST, never a guarantee: the caller writes the
-- Factor through data/gigantamax_factor.lua's own eligibility gate, so a
-- G-max form of a species the engine will not let Gigantamax (Eternatus)
-- arrives as its plain base form with no Factor recorded.
--
-- This module owns no state and requires nothing: the rarity rules it needs
-- (data/pity.lua) arrive as the `pity` argument, wired by main.lua, the same
-- way evolutions/trade.lua is handed ctx.held.
local M = {}

-- The stat total a bracket reads.  national_dex publishes the real Gen 6
-- split (spAttack/spDefense on the RECORD, beside the cart's collapsed
-- `special` inside baseStats); a record with only `special` counts it as BOTH
-- special stats, which is the older Gen 1/2 shape.  Reading the split is what
-- makes the bracket agree with Bulbapedia's base-stat list -- Ogerpon is 550,
-- not 586.
--
-- THE "DOUBLE SPECIAL".  When no split exists -- a boot whose running dex was
-- registered without g9-battle-engine, or a cart record that only ever named
-- one `special` -- that ONE collapsed stat stands in for the modern pair, so
-- it is counted for BOTH halves.  It is not counted once and left low: the
-- request asks for the double exactly because the missing split has to be
-- priced in (Gen 1's Special is one stat where a modern species has two).
-- The read is adaptive to the field name a dex uses (`special` / `spc`,
-- inside baseStats or on the record, split or collapsed), so the bracket falls
-- out of whatever shape the running dex registers rather than a fixed roster.
function M.bst(record, gen)
  local b = record and record.baseStats
  if type(b) ~= "table" then return nil end
  local collapsed = b.special or b.spc or record.special or record.spc
  local spa = b.spAttack or b.specialAttack or record.spAttack
    or record.specialAttack
  local spd = b.spDefense or b.specialDefense or record.spDefense
    or record.specialDefense
  if type(spa) ~= "number" then spa = collapsed end
  if type(spd) ~= "number" then spd = collapsed end
  if type(b.hp) ~= "number" or type(b.attack) ~= "number"
      or type(b.defense) ~= "number" or type(b.speed) ~= "number"
      or type(spa) ~= "number" or type(spd) ~= "number" then
    return nil
  end
  return b.hp + b.attack + b.defense + b.speed + spa + spd
end

-- Every id that could be handed over, as { id = record }.  `pokemon` is the
-- engine's merged registry table (game.data.pokemon).  No form is filtered
-- out here: a battle-only record is turned back into the Pokemon a player
-- may keep by M.resolve below.
function M.records(pokemon)
  local out = {}
  if type(pokemon) ~= "table" then return out end
  for id, record in pairs(pokemon) do
    if type(id) == "string" and type(record) == "table" then
      out[id] = record
    end
  end
  return out
end

-- The pool: the bracket tables and the flat list, each entry
--   { species, name, bst, star, legendary, form, base }
-- `legendary` is a set keyed by species id (data/legendary.lua); a form is
-- legendary when its BASE species is, so a Mega of a restricted species
-- cannot fall into the non-legendary bracket.
--
-- `exclude(id, record)` is the caller's optional filter -- the wonder trade
-- hands in the BLACKLIST here, so a delisted species (or a delisted base's
-- forms) is simply absent from the pool and can never be drawn.  The filter is
-- read fresh at build time; ui/trade.lua rebuilds the pool on every trade
-- precisely so a window edit lands on the very next roll.
function M.build(pokemon, legendary, pity, exclude, gen)
  legendary = legendary or {}
  local pool = { byTier = { {}, {}, {}, {}, {} }, all = {} }
  for id, record in pairs(M.records(pokemon)) do
    if not (type(exclude) == "function" and exclude(id, record)) then
      local bst = M.bst(record, gen)
      if bst then
        local base = record.baseSpecies
        local legend = legendary[id] == true
          or (type(base) == "string" and legendary[base] == true)
        local star = pity and pity.speciesStar(bst, legend) or 1
        local entry = {
          species = id,
          name = record.name or id,
          bst = bst,
          star = star,
          legendary = legend,
          form = record.form,
          base = base,
        }
        pool.all[#pool.all + 1] = entry
        local list = pool.byTier[star]
        if list then list[#list + 1] = entry end
      end
    end
  end
  table.sort(pool.all, function(a, b) return a.species < b.species end)
  for _, list in ipairs(pool.byTier) do
    table.sort(list, function(a, b) return a.species < b.species end)
  end
  return pool
end

-- How many species a bracket holds in this install (a dex can have no
-- 5-star at all, which the picker has to survive).
function M.tierCount(pool, tier)
  local list = pool and pool.byTier and pool.byTier[tier]
  return type(list) == "table" and #list or 0
end

-- One entry from `tier`, or from the nearest non-empty bracket when that one
-- is empty -- so a small dex still answers rather than erroring.  `roll` is a
-- 0..1 the caller supplies, for reproducible tests.
function M.pick(pool, tier, roll)
  if type(pool) ~= "table" or type(pool.byTier) ~= "table" then return nil end
  local list = pool.byTier[tier]
  if not (type(list) == "table" and #list > 0) then
    local best, distance
    for t = 1, #pool.byTier do
      local candidate = pool.byTier[t]
      if type(candidate) == "table" and #candidate > 0 then
        local gap = math.abs(t - (tonumber(tier) or 1))
        if not distance or gap < distance then best, distance = candidate, gap end
      end
    end
    list = best
  end
  if not (type(list) == "table" and #list > 0) then return nil end
  roll = tonumber(roll) or math.random()
  local index = math.floor(roll * #list) + 1
  if index < 1 then index = 1 elseif index > #list then index = #list end
  return list[index]
end

-- ------------------------------------------------------------------ the item
local flagsIndex

-- A Showdown form name ("Charizard-Mega-X") and a national_dex form id
-- ("CHARIZARD_MEGA_X") are the same word punctuated differently.
function M.normalise(name)
  return (tostring(name):upper():gsub("[^A-Z0-9]", "_")
    :gsub("_+", "_"):gsub("^_", ""):gsub("_$", ""))
end

-- national_dex >= apiVersion 9 answer for a form's stone, by inverting its
-- own itemFlags().megaStone pairing over the catalogue.  Memoised (the walk
-- touches every item id once), and false once it is known to be unavailable.
local function stoneFromFlags(exports, formId)
  if type(exports) ~= "table" or type(exports.itemFlags) ~= "function"
      or type(exports.listItems) ~= "function" then
    return nil
  end
  if flagsIndex == nil then
    flagsIndex = {}
    local ok, ids = pcall(exports.listItems)
    if ok and type(ids) == "table" then
      for _, itemId in ipairs(ids) do
        local okF, flags = pcall(exports.itemFlags, itemId)
        if okF and type(flags) == "table"
            and type(flags.megaStone) == "table" then
          for _, formName in pairs(flags.megaStone) do
            if type(formName) == "string" then
              flagsIndex[M.normalise(formName)] = itemId
            end
          end
        end
      end
    end
    if next(flagsIndex) == nil then flagsIndex = false end
  end
  return flagsIndex and flagsIndex[formId] or nil
end

-- `entry` is a pool entry; `formItems` is data/form_items.lua; `exports` is
-- national_dex's (optional).  Returns { species, item, source, factor }:
--   species   the id the player actually receives
--   item      the enabling item id, or nil
--   source    "mega" | "totem" | "gmax" | "stellar" | "terastal" | nil
--   factor    true when the received mon should have its Gigantamax Factor
--             activated (a G-max / Etenamax downgrade); nil otherwise
--
-- The form id is matched by SUBSTRING because national_dex spells the same
-- battle form several ways ("GMAX", "AMPED_GMAX", "SINGLE_STRIKE_GMAX");
-- ETERNAMAX is its own word.  Read the header for the whole rule.
--
-- A rolled MEGA ALWAYS becomes its base species, whether or not a stone was
-- found: the request is "the player receives the non altern form of the
-- pokemon + the item", so handing over the battle-only Mega FORM when the
-- stone table has no row for it would be exactly the wrong answer.  The item
-- is the second half and may legitimately be missing (a dex older than the
-- stone table names no stone for a form); the DOWNGRADE is not optional.
local function hasForm(form, word)
  return type(form) == "string" and form:find(word, 1, true) ~= nil
end

function M.resolve(entry, formItems, exports)
  if type(entry) ~= "table" then return nil end
  local form = entry.form
  local base = entry.base or entry.species
  local species, item, source, factor = entry.species, nil, nil, nil
  if hasForm(form, "MEGA") then
    item = (formItems and formItems.MEGA_STONES
      and formItems.MEGA_STONES[entry.species])
      or stoneFromFlags(exports, entry.species)
    species = base
    source = "mega"
  elseif hasForm(form, "TOTEM") then
    item = formItems and formItems.SPECIES_CRYSTALS
      and formItems.SPECIES_CRYSTALS[base]
    species = base
    source = "totem"
  elseif hasForm(form, "GMAX") or form == "ETERNAMAX" then
    species = base
    source = "gmax"
    factor = true
  elseif hasForm(form, "STELLAR") then
    species = base
    source = "stellar"
  elseif hasForm(form, "TERASTAL") then
    species = base
    source = "terastal"
  end
  return { species = species, item = item, source = source, factor = factor }
end

-- The same answer with the registry in hand, so the totem fallback can read
-- the species' own first type when it has no signature crystal.  Kept
-- separate so resolve() stays a pure function of the entry.
function M.resolveWith(entry, formItems, pokemon, exports)
  local resolved = M.resolve(entry, formItems, exports)
  if not resolved then return nil end
  if resolved.source == "totem" and not resolved.item then
    local record = pokemon and pokemon[resolved.species]
    local first = record and record.types and record.types[1]
    if type(first) == "string" then
      resolved.item = formItems and formItems.TYPE_CRYSTALS
        and formItems.TYPE_CRYSTALS[first]
    end
  end
  return resolved
end

return M
