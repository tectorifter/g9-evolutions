-- trades/wonder.lua -- one WONDER TRADE, end to end, with no window in it.
--   * pick()   rolls the bracket (through data/pity.lua's pity clock), picks a
--              pool entry, resolves an alternate form into its base Pokemon
--              (+ its enabling item, or its Gigantamax Factor), rolls six
--              modern IVs, and BUILDS the received Pokemon -- touching nothing.
--   * commit() then does the party swap, the Pokedex tick, the held item and
--              the pity counters.
--
-- WHY THE SPLIT.  The trade animation has to show the Pokemon the player is
-- ABOUT to receive, so it must exist before the swap; and a split pick/commit
-- means the whole roll is assertable in tools/verify.lua with an injected
-- random and no engine at all.
--
-- THE GIGANTAMAX FACTOR.  A rolled Gigantamax form is delivered as its base
-- species (data/wonder_pool.lua's rule) and this file then asks the caller's
-- `setFactor(mon, species)` to switch the Factor on -- so a Gigantamax-capable
-- species arrives ready to Gigantamax, exactly as if its G-FACTOR had been
-- used on it.  The caller owns eligibility (data/gigantamax_factor.lua), so a
-- form of a species the engine will not let Gigantamax is simply its base
-- form.  `pick` reports `factor = true` only when the write actually landed.
--
-- THE LEVEL.  The received Pokemon arrives at the level of the one the player
-- traded away -- the request never names a level, and a fixed one would either
-- hand out a Level 5 Legendary or a Level 70 Caterpie.  Matching keeps the
-- swap neutral: what you put in is the size of what you get.
--
-- THE TWO GENES, ONE RUNG.  The request gives the rarity outright (+1 star
-- 50%, +2 star 44.3%, +3 star 5.1%, +4 star 0.6%), so the RUNG is rolled first
-- (through data/pity.lua) and BOTH gene blocks are then GENERATED to total
-- inside that rung's range:
--
--   * `mon.ivs` -- the six modern 0-31 IVs g9-battle-engine reads (the rung's
--     range is 86-128 / 129-171 / 172-185 / 186 raw);
--   * `mon.dvs` -- the cart's own 0-15 DVs, on ITS generation's scale, because
--     a boot with no battle engine has no IV block at all and the DVs are the
--     only genes that exist.  Gen 2 scores the split special (its maximum is
--     90); Gen 1's two special stats share one DV, so its maximum is the 80
--     the request names (data/pity.lua owns both ladders).
--
-- The two blocks are rolled INDEPENDENTLY from the same rung, exactly as the
-- request asks ("it also does the same it did for IV but for DV"): each is
-- therefore its own rung's rarity to the letter, rather than one being a
-- rounding of the other.  A HARD-PITY pull is rung +4 on both ladders -- a
-- perfect IV set (all 31) and a perfect DV set (all 15).
local M = {}

-- ------------------------------------------------------------------- random
-- The engine's own `random(a, b)` shape (`love.math.random` under LÖVE, with a
-- plain fallback), so a test can hand in a deterministic stub.
function M.rng()
  local lib = (love and love.math and love.math) or math
  return function(a, b)
    if b ~= nil then return lib.random(a, b) end
    return lib.random()
  end
end

local function dvOf(iv)
  return math.floor((tonumber(iv) or 0) * 15 / 31 + 0.5)
end

-- --------------------------------------------------------------------- pool
-- The pool is built once per game (data/wonder_pool.lua walks the whole
-- registry) and handed in; nil means "nothing to trade with".
function M.ready(pool)
  return type(pool) == "table" and type(pool.byTier) == "table"
    and type(pool.all) == "table" and #pool.all > 0
end

-- ---------------------------------------------------------------------- IVs
function M.ivsFor(rng, perfect)
  local keys = { "hp", "atk", "def", "spa", "spd", "spe" }
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = perfect and 31 or rng(0, 31)
  end
  return out
end

function M.ivTotal(ivs)
  local total = 0
  for _, key in ipairs({ "hp", "atk", "def", "spa", "spd", "spe" }) do
    total = total + (tonumber(ivs and ivs[key]) or 0)
  end
  return total
end

-- ------------------------------------------------------------------- build
-- `ivs` and `dvs` are the two gene blocks the roll produced; they are applied
-- to whatever the engine's own builder made.  The DVs are written first, then
-- the stat block is recomputed through the generation's own stat function, so
-- the figures really follow the cart's genes on a boot with no
-- g9-battle-engine; the modern `ivs`/`evs` block is stamped too, and
-- `modernStatsInitialized` tells that mod's .initialize/.ensure not to
-- randomise over them.  A caller that passes no `dvs` (an older one) still
-- gets the faithful conversion of `ivs`.
function M.build(opts, species, level, ivs, dvs, item)
  local data = opts.data
  local def = data and data.pokemon and data.pokemon[species]
  if not def then return nil end
  level = math.max(1, tonumber(level) or 1)
  dvs = dvs or {
    attack = dvOf(ivs.atk), defense = dvOf(ivs.def),
    speed = dvOf(ivs.spe),
    special = dvOf(math.floor((ivs.spa + ivs.spd) / 2 + 0.5)),
  }
  local mon
  if opts.gen == 2 then
    local Mon = require("src.battle.gen2.Mon")
    mon = Mon.new(data, species, level, {
      dvs = dvs,
      item = item,
      -- A traded mon is a DIFFERENT trainer's, and Gold's own trade path marks
      -- it so it earns the boosted experience (engine/battle/experience.asm:69).
      happiness = 70,
    })
    if mon then
      -- Only a caller with no HP DV gets the cart's own parity derivation; a
      -- rolled set carries its own HP (the request's DV ladder counts it).
      if dvs.hp == nil then dvs.hp = Mon.hpDV(dvs) end
      mon.dvs = dvs
    end
  else
    local Pokemon = require("src.pokemon.Pokemon")
    mon = Pokemon.new(data, species, level, opts.rng)
    if mon then mon.dvs = dvs end
  end
  if not mon then return nil end

  mon.ivs = { hp = ivs.hp, atk = ivs.atk, def = ivs.def,
              spa = ivs.spa, spd = ivs.spd, spe = ivs.spe }
  mon.evs = mon.evs or { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  mon.modernStatsInitialized = true
  mon.traded = true
  -- The species' display copy follows the species in a form record; a builder
  -- that does not already carry `name` (Gen 1's) gets it here.
  if mon.name == nil then mon.name = def.name or species end
  M.restat(mon, opts.gen, data, def)
  return mon
end

-- Recompute the cart's own stat block from `mon.dvs`.  Gen 2's Mon.refreshStats
-- also keeps `maxHp` in step and clamps a current HP that the new maximum no
-- longer covers.
function M.restat(mon, gen, data, def)
  def = def or (data and data.pokemon and data.pokemon[mon.species])
  if not def then return mon end
  if gen == 2 then
    local ok, Mon = pcall(require, "src.battle.gen2.Mon")
    if ok and type(Mon) == "table" and type(Mon.refreshStats) == "function" then
      pcall(Mon.refreshStats, mon, data)
      return mon
    end
    local base = def.baseStats or {}
    local specialDv = mon.dvs.special or 0
    local hpDv = ((mon.dvs.attack or 0) % 2) * 8
      + ((mon.dvs.defense or 0) % 2) * 4
      + ((mon.dvs.speed or 0) % 2) * 2 + (specialDv % 2)
    local function stat(key, dv)
      local base2 = base[key] or base.special or 1
      return math.floor(((base2 * 2 + (dv or 0) * 2) * mon.level) / 100) + 5
    end
    mon.stats = {
      hp = math.floor(((base.hp or 1) * 2 + hpDv * 2) * mon.level / 100)
        + mon.level + 10,
      attack = stat("attack", mon.dvs.attack),
      defense = stat("defense", mon.dvs.defense),
      speed = stat("speed", mon.dvs.speed),
      specialAttack = stat("specialAttack", specialDv),
      specialDefense = stat("specialDefense", specialDv),
    }
    mon.maxHp = mon.stats.hp
    if mon.hp == nil or mon.hp > mon.stats.hp then mon.hp = mon.stats.hp end
    return mon
  end
  local ok, Stats = pcall(require, "src.pokemon.Stats")
  if ok and type(Stats) == "table" and type(Stats.calc) == "function" then
    mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
    mon.hp = math.max(1, math.min(tonumber(mon.hp) or mon.stats.hp,
      mon.stats.hp))
  end
  return mon
end

-- ---------------------------------------------------------------- pick/roll
-- opts:
--   save, pool, pity, wonderPool, formItems, exports, pokemon, data, gen,
--   level, rng, itemExists(itemId), setFactor(mon, species)
-- Answers the whole proposed trade, or nil + a short reason.
function M.pick(opts)
  opts = opts or {}
  local pool, pity = opts.pool, opts.pity
  local poolmod = opts.wonderPool
  if not M.ready(pool) then return nil, "no_pool" end
  if type(pity) ~= "table" or type(pity.roll) ~= "function" then
    return nil, "no_pity"
  end
  if type(poolmod) ~= "table" or type(poolmod.pick) ~= "function" then
    return nil, "no_pool_module"
  end
  local rng = opts.rng or M.rng()
  local save = opts.save or {}
  local since = tonumber(save.g9WonderPity) or 0

  -- One clock drives BOTH rolls: `rng()` (NO arguments) is the 0..1 uniform,
  -- never `rng(0,1)` -- the engine's integer random would answer 0 or 1 and
  -- collapse the whole distribution to its first/last element.
  local tier, rung, hard = pity.roll(since, rng(), rng())
  local entry = poolmod.pick(pool, tier, rng())
  if not entry then return nil, "empty_pool" end

  -- A form is handed over as its base species + the item that enables it.
  local resolved
  if type(poolmod.resolveWith) == "function" then
    resolved = poolmod.resolveWith(entry, opts.formItems, opts.pokemon,
      opts.exports)
  else
    resolved = poolmod.resolve(entry, opts.formItems, opts.exports)
  end
  resolved = resolved or { species = entry.species }

  -- Both gene blocks are generated to total inside the rolled rung's range, so
  -- the mon the player receives really is the rarity the roll announced on
  -- EITHER vocabulary -- the modern IVs (what g9-battle-engine reads) and the
  -- cart's own DVs (the only genes a boot with no battle engine has; Gen 2's
  -- ladder tops at 90, Gen 1's at 80).
  local dvs
  if type(pity.dvsForRung) == "function" then
    dvs = pity.dvsForRung(rng, rung, opts.gen)
  end
  local ivs = (type(pity.ivsForRung) == "function"
    and pity.ivsForRung(rng, rung)) or M.ivsFor(rng, rung == 4)
  local raw = M.ivTotal(ivs)
  local score = pity.ivScore and pity.ivScore(raw) or 0
  local bonus = rung
  -- The flavour total the result page may show.  It is NOT the pity value:
  -- commit() resets the clock off the SPECIES bracket alone (see below).
  local stars = (tonumber(entry.star) or 1) + bonus
  local dvRaw = dvs and pity.dvRawTotal and pity.dvRawTotal({ dvs = dvs },
    opts.gen) or nil
  local dvScore = dvRaw and pity.dvScore and pity.dvScore(dvRaw, opts.gen)
    or nil
  local dvMax = pity.DV_MAX and (pity.DV_MAX[pity.dvGen
    and pity.dvGen(opts.gen) or 1] or pity.DV_MAX[1]) or nil

  local item = resolved.item
  local itemMissing = false
  if item and type(opts.itemExists) == "function" and not opts.itemExists(item) then
    -- The enabling item is not in this install (battle_forms absent, say):
    -- the base form still arrives, the item simply cannot.
    itemMissing = true
    item = nil
  end

  local mon = M.build(opts, resolved.species, opts.level, ivs, dvs, item)
  if not mon then return nil, "build_failed" end

  -- A Gigantamax form arrives as its base species AND with its Factor active.
  -- The write is the caller's (`setFactor` consults the engine's own
  -- eligibility gate), so the flag here records what actually happened rather
  -- than what was asked for.
  local factor = false
  if resolved.factor == true and type(opts.setFactor) == "function" then
    local okF, applied = pcall(opts.setFactor, mon, resolved.species)
    factor = okF and applied == true
  end

  return {
    entry = entry, resolved = resolved,
    species = resolved.species, item = item, itemMissing = itemMissing,
    source = resolved.source, factor = factor,
    tier = tier, ivRung = rung, hard = hard == true,
    perfect = (rung == 4),
    ivs = ivs, raw = raw, score = score, bonus = bonus, stars = stars,
    dvs = dvs, dvMax = dvMax, dvRaw = dvRaw, dvScore = dvScore,
    dvRung = (dvScore and pity.dvBonus
      and pity.dvBonus(dvScore, opts.gen)) or rung,
    mon = mon,
  }
end

-- -------------------------------------------------------------------- commit
-- Apply a pick to the save.  The traded Pokemon is gone (it left through the
-- cable) and the received one lands in ITS slot, so the party order a player
-- arranged is preserved.
function M.commit(opts)
  opts = opts or {}
  local save, index, mon = opts.save, opts.index, opts.mon
  local party = save and save.party
  if type(party) ~= "table" or type(index) ~= "number" then
    return false, "no_party"
  end
  if type(mon) ~= "table" then return false, "no_mon" end
  if index < 1 or index > #party then return false, "bad_index" end

  table.remove(party, index)
  table.insert(party, index, mon)

  -- Pokedex: a received Pokemon is seen AND owned/caught (SetSeenAndCaughtMon,
  -- the same pair a gift ticks).
  local species = mon.species
  if save.pokedex and species then
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.seen[species] = true
    local ownedKey = (opts.gen == 2) and "caught" or "owned"
    save.pokedex[ownedKey] = save.pokedex[ownedKey] or {}
    save.pokedex[ownedKey][species] = true
  end

  -- The enabling item.  Gold has a real held-item slot, so the Pokemon really
  -- does come holding its stone/crystal; on Gen 1 there is no such field, and
  -- the bag is where the cart's own item-use path reads it from -- so the item
  -- goes into the bag on BOTH, and onto the mon only where that field exists.
  local item = opts.item
  if item and (type(opts.itemExists) ~= "function" or opts.itemExists(item)) then
    if opts.gen == 2 then mon.item = item end
    local ok, Bag = pcall(require, "src.inventory.Bag")
    if ok and type(Bag) == "table" and type(Bag.add) == "function" then
      pcall(Bag.add, save, item, 1, opts.data)
    end
  end

  -- The pity clock.  It follows the SPECIES BRACKET alone (opts.tier): only a
  -- five-star species resets the ONE clock.  The +N IV/DV rung is flavour the
  -- result page prints and does NOT count, so a 2-star species rolled at +3 is
  -- "just a 2" and advances the clock (the request: "the + was just a flavor
  -- extra, not 2+3 = 5 star") -- see data/pity.lua's advance().  The old
  -- separate four-star key is cleared: the clock moves both rolls at once.
  local pity = opts.pity
  if type(pity) == "table" and type(pity.advance) == "function" then
    local bracket = tonumber(opts.tier)
    if not bracket and type(opts.entry) == "table" then
      bracket = tonumber(opts.entry.star)
    end
    save.g9WonderPity = pity.advance(tonumber(save.g9WonderPity) or 0,
      bracket or 1)
    save.g9WonderFourPity = nil
  end

  return true, mon
end

return M
