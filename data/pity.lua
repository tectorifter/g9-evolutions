-- data/pity.lua -- the wonder trade's rarity brackets, its IV factor and its
-- pity clock.  PURE: no engine, no window, no save -- every number in and out
-- is a plain value, so the whole thing is assertable from tools/verify.lua.
--
-- THE FIVE BRACKETS.  A species' star is its base-stat total (hp + attack +
-- defence + sp.attack + sp.defence + speed, the six modern stats -- national_dex
-- keeps the split spAttack/spDefense BESIDE the cart's collapsed `special`, and
-- the split is what is read), except that a legendary or mythical is ALWAYS
-- five stars whatever its total is.  The ceilings are the request's own
-- (200 / 300 / 400 / 600), so each bracket can be checked against Bulbapedia's
-- base-stat list.
--
-- THE TWO ROLLS.  The request gives both distributions outright:
--
--   species bracket: 1-star 20%, 2-star 30%, 3-star 44.3%, 4-star 5.1%,
--                    5-star 0.6%
--   IV factor:       +1 star 50%, +2 star 44.3%, +3 star 5.1%, +4 star 0.6%
--
-- A pull therefore rolls a BRACKET (BRACKET_CHANCE) and, independently, an IV
-- RUNG (IV_CHANCE).  The star a pull is WORTH is bracket + rung -- the request's
-- own "IV counts as extra star".  The IV rung is not read back off the six
-- numbers afterwards: the rung is rolled first and the six IVs are GENERATED to
-- total inside that rung's range, which is the only way the stated IV rates can
-- be true (a uniform six-IV roll would land +4 one time in billions).
--
-- THE PITY CLOCK.  One clock, and it moves BOTH rolls at once: past SOFT_PITY
-- its top tier's chance ramps linearly until either the 5-star bracket or the
-- +4 IV rung is CERTAIN on the PITY_MAX'th pull -- so the guarantee is the
-- request's "perfect 5 star + 4 star (pokemon + IV)" (a 9-star result).  The
-- non-top tiers keep their base proportions and are squeezed down together.
-- ONLY A FIVE-STAR SPECIES RESETS THE CLOCK.  The +N IV/DV rung is flavour the
-- result page prints and never counts, so a 2-star species rolled at +3 is
-- still "just a 2" and ADVANCES the clock rather than resetting it.
local Pity = {}

-- ---------------------------------------------------------------- brackets
-- The BST ceilings of brackets 1..4; anything above 600 is 5.
Pity.BST_CEILINGS = { 200, 300, 400, 600 }

function Pity.speciesStar(bst, legendary)
  if legendary then return 5 end
  bst = tonumber(bst) or 0
  for star = 1, #Pity.BST_CEILINGS do
    if bst <= Pity.BST_CEILINGS[star] then return star end
  end
  return 5
end

-- ------------------------------------------------- the two distributions
-- The request's rates, index 1..5 (brackets) and 1..4 (IV rungs).  Each sums
-- to 1; the LAST entry of each is the tier pity ramps.
Pity.BRACKET_CHANCE = { 0.20, 0.30, 0.443, 0.051, 0.006 }
Pity.IV_CHANCE = { 0.50, 0.443, 0.051, 0.006 }

-- ---------------------------------------------------------------- IV factor
-- The six modern IV keys, and the two scales.  IV_RAW_MAX is the arithmetic
-- maximum of six 0-31 IVs (186); IV_SCORE_MAX is the 216 the request's earlier
-- thresholds were written against (six x 36).  ivScore() converts between them.
Pity.IV_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }
Pity.IV_STAT_MAX = 31
Pity.IV_RAW_MAX = 6 * Pity.IV_STAT_MAX          -- 186
Pity.IV_SCORE_MAX = 216
Pity.IV_NO_BONUS = 100

-- The +N rungs, low to high: the RAW six-IV total each rung covers, derived
-- from the 216-scale rungs 100 / 150 / 200 / 216 so a generated set always
-- scores the rung it was rolled for.
Pity.IV_RANGES = {
  { bonus = 1, lo = 86, hi = 128 },
  { bonus = 2, lo = 129, hi = 171 },
  { bonus = 3, lo = 172, hi = 185 },
  { bonus = 4, lo = 186, hi = 186 },
}

