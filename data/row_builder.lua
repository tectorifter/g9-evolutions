-- Turns one national_dex evolution spec into this generation's evolutions[]
-- rows, and names the evolution-method id each row uses.
--
-- This is the whole conversion policy in one place.  The rules, and why:
--
--   REGIONAL (the method carries a `region`).  Rewritten around this mod's
--   region items: the row becomes G9_REGION_<REGION> and fires on a level-up
--   while the mon HOLDS that region's item, at the method's own level when it
--   carries one and at the REGION LEVEL option when it does not (Pikachu's Alolan
--   Raichu is a Thunder Stone in the data; here it is a Solstice Nectar held
--   through level 36).  This is deliberately checked BEFORE the trigger, so a
--   use-item regional (Pikachu, Exeggcute, Petilil) becomes a held-item level-up
--   too.  The row is emitted FIRST among a species' rows (see M.build's caller),
--   so that when a mon holding the item reaches the shared level the regional
--   form wins the engine's first-match walk -- the "Samurott OR Samurott-Hisui"
--   the item is meant to choose between.
--
--   LEVEL-UP with an extra condition, in priority order: a `knownMove`
--   (G9_KNOWN_MOVE_<MOVE>), a `heldItem`, a `minHappiness`
--   (G9_HAPPINESS_<N>), a `relativePhysicalStats` (G9_STAT_<COMPARISON>),
--   otherwise a plain level-up (G9_LEVEL).  Extra conditions this engine cannot
--   express (rain, walking distance, affection, party species, ...) are
--   deliberately DROPPED rather than left to strand the evolution: reachable-
--   and-easier beats unreachable.
--
--   NO MOVE EVO (the option of that name) changes the known-move branch: when
--   it is on, "level up while knowing <move>" becomes a plain level-up at the
--   level the mon LEARNS the move, plus one (data/move_evo.lua finds that level
--   in national_dex's learnset and falls back to the line's shape).  The move
--   requirement is then not registered at all, because no row references it.
--   The option existing is what lets a player who wants the cart's original
--   "come back once it knows the move" rule have it, and one who wants the
--   evolution reachable by level alone have that instead.
--
--   A HELD-ITEM level-up is where the two generations part company, because
--   only Gold has a real held-item field:
--     * Gen 2 -> G9_HELD_ITEM: level up while `mon.item` is the required item
--       (in the ITEM pocket, given through the party menu).
--     * Gen 1 -> G9_ITEM_LEVEL: the item is a use-on-a-mon tool.  Using it on
--       the Pokemon fulfils "while holding", but only once the mon has reached
--       the level this row carries (the data's own level, else the HELD LEVEL
--       option).  Red/Blue/Yellow has no held-item slot to check, so a
--       use-item trigger is the one honest way to express the condition.  The
--       item is consumed on success.
--
--   USE-ITEM -> the engine's own operator, `ITEM` on Gen 1 and `EVOLVE_ITEM` on
--   Gen 2, with the row's `item` remapped to the running cart's id.  Those ids
--   are NOT renamed because the engine's own item-use machinery keys off them
--   directly (Gen 1's inventory/ItemEffects.lua and ui/PartyMenu.lua both test
--   `evo.method == "ITEM"`), so owning the row means reusing the operator, not
--   re-spelling it.
--
--   GIMMIGHOUL COINS (Gimmighoul -> Gholdengo) -> a use-item row on the coin
--   (items/evolution_items.lua registers a custom effect that additionally
--   demands the COIN COST option's worth of coins in the bag and consumes
--   them).  The row keeps the engine's ITEM / EVOLVE_ITEM operator so the
--   party-menu picker still offers the coin on a Gimmighoul.  The coins
--   themselves drop from a defeated wild Gimmighoul (main.lua).
--
--   TRADE -> TWO rows: the engine's `TRADE`/`EVOLVE_TRADE` (so a real link trade
--   still works, and still keys off the engine's own id in link/Protocol.lua),
--   immediately followed by an alternative.  The alternative is G9_TRADE_LEVEL,
--   which fires the same evolution on a level-up at the TRADE LEVEL option or
--   higher.  On Gen 1 an item-bearing trade uses G9_ITEM_LEVEL instead: use the
--   item on the mon once it has reached the HELD LEVEL option, exactly like the
--   held-item case above, since there is no held-item slot for a trade to read.
--   The held item a trade demands rides every row.
--
--   EXOTIC (every trigger this engine has no seam for -- spin, shed, use-move
--   N times, recoil/take-damage totals, three hits, three-defeats, the Kubfu
--   towers, and anything a future dex adds) -> a plain level-up at the EXOTIC
--   LEVEL option (40 by default).  The user's rule: a non-codable condition is
--   recoded as a normal evolution rather than left permanently unreachable.
--   "other" with a level is still a plain level-up at that level.
local M = {}

