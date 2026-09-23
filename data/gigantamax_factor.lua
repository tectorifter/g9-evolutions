-- The Gigantamax Factor item, and the wording/rate of the PC conversion that
-- mints it from Dynamax Candies.
--
-- WHY THIS IS A DATA MODULE AND NOT PART OF items/.  national_dex's evolution
-- data never names this item -- it triggers no evolution at all -- so it has no
-- place in the SLUGS vocabulary data/item_ids.lua builds.  What it DOES have is
-- a vocabulary of its own: the engine id it registers under, its display name,
-- the Dynamax Candy it is minted from, the exchange rate and the PC row's own
-- wording.  TWO installers read that vocabulary -- items/gigantamax_factor.lua
-- (the item) and ui/pc_maxfactor.lua (the row) -- so it lives in one copy here
-- where the two cannot drift into printing one number while spending another.
--
-- The item's display name is the one asked for, "G-FACTOR".  The PC row and
-- its question speak of "MAX-FACTOR", which is the wording given for the
-- conversion itself; both spellings are kept exactly as written.
local M = {}

-- national_dex's separator-free uppercase id spelling -- the same convention
-- items/evolution_items.lua registers under.
M.ITEM_ID = "GIGANTAMAXFACTOR"
M.NAME = "G-FACTOR"

-- The item the Factor is minted from.  This is battle_forms' Dynamax Candy,
-- whose id the engine already carries (battle_forms' own src/dynamaxlevel.lua
-- registers DYNAMAX_CANDY / "MAX CANDY"), so the PC row spends the very candy
-- a player feeds their Pokemon.
M.CANDY_ID = "DYNAMAX_CANDY"
M.CANDY_NAME = "MAX CANDY"

-- Ten candies per Factor, the rate asked for.
M.COST = 10

-- The PC row's own wording.  The question is paged with \f (the engine's own
-- "wait for A, clear" marker) because it is longer than the dialogue box's two
-- visible lines; the box is the engine's shared TextBox, which draws correctly
-- on both generations.
M.PC_LABEL = "MAX-FACTOR"
M.PC_QUESTION = "You want to convert\n10 max candies into\f1 MAX-FACTOR?"

-- The bag price.  This item is meant to be MINTED at the PC, never bought, so
-- the figure never reaches a shelf -- but the items schema requires one, and
-- 1000 is what every other item this mod registers uses.
M.PRICE = 1000

-- The Gigantamax-capable species, as the FALLBACK for a build without
-- g9-battle-engine: the engine's own isGigantamaxEligibleSpecies is the real
-- answer and is asked first, and this list only has to agree with it.  Mirrors
-- g9-battle-engine's gigantamax/gmax_data.lua `order` (the 33 species with a
-- Gigantamax form; Eternatus is deliberately absent there and here).
M.ELIGIBLE = {
  VENUSAUR = true, CHARIZARD = true, BLASTOISE = true, BUTTERFREE = true,
  PIKACHU = true, MEOWTH = true, MACHAMP = true, GENGAR = true, KINGLER = true,
  LAPRAS = true, EEVEE = true, SNORLAX = true, GARBODOR = true, MELMETAL = true,
  RILLABOOM = true, CINDERACE = true, INTELEON = true, CORVIKNIGHT = true,
  ORBEETLE = true, DREDNAW = true, COALOSSAL = true, FLAPPLE = true,
  APPLETUN = true, SANDACONDA = true, TOXTRICITY = true, CENTISKORCH = true,
  HATTERENE = true, GRIMMSNARL = true, ALCREMIE = true, COPPERAJAH = true,
  DURALUDON = true, URSHIFU = true, ELDEGOSS = true,
}

-- Whether `species` can Gigantamax.  The engine's own gate is authoritative and
-- is asked first (it also resolves alt forms through national_dex); the local
-- list is only the fallback for a build where g9-battle-engine is not loaded.
function M.isEligible(mod, species)
  if type(species) ~= "string" then return false end
  local eng = mod and mod.find and mod.find("g9-battle-engine")
  local api = eng and eng.exports
  if api and type(api.isGigantamaxEligibleSpecies) == "function" then
    local ok, value = pcall(api.isGigantamaxEligibleSpecies, species)
    if ok then return value == true end
  end
  return M.ELIGIBLE[species] == true
end

-- Whether `mon` already carries the Factor.  Read (and written) through the
-- engine's own exported accessors when it has them -- its dynamax_state.lua
-- stores a bare `mon.gigantamaxFactor = true` (nil when false), which is the
-- fallback for a build without those exports.
function M.hasFactor(mod, mon)
  if type(mon) ~= "table" then return false end
  local eng = mod and mod.find and mod.find("g9-battle-engine")
  local api = eng and eng.exports
  if api and type(api.getGigantamaxFactor) == "function" then
    local ok, value = pcall(api.getGigantamaxFactor, mon)
    if ok then return value == true end
  end
  return mon.gigantamaxFactor == true
end

-- Grants `mon` the Factor.  The engine's setter first, the bare field as the
-- fallback; answers true unless there is no mon to write to.
function M.setFactor(mod, mon)
  if type(mon) ~= "table" then return false end
  local eng = mod and mod.find and mod.find("g9-battle-engine")
  local api = eng and eng.exports
  if api and type(api.setGigantamaxFactor) == "function" then
    local ok = pcall(api.setGigantamaxFactor, mon, true)
    if ok then return true end
  end
  mon.gigantamaxFactor = true
  return true
end

return M