-- A raw six-IV total onto the 0-216 the thresholds are written in.
function Pity.ivScore(raw)
  raw = tonumber(raw) or 0
  if raw < 0 then raw = 0 end
  if raw > Pity.IV_RAW_MAX then raw = Pity.IV_RAW_MAX end
  return math.floor(raw * Pity.IV_SCORE_MAX / Pity.IV_RAW_MAX + 0.5)
end

-- The +N rung a 216-scale score falls in (0 below the 100 rung).
function Pity.ivBonus(score)
  score = tonumber(score) or 0
  if score >= 216 then return 4 end
  if score >= 200 then return 3 end
  if score >= 150 then return 2 end
  if score >= 100 then return 1 end
  return 0
end

-- The raw total of a record's six IVs, or nil when the record carries none.
function Pity.rawIvTotal(mon)
  if type(mon) ~= "table" then return nil end
  local ivs = mon.ivs
  if type(ivs) == "table" then
    local total, seen = 0, false
    for _, key in ipairs(Pity.IV_KEYS) do
      local v = tonumber(ivs[key])
      if v then total = total + v; seen = true end
    end
    if seen then return total end
  end
  local dvs = mon.dvs
  if type(dvs) ~= "table" then return nil end
  local function dv(key, fallback)
    local v = tonumber(dvs[key])
    if not v then v = tonumber(dvs[fallback]) end
    return v or 0
  end
  local special = dv("special", "spc") * 2
  return dv("attack", "atk") * 2 + dv("defense", "def") * 2
    + dv("speed", "spd") * 2 + special + special
end

-- The bonus a record itself earns, and the stars a pull is worth.
function Pity.bonusOf(mon)
  local raw = Pity.rawIvTotal(mon)
  if not raw then return 0 end
  return Pity.ivBonus(Pity.ivScore(raw))
end

function Pity.starsOf(speciesStar, mon)
  return (tonumber(speciesStar) or 1) + Pity.bonusOf(mon)
end

-- Six IVs whose total lies inside rung `rung`'s raw range, distributed over
-- the six stats (each 0..31).  `rng` is a 0..1 uniform (the wonder trade's own
-- rng called with no arguments).  The +4 rung is exactly all-31s.
function Pity.ivsForRung(rng, rung)
  rung = math.floor(tonumber(rung) or 1)
  if rung < 1 then rung = 1 elseif rung > 4 then rung = 4 end
  local unit = function()
    local v = tonumber(rng and rng()) or 0
    if v < 0 then v = 0 elseif v >= 1 then v = 0.999999 end
    return v
  end
  local range = Pity.IV_RANGES[rung]
  local target = range.lo + math.floor(unit() * (range.hi - range.lo + 1))
  if target > Pity.IV_RAW_MAX then target = Pity.IV_RAW_MAX end
  local out, remaining = {}, target
  for i = 1, #Pity.IV_KEYS do
    local slotsLeft = #Pity.IV_KEYS - i
    local maxHere = math.min(Pity.IV_STAT_MAX, remaining)
    local minHere = math.max(0, remaining - Pity.IV_STAT_MAX * slotsLeft)
    local span = maxHere - minHere
    local pick = minHere
    if span > 0 then
      pick = minHere + math.floor(unit() * (span + 1))
      if pick > maxHere then pick = maxHere end
    end
    out[Pity.IV_KEYS[i]] = pick
    remaining = remaining - pick
  end
  return out
end