-- ---- method-id builders (pure; the tests assert on them) -------------------

function M.levelId() return "G9_LEVEL" end
function M.heldItemId() return "G9_HELD_ITEM" end
function M.itemLevelId() return "G9_ITEM_LEVEL" end
function M.tradeLevelId() return "G9_TRADE_LEVEL" end

function M.itemId(gen) return gen == 2 and "EVOLVE_ITEM" or "ITEM" end
function M.tradeId(gen) return gen == 2 and "EVOLVE_TRADE" or "TRADE" end

function M.happinessId(value)
  return "G9_HAPPINESS_" .. tostring(math.floor(tonumber(value) or 0))
end

-- The day/night stone + friendship route (Espeon / Umbreon and kin).  Gold has
-- a real day/night clock, so the row there is only ever reached from a stone's
-- own use -- which is why its method declares `requiresForce` (see
-- evolutions/happiness_stone.lua).  Gen 1 borrows the engine's own ITEM
-- operator instead, because its stone picker keys off that spelling directly.
function M.happinessStoneId(value)
  return "G9_HAPPINESS_STONE_" .. tostring(math.floor(tonumber(value) or 0))
end

function M.moveId(slug)
  return "G9_KNOWN_MOVE_" .. (slug:upper():gsub("[^%u%d]", ""))
end

function M.statId(comparison)
  return "G9_STAT_" .. comparison
end

function M.regionId(region)
  return "G9_REGION_" .. region:upper()
end

-- The item slug a `gimmighoul-coins` evolution is satisfied with.  national_dex
-- names the item (GIMMIGHOULCOIN) but not on the evolution row, so the slug
-- lives here.
M.GIMMIGHOUL_COIN = "gimmighoul-coin"

-- ---- small normalisers -----------------------------------------------------

-- PokeAPI's TR_* window, spelled the way Gold's evolution schema expects.
function M.dayNight(value)
  if value == "day" or value == "morning" then return "MORNDAY" end
  if value == "night" then return "NITE" end
  return nil
end

-- PokeAPI's relativePhysicalStats: 1 attack>defence, -1 attack<defence,
-- 0 equal -- the ATK_GT_DEF family Gold's own schema names.
function M.statComparison(value)
  local n = tonumber(value)
  if n == nil then
    if value == "ATK_LT_DEF" or value == "ATK_GT_DEF" or value == "ATK_EQ_DEF" then
      return value
    end
    return "ATK_EQ_DEF"
  end
  if n < 0 then return "ATK_LT_DEF" end
  if n > 0 then return "ATK_GT_DEF" end
  return "ATK_EQ_DEF"
end

-- ---- row construction ------------------------------------------------------

local function baseRow(gen, id, target)
  if gen == 2 then return { method = id, into = target } end
  return { method = id, species = target }
end