-- ---------------------------------------------------------------- DV factor
-- The cart's own genes, and the SECOND ladder the wonder trade rolls.  A boot
-- with no battle engine has no modern IV block at all: the generation's own
-- DVs are the only genes a Pokemon carries, so the same rarity:quality
-- distribution the IV rungs give has to hold on the DV scale too (the
-- request: "it also does the same it did for IV but for DV").
--
-- THE MAXIMUM IS PER GENERATION, and it is the request's own pair: Gen 2
-- scores the two special stats separately (six DV slots, 6 x 15 = 90), while
-- Gen 1's two special stats share ONE DV, so its ladder is read on the 80 the
-- request names.  A DV set is scored as its share of the generation's own
-- maximum, which is what makes the rungs the same FRACTIONS of the top on
-- both generations -- the request's "keep the same split ratios ... for DVs".
--
-- THE WEIGHTS.  The generation's DV fields number five (hp, attack, defence,
-- speed, special -- the cart itself derives the HP DV from the other four), so
-- Gen 2's split is expressed as a WEIGHT: its shared Special DV is counted
-- twice (once for Sp. Atk, once for Sp. Def), which is exactly the "double
-- Special" the BST read applies to a record with no split data.
Pity.DV_STAT_MAX = 15
Pity.DV_KEYS = { "hp", "attack", "defense", "speed", "special" }
Pity.DV_WEIGHTS = {
  [1] = { 1, 1, 1, 1, 1 },   -- Gen 1: one Special DV
  [2] = { 1, 1, 1, 1, 2 },   -- Gen 2: the shared Special DV stands for both
}
Pity.DV_MAX = { [1] = 80, [2] = 90 }

function Pity.dvGen(gen)
  if tonumber(gen) == 2 then return 2 end
  return 1
end

-- The weighted total a generation's DV set can reach (75 Gen 1, 90 Gen 2).
function Pity.dvWeightedMax(gen)
  gen = Pity.dvGen(gen)
  local weights = Pity.DV_WEIGHTS[gen]
  local total = 0
  for i = 1, #weights do total = total + Pity.DV_STAT_MAX * weights[i] end
  return total
end

-- The four +N rungs on the generation's DV score scale.  The boundaries are
-- the request's own IV thresholds (100 / 150 / 200 / 216) mapped onto the
-- generation's DV maximum, so the ladder is the same shape the IV ladder is;
-- the top rung is always the maximum itself (a perfect DV set).
function Pity.dvRanges(gen)
  gen = Pity.dvGen(gen)
  local max = Pity.DV_MAX[gen] or Pity.DV_MAX[1]
  local b1 = math.floor(max * 100 / 216)
  local b2 = math.floor(max * 150 / 216)
  local b3 = math.floor(max * 200 / 216)
  if b2 <= b1 then b2 = b1 + 1 end
  if b3 <= b2 then b3 = b2 + 1 end
  if b3 >= max then b3 = max - 1 end
  return {
    { bonus = 1, lo = b1, hi = b2 - 1 },
    { bonus = 2, lo = b2, hi = b3 - 1 },
    { bonus = 3, lo = b3, hi = max - 1 },
    { bonus = 4, lo = max, hi = max },
  }
end

-- A weighted DV total onto the generation's 0..DV_MAX score scale.
function Pity.dvScore(raw, gen)
  gen = Pity.dvGen(gen)
  local wmax = Pity.dvWeightedMax(gen)
  local max = Pity.DV_MAX[gen] or Pity.DV_MAX[1]
  local v = tonumber(raw) or 0
  if v < 0 then v = 0 elseif v > wmax then v = wmax end
  if wmax <= 0 then return 0 end
  return math.floor(v * max / wmax + 0.5)
end

function Pity.dvBonus(score, gen)
  score = tonumber(score) or 0
  for _, rung in ipairs(Pity.dvRanges(gen)) do
    if score >= rung.lo and score <= rung.hi then return rung.bonus end
  end
  return 0
end

-- Read one DV off a mon.dvs table, accepting the short spellings the engine's
-- own records use (`atk` / `def` / `spd` / `spc`, and `specialAttack` /
-- `specialDefense` for a record that splits them at the DV level).
local DV_ALIASES = {
  hp = "hp", attack = "atk", defense = "def", speed = "spd",
  special = "spc",
}
function Pity.dvValue(dvs, key)
  if type(dvs) ~= "table" then return nil end
  local v = tonumber(dvs[key])
  if v then return v end
  local alt = DV_ALIASES[key]
  if alt and alt ~= key then
    v = tonumber(dvs[alt])
    if v then return v end
  end
  if key == "special" then
    v = tonumber(dvs.specialAttack)
    if v then return v end
    return tonumber(dvs.specialDefense)
  end
  return nil