-- One spec -> one or more rows.  `ctx` carries:
--   gen          1 or 2
--   regionLevel  level for a regional row that names no level of its own
--   tradeLevel   level a trade evolution may fire at instead of trading
--   exoticLevel  level an uncodable ("exotic") evolution is recoded to
--   heldLevel    level a Gen 1 held-item / item-trade use needs
--   itemId       function(slug) -> that generation's item id (nil if unknown)
--   registered   function(speciesId) -> true when the species exists
-- Returns nil when the target species is not registered (a dangling row is a
-- cross-validation error and a permanently dead evolution).
function M.build(spec, ctx)
  if type(spec) ~= "table" or type(spec.method) ~= "table" then return nil end
  local gen = ctx.gen
  local target = spec.target
  if not ctx.registered(target) then return nil end
  local method = spec.method
  local Alt = ctx.alt
  local region = method.region

  -- REGIONAL first: a region item held through the level named by the data
  -- (or the REGION LEVEL option when the data only names a stone).
  if type(region) == "string" and region ~= "" then
    local row = baseRow(gen, M.regionId(region), target)
    row.level = tonumber(method.level) or ctx.regionLevel
    return { row }
  end

  -- The Rockruff line on Gen 1 is rebuilt explicitly (see
  -- data/alt_evolutions.lua): the data's two level-25 targets cannot be told
  -- apart without a clock, so the Sun / Dusk stones choose Midday / Dusk and a
  -- plain level-up chooses Midnight.
  if Alt and type(Alt.override) == "function" then
    local rows = Alt.override(spec, ctx)
    if rows then return rows end
  end

  local trigger = method.trigger

  if trigger == "level-up" then
    local row
    if type(method.knownMove) == "string" then
      -- NO MOVE EVO: the hint family's "level up knowing <move>" becomes a
      -- plain level-up at the level the mon learns the move + 1.  The level is
      -- data/move_evo.lua's answer; when the option is off, or the level cannot
      -- be derived at all, the row keeps the move requirement.
      local converted = ctx.noMoveEvo and type(ctx.moveEvoLevel) == "function"
        and ctx.moveEvoLevel(spec.from, method.knownMove)
      if tonumber(converted) then
        row = baseRow(gen, M.levelId(), target)
        row.level = math.floor(tonumber(converted))
        return { row }
      end
      row = baseRow(gen, M.moveId(method.knownMove), target)
      if tonumber(method.level) then row.level = tonumber(method.level) end
      return { row }
    end
    if type(method.heldItem) == "string" then
      local item = ctx.itemId(method.heldItem)
      if item then
        local level = tonumber(method.level) or ctx.heldLevel
        if gen == 2 then
          row = baseRow(gen, M.heldItemId(), target)
          row.item = item
          if tonumber(method.level) then row.level = tonumber(method.level) end
        else
          -- Gen 1: no held-item field, so "hold it" becomes "use it once the
          -- mon is strong enough" (G9_ITEM_LEVEL).
          row = baseRow(gen, M.itemLevelId(), target)
          row.item = item
          row.level = level
        end
        return { row }
      end
      -- an unresolvable item cannot become a held-item row; fall through to
      -- the exotic level so the evolution stays reachable.
      return { M.exoticRow(gen, target, ctx) }
    end
    if tonumber(method.minHappiness) then
      local threshold = math.floor(tonumber(method.minHappiness))
      -- A friendship route that also names a day/night window gets its stone
      -- (Espeon = Sun Stone + friendship, Umbreon = Dusk Stone + friendship).
      -- Red/Blue/Yellow has no clock for the level-up route to read, so there
      -- the stone REPLACES it -- the stone is the missing day/night.  Gold
      -- keeps the real clock AND gains the stone route.
      local stoneSlug = Alt and Alt.stoneEligible(method)
        and Alt.stoneForTime(method) or nil
      local stoneItem = stoneSlug and ctx.itemId(stoneSlug) or nil
      if stoneItem then
        if gen == 1 then
          row = baseRow(gen, M.itemId(gen), target)
          row.item = stoneItem
          row.minHappiness = threshold
          return { row }
        end
        local base = baseRow(gen, M.happinessId(threshold), target)
        local window = M.dayNight(method.timeOfDay)
        if window then base.time = window end
        local stoneRow = baseRow(gen, M.happinessStoneId(threshold), target)
        stoneRow.item = stoneItem
        stoneRow.minHappiness = threshold
        return { base, stoneRow }
      end
      row = baseRow(gen, M.happinessId(method.minHappiness), target)
      if gen == 2 then
        local window = M.dayNight(method.timeOfDay)
        if window then row.time = window end
      end
      return { row }
    end
    if method.relativePhysicalStats ~= nil then
      local comparison = M.statComparison(method.relativePhysicalStats)
      row = baseRow(gen, M.statId(comparison), target)
      row.level = tonumber(method.level) or 1
      if gen == 2 then row.comparison = comparison end
      return { row }
    end
    row = baseRow(gen, M.levelId(), target)
    row.level = tonumber(method.level) or 1
    -- A plain day/night level-up also gets its stone route on BOTH
    -- generations: the clock still runs on Gold, but the Sun / Dusk Stone is
    -- the answer on Red/Blue/Yellow (and a convenient shortcut on Gold).
    if Alt and Alt.stoneEligible(method) then
      local stoneSlug = Alt.stoneForTime(method)
      local stoneItem = stoneSlug and ctx.itemId(stoneSlug) or nil
      if stoneItem then
        local stoneRow = baseRow(gen, M.itemId(gen), target)
        stoneRow.item = stoneItem
        return { row, stoneRow }
      end
    end
    return { row }
  end

  if trigger == "use-item" then
    local item = type(method.item) == "string" and ctx.itemId(method.item) or nil
    if item then
      local row = baseRow(gen, M.itemId(gen), target)
      row.item = item
      return { row }
    end
    return { M.exoticRow(gen, target, ctx) }
  end

  if trigger == "gimmighoul-coins" then
    local coin = ctx.itemId(M.GIMMIGHOUL_COIN)
    if coin then
      local row = baseRow(gen, M.itemId(gen), target)
      row.item = coin
      return { row }
    end
    return { M.exoticRow(gen, target, ctx) }
  end

  if trigger == "trade" then
    local held = type(method.heldItem) == "string" and ctx.itemId(method.heldItem)
      or (type(method.item) == "string" and ctx.itemId(method.item) or nil)
    local trade = baseRow(gen, M.tradeId(gen), target)
    if held then trade.item = held end
    local alternative
    if gen == 1 and held then
      -- Gen 1, item trade: use the item on the mon once it is high enough
      -- (there is no held-item slot for a trade to read).
      alternative = baseRow(gen, M.itemLevelId(), target)
      alternative.item = held
      alternative.level = tonumber(method.level) or ctx.heldLevel
    else
      alternative = baseRow(gen, M.tradeLevelId(), target)
      alternative.level = ctx.tradeLevel
      if held then alternative.item = held end
    end
    return { trade, alternative }
  end

  if trigger == "other" and tonumber(method.level) then
    local row = baseRow(gen, M.levelId(), target)
    row.level = tonumber(method.level)
    return { row }
  end

  -- Anything left -- the exotic triggers this engine cannot express, and any
  -- trigger a future dex adds -- becomes a plain level-up at EXOTIC LEVEL.
  return { M.exoticRow(gen, target, ctx) }
end

-- The row an uncodable condition is recoded to: a plain level-up at the EXOTIC
-- LEVEL option.  Kept out of M.build's body so the intent is one line and the
-- tests can assert on it directly.
function M.exoticRow(gen, target, ctx)
  local row = baseRow(gen, M.levelId(), target)
  row.level = tonumber(ctx and ctx.exoticLevel) or 40
  return row
end

-- The variant values the data asks for, so main.lua can register exactly the
-- method ids it is about to reference (a happiness threshold or a known move
-- that never appears must not leave a dangling id behind, and one that does
-- appear must not be missing).  It also collects the ITEM slugs, split by the
-- job they do, so items/evolution_items.lua knows which items need a use
-- effect (a use-item trigger, or a Gen 1 held-item / item-trade, which become
-- use-items there) and which are only ever held on Gold.
--
-- `ctx` (optional) is the NO MOVE EVO half: when the known-move converter
-- answers a level for a move, the row will be a plain level-up and no
-- G9_KNOWN_MOVE_ method is referenced, so that move is not collected.
function M.collectNeeds(specs, ctx)
  local Alt = ctx and ctx.alt
  local gen = (ctx and ctx.gen) or 1
  local need = {
    happiness = {}, happinessStones = {}, moves = {}, useItems = {},
    heldItems = {}, tradeItems = {}, coins = false,
  }
  for _, spec in ipairs(specs or {}) do
    local method = spec.method
    if type(method) == "table" and method.region == nil then
      local trigger = method.trigger
      if tonumber(method.minHappiness) then
        need.happiness[math.floor(tonumber(method.minHappiness))] = true
      end
      -- The day/night stone routes: the stone is a use-item, and a route that
      -- also demands friendship needs its own G9_HAPPINESS_STONE_<N> method on
      -- Gold (on Gen 1 it reuses the engine's ITEM operator, so no method id).
      if Alt and Alt.stoneEligible and Alt.stoneEligible(method) then
        local stone = Alt.stoneForTime(method)
        if stone then need.useItems[stone] = true end
        if gen == 2 and tonumber(method.minHappiness) then
          need.happinessStones[math.floor(tonumber(method.minHappiness))] = true
        end
      end
      if type(method.knownMove) == "string" then
        local converted = ctx and ctx.noMoveEvo
          and type(ctx.moveEvoLevel) == "function"
          and ctx.moveEvoLevel(spec.from, method.knownMove)
        if not tonumber(converted) then
          need.moves[method.knownMove] = true
        end
      end
      if trigger == "use-item" and type(method.item) == "string" then
        need.useItems[method.item] = true
      end
      if trigger == "gimmighoul-coins" then
        need.coins = true
      end
      if type(method.heldItem) == "string" then
        need.heldItems[method.heldItem] = true
      end
      if trigger == "trade" then
        if type(method.item) == "string" then
          need.tradeItems[method.item] = true
        end
        if type(method.heldItem) == "string" then
          need.tradeItems[method.heldItem] = true
        end
      end
    end
  end
  return need
end

return M