end

-- The HP DV: the cart stores only the other four and derives HP from their
-- low bits, so a record carrying no explicit `hp` answers that derivation.
function Pity.dvHp(dvs)
  local v = Pity.dvValue(dvs, "hp")
  if v then return v end
  local attack = Pity.dvValue(dvs, "attack") or 0
  local defense = Pity.dvValue(dvs, "defense") or 0
  local speed = Pity.dvValue(dvs, "speed") or 0
  local special = Pity.dvValue(dvs, "special") or 0
  return (attack % 2) * 8 + (defense % 2) * 4 + (speed % 2) * 2
    + (special % 2)
end

-- The weighted DV total a mon carries (nil when it has no DV block at all).
function Pity.dvRawTotal(mon, gen)
  local dvs = type(mon) == "table" and mon.dvs or nil
  if type(dvs) ~= "table" then return nil end
  gen = Pity.dvGen(gen)
  local weights = Pity.DV_WEIGHTS[gen]
  local total = 0
  for i, key in ipairs(Pity.DV_KEYS) do
    local v = (key == "hp") and Pity.dvHp(dvs) or Pity.dvValue(dvs, key)
    total = total + (tonumber(v) or 0) * weights[i]
  end
  return total
end

function Pity.dvScoreOf(mon, gen)
  local raw = Pity.dvRawTotal(mon, gen)
  if not raw then return nil end
  return Pity.dvScore(raw, gen)
end

function Pity.dvBonusOf(mon, gen)
  local score = Pity.dvScoreOf(mon, gen)
  if not score then return 0 end
  return Pity.dvBonus(score, gen)
end

-- An integer total spread over `count` slots of 0..cap (exact: every unit of
-- the total lands somewhere, so the sum is preserved).
local function spread(unit, count, cap, total)
  total = math.max(0, math.min(cap * count, math.floor(tonumber(total) or 0)))
  local out, remaining = {}, total
  for i = 1, count do
    local slotsLeft = count - i
    local lo = math.max(0, remaining - cap * slotsLeft)
    local hi = math.min(cap, remaining)
    local pick = lo
    if hi > lo then
      pick = lo + math.floor(unit() * (hi - lo + 1))
      if pick > hi then pick = hi end
    end
    out[i] = pick
    remaining = remaining - pick
  end
  return out
end

-- A DV set whose SCORE lies inside rung `rung`'s range for `gen`, in the
-- mon.dvs field spelling the engine uses.  `rng` is a 0..1 uniform (the
-- wonder trade's own rng called with no arguments).  Gen 2 draws its shared
-- Special DV FIRST and splits the exact remainder over the four 1-weight DVs,
-- because that DV is counted twice by the score.
function Pity.dvsForRung(rng, rung, gen)
  gen = Pity.dvGen(gen)
  rung = math.floor(tonumber(rung) or 1)
  if rung < 1 then rung = 1 elseif rung > 4 then rung = 4 end
  local unit = function()
    local v = tonumber(rng and rng()) or 0
    if v < 0 then v = 0 elseif v >= 1 then v = 0.999999 end
    return v
  end
  local range = Pity.dvRanges(gen)[rung]
  local score = range.lo + math.floor(unit() * (range.hi - range.lo + 1))
  if score > range.hi then score = range.hi end
  local target = math.floor(score * Pity.dvWeightedMax(gen)
    / (Pity.DV_MAX[gen] or Pity.DV_MAX[1]) + 0.5)
  if target > Pity.dvWeightedMax(gen) then target = Pity.dvWeightedMax(gen) end
  if gen == 2 then
    local lo = math.max(0, math.ceil((target - 4 * Pity.DV_STAT_MAX) / 2))
    local hi = math.min(Pity.DV_STAT_MAX, math.floor(target / 2))
    local special = lo
    if hi > lo then
      special = lo + math.floor(unit() * (hi - lo + 1))
      if special > hi then special = hi end
    end
    local rest = spread(unit, 4, Pity.DV_STAT_MAX, target - special * 2)
    return { hp = rest[1], attack = rest[2], defense = rest[3],
      speed = rest[4], special = special }
  end
  local v = spread(unit, 5, Pity.DV_STAT_MAX, target)
  return { hp = v[1], attack = v[2], defense = v[3], speed = v[4],
    special = v[5] }
end

-- The faithful conversion the OTHER way: a DV onto the modern 0-31 scale
-- (Gen 1's one Special DV feeds BOTH special IVs).  The inverse of
-- trades/wonder.lua's dvOf, and the same rule g9-battle-engine's ModernStats
-- uses.
function Pity.ivsFromDvs(dvs)
  if type(dvs) ~= "table" then return nil end
  local function ivOf(v) return math.floor((tonumber(v) or 0) * 31 / 15 + 0.5) end
  local special = Pity.dvValue(dvs, "special") or 0
  return {
    hp = ivOf(Pity.dvHp(dvs)),
    atk = ivOf(Pity.dvValue(dvs, "attack") or 0),
    def = ivOf(Pity.dvValue(dvs, "defense") or 0),
    spe = ivOf(Pity.dvValue(dvs, "speed") or 0),
    spa = ivOf(special),
    spd = ivOf(special),
  }
end

-- --------------------------------------------------------------- pity clock
-- One clock: the 5-star bracket and the +4 IV rung both ramp past SOFT_PITY
-- and are certain on the PITY_MAX'th pull.
Pity.PITY_MAX = 70
Pity.SOFT_PITY = 55

-- 0 before the soft knee, then linear to 1 at PITY_MAX.  `since` is the number
-- of pulls since the clock last reset (0 = the very next pull can be one).
function Pity.intensity(since)
  since = tonumber(since) or 0
  if since < Pity.SOFT_PITY then return 0 end
  if since >= Pity.PITY_MAX then return 1 end
  return (since - Pity.SOFT_PITY) / (Pity.PITY_MAX - Pity.SOFT_PITY)
end

-- Which index of `weights` a uniform `roll` lands in, with the LAST tier's
-- chance ramped by pity: its base weight grows toward 1 while every lower
-- tier keeps its base proportion of what is left.
function Pity.rampTop(weights, roll, since)
  local n = #weights
  if n == 0 then return 1 end
  local top = weights[n]
  local p = Pity.intensity(since)
  local pTop = top + (1 - top) * p
  roll = tonumber(roll) or 0
  if roll < 0 then roll = 0 elseif roll >= 1 then roll = 0.999999 end
  if roll < pTop or n == 1 then return n end
  local rest = 1 - top
  if rest <= 0 then return n end
  local t = (roll - pTop) / math.max(1e-9, 1 - pTop)
  local seen = 0
  for i = 1, n - 1 do
    seen = seen + weights[i] / rest
    if t < seen then return i end
  end
  return n - 1
end

-- One wonder trade's roll.  Returns tier, rung, hard:
--   tier  1..5, the SPECIES bracket the pull draws from
--   rung  1..4, the IV bonus the pull is built with
--   hard  true when the clock guaranteed the pull (bracket 5 + rung 4)
-- `r1`/`r2` are the two uniforms the caller supplies (0..1).
function Pity.roll(since, r1, r2)
  since = math.max(0, math.floor(tonumber(since) or 0))
  local hard = (since + 1) >= Pity.PITY_MAX
  if hard then return 5, 4, true end
  local tier = Pity.rampTop(Pity.BRACKET_CHANCE, tonumber(r1) or 0, since)
  local rung = Pity.rampTop(Pity.IV_CHANCE, tonumber(r2) or 0, since)
  return tier, rung, false
end

-- The clock after a pull whose SPECIES bracket is `bracket` (1..5).  Only a
-- five-star species resets it.  The +N IV/DV rung is deliberately NOT read
-- here: it is flavour the result page prints, so a 2-star species rolled at +3
-- is "just a 2" and advances the clock rather than resetting it.
function Pity.advance(since, bracket)
  bracket = tonumber(bracket) or 0
  if bracket >= 5 then return 0 end
  return (tonumber(since) or 0) + 1
end

return Pity
