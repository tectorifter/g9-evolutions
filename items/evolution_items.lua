-- Every evolution ITEM national_dex names, made real so the rows that name
-- one can actually be satisfied.
--
-- national_dex deliberately DESCRIBES items without registering them (its own
-- test asserts that nothing in the dex calls content.items:register), and its
-- patch() door cannot conjure one either -- patch("item", ...) forwards only
-- the fields of an item the engine ALREADY has, so a new id has nothing to be
-- forwarded to.  Items are therefore the one thing this mod writes straight to
-- the engine's own `items` registry -- and it WRITES with `:patch`, never
-- `:register`: patch layers and cannot be refused, where register on a record
-- registry replaces the value and errors on an id that already exists.  The ids
-- it uses are national_dex's own separator-free uppercase ids
-- (RAZORCLAW, KINGSROCK, DUSKSTONE, GIMMIGHOULCOIN, ...), except for the stones
-- a cart already owns, which data/item_ids.lua remaps to that cart's real id
-- and which are skipped here rather than re-registered as a dead duplicate.
--
-- What "registered" means differs by generation, and the difference is forced
-- by the engine:
--
--   GEN 2 has a real held-item field (mon.item) and a real USE-item dispatch
--   (src/core/gen2/ItemEffects.lua).  So an item that the data uses as a
--   use-item gets Gold's ITEMMENU_PARTY field menu plus an item_effects record
--   whose action is "stone" -- the same shape Gold's own six stones use -- and
--   an item that is only ever HELD (or that a trade demands) gets
--   ITEMMENU_NOUSE, so it appears in the ITEM pocket (held-item menu) and
--   offers no USE verb.  Nothing here touches mon.item; Gold's own Give/Take
--   does that.
--
--   GEN 1 has no held-item field at all, so every non-native item is a
--   use-on-a-mon tool.  For a USE-ITEM (a stone, a Scroll of Darkness) the
--   effect consumes itself on a matching ITEM row, exactly like a cart stone.
--   For a HELD-ITEM or item-trade evolution -- the user's rule: "for gen 1, all
--   held item evolutions including trades, make them be use item on the
--   pokemon + meeting level criteria" -- the item is used on the mon and
--   evolves it only once the mon has reached the row's level (G9_ITEM_LEVEL).
--   Below that level the use is refused with a "not strong enough" line.  On a
--   species the item does not evolve, the use falls back to the old behaviour:
--   it toggles the mon's g9HeldItem mark and is KEPT (re-usable, never
--   consumed), so one Razor Claw can still be "held" for g9-battle-engine's
--   held-item effects.  Using it again takes the mark back off, so a misclick
--   is fixable.
--
--   The GIMMIGHOUL COIN is its own effect on both generations: each use spends
--   exactly ONE coin and adds ONE point to a saved counter on the Pokemon
--   (`mon.g9GimmighoulCharge`).  At GIMMIGHOUL COST points (20 by default) the
--   Pokemon evolves into Gholdengo.  The coin is exclusive -- a Gimmighoul and
--   nothing else (not even a Gholdengo) -- and a re-entrancy mark refuses a use
--   that is already mid-evolution, so the counter cannot nest a second
--   evolution.  Coins drop from a defeated wild Gimmighoul (main.lua).
local PRICE = 1000

local NO_EFFECT = "It won't have\nany effect."

-- Shown when a Gen 1 use-on-a-mon meets the item it needs but is still below
-- the level the row demands (a held-item / item-trade recoded to G9_ITEM_LEVEL).
local TOO_WEAK = "It's not strong\nenough yet."

return {
  install = function(mod, ctx, need)
    local gen = ctx.gen
    local held = ctx.held
    local ids = ctx.itemIds
    local Alt = ctx.alt
    local useItems = (need and need.useItems) or {}
    local coinSlug = ctx.coinSlug or "gimmighoul-coin"
    local coinCost = tonumber(ctx.coinCost) or 20

    local registeredItems, registeredEffects = 0, 0

    -- The friendship the row demands (a stone route that keeps its bond
    -- requirement -- Espeon = Sun Stone + friendship).  Happiness.lua
    -- publishes the very reader its own checks use; this is the fallback for a
    -- load order that somehow skipped it, so the two can never disagree about
    -- what a mon's friendship is.
    local function friendshipOf(mon)
      if type(ctx.friendshipOf) == "function" then return ctx.friendshipOf(mon) end
      if type(mon) ~= "table" then return 0 end
      local v = tonumber(mon.happiness) or tonumber(mon.g9Happiness)
      return v or 70
    end

    -- Shown when a stone would evolve the mon but its friendship is too low.
    local TOO_LOYAL = "It's not friendly\nenough yet."

    -- The charge vocabulary (data/alt_evolutions.lua).  Aliased with plain
    -- fallbacks so a load that somehow skipped that module degrades to the
    -- same rules rather than erroring inside an item use.
    local chargeField = (Alt and Alt.CHARGE_FIELD) or "g9GimmighoulCharge"
    local isGimmighoul = (Alt and Alt.isGimmighoul) or function(species)
      return type(species) == "string" and species:sub(1, 11) == "GIMMIGHOUL"
    end
    local chargeOf = (Alt and Alt.chargeOf) or function(mon, max)
      if type(mon) ~= "table" then return 0 end
      local n = math.floor(tonumber(mon.g9GimmighoulCharge) or 0)
      if n < 0 then n = 0 end
      if max and n > max then n = max end
      return n
    end
    local isEvolving = (Alt and Alt.isEvolving) or function() return false end
    local markEvolving = (Alt and Alt.markEvolving) or function() end
    local evolveTargetOf = (Alt and Alt.evolveTargetOf) or function(def, itemId)
      for _, evo in ipairs((def and def.evolutions) or {}) do
        if evo.item == itemId then return evo.species or evo.into end
      end
      return nil
    end

    -- The line every charge use prints: how full the Gimmighoul now is.  The
    -- next coin must NOT be offered once the mon is at the threshold -- that
    -- use evolves it instead -- so the count only ever prints below the max.
    local function chargeText(charge)
      return "Gimmighoul took\nthe coin! " .. tostring(charge)
        .. "/" .. tostring(coinCost)
    end

    -- The item's own use-on-a-mon behaviour on Gen 1.  A use-item trigger (or
    -- the same item on a held-item / item-trade row) hunts the target species'
    -- evolution rows and consumes itself on a match, refusing exactly like a
    -- cart stone on a miss.  `allowHold` items (the held-item and trade-item
    -- families) additionally toggle the g9HeldItem mark when the species has
    -- no row for them at all, which is how a Gen 1 Razor Claw stays "held" for
    -- its battle effect on everything that is not a Sneasel.
    local function gen1Effect(itemId, name, allowHold)
      return {
        needsTarget = true,
        battle = false,
        use = function(context)
          local target = context and context.target
          if type(target) ~= "table" then
            return "failed", { NO_EFFECT }
          end
          local data = context and context.data
          local species = data and data.pokemon and data.pokemon[target.species]
          local levelGated = false
          for _, evo in ipairs((species and species.evolutions) or {}) do
            if evo.item == itemId then
              if evo.method == "ITEM" then
                -- a stone route that still demands friendship (Espeon =
                -- Sun Stone + friendship): refuse, and do NOT consume the
                -- stone, when the mon is not friendly enough yet
                local need = tonumber(evo.minHappiness)
                if need and friendshipOf(target) < need then
                  return "failed", { TOO_LOYAL }
                end
                return "consumed", nil, { evolveTo = evo.species }
              end
              if evo.method == "G9_ITEM_LEVEL" then
                if (tonumber(target.level) or 1) >= (tonumber(evo.level) or 0) then
                  return "consumed", nil, { evolveTo = evo.species }
                end
                levelGated = true
              end
            end
          end
          if levelGated then return "failed", { TOO_WEAK } end
          if not allowHold then return "failed", { NO_EFFECT } end
          if held.of(target, 1) == itemId then
            held.set(target, 1, nil)
            return "kept", { name .. " was put\nback." }
          end
          held.set(target, 1, itemId)
          return "kept", { name .. " is now held!" }
        end,
      }
    end

    -- The item's own use-on-a-mon behaviour on Gen 2: Gold's own stone shape,
    -- action = "stone", so Game2:usePartyItem plays the evolution animation
    -- and consumes only on a real evolution.
    local function gen2StoneEffect(itemId)
      return {
        action = "stone",
        field = true,
        needsTarget = true,
        battle = false,
        use = function(context)
          local Strings = require("src.core.Strings")
          local Evolution = require("src.core.gen2.Evolution")
          local entry = Evolution.checkMon(context.data, context.mon,
            { force = true, item = context.item })
          if not entry then
            return { used = false, text = Strings(NO_EFFECT) }
          end
          return { used = true, evolution = entry }
        end,
      }
    end

    -- The Gimmighoul Coin's charge mechanic (both generations).
    --
    -- Gholdengo's own route -- "level up carrying enough Gimmighoul Coins" --
    -- has no side-effect seam this engine can fire from, so the coin works
    -- differently: using ONE coin on a Gimmighoul adds ONE point to a saved
    -- counter (`mon.g9GimmighoulCharge`), and at GIMMIGHOUL COST points
    -- (20 by default) the Pokemon evolves.  Every use spends exactly one coin.
    --
    -- Two safeguards, because a naive counter is easy to break:
    --   * the coin is EXCLUSIVE -- it charges a Gimmighoul and nothing else,
    --     so a Gholdengo (or any other species) is refused outright, which is
    --     also what stops the evolved form being "topped up" after the fact;
    --   * a re-entrancy mark (Alt.markEvolving) refuses a use that is already
    --     mid-evolution, so the threshold use can never nest a second
    --     evolution inside the engine's own animation pass.
    --
    -- The saved value is clamped to [0, cost], so a hand-edited or corrupted
    -- save can never make the counter overflow past the threshold.
    local function planCharge(target, itemId, data)
      if type(target) ~= "table" then return nil end
      if not isGimmighoul(target.species) then return nil end
      if isEvolving(target) then return nil end
      local species = data and data.pokemon and data.pokemon[target.species]
      local charge = chargeOf(target, coinCost)
      if charge >= coinCost then
        -- already full: do not spend a coin, evolve now
        return charge, evolveTargetOf(species, itemId), true
      end
      return charge, evolveTargetOf(species, itemId), false
    end

    -- The Gimmighoul Coin on Gen 1: BagMenu removes exactly one coin on
    -- "consumed", which is the one coin each charge spends.
    local function gen1CoinEffect(itemId)
      return {
        needsTarget = true,
        battle = false,
        use = function(context)
          local target = context and context.target
          if type(target) ~= "table" then return "failed", { NO_EFFECT } end
          local charge, evolveTo, full = planCharge(target, itemId, context.data)
          if not charge then return "failed", { NO_EFFECT } end
          if full then
            if evolveTo then
              markEvolving(target)
              return "consumed", nil, { evolveTo = evolveTo }
            end
            return "failed", { NO_EFFECT }
          end
          local nextCharge = charge + 1
          target[chargeField] = nextCharge
          if nextCharge >= coinCost and evolveTo then
            markEvolving(target)
            return "consumed", nil, { evolveTo = evolveTo }
          end
          return "consumed", { chargeText(nextCharge) }
        end,
      }
    end

    -- The Gimmighoul Coin on Gen 2: the record keeps the "stone" action so the
    -- threshold use plays the engine's own evolution animation.  Context
    -- carries no save, so the bag is reached through the Game singleton and
    -- the single coin is removed here (the non-threshold use returns
    -- used=false, which stops Game2 consuming a SECOND one).
    local function gen2CoinEffect(itemId)
      return {
        action = "stone",
        field = true,
        needsTarget = true,
        battle = false,
        use = function(context)
          local Strings = require("src.core.Strings")
          local Evolution = require("src.core.gen2.Evolution")
          local mon = context and context.mon
          local charge, evolveTo, full = planCharge(mon, itemId, context.data)
          if not charge then return { used = false, text = Strings(NO_EFFECT) } end
          if full then
            if not evolveTo then
              return { used = false, text = Strings(NO_EFFECT) }
            end
            markEvolving(mon)
            local entry = Evolution.checkMon(context.data, mon,
              { force = true, item = context.item })
            if entry then return { used = true, evolution = entry } end
            return { used = true, evolution = { method = "EVOLVE_ITEM",
              into = evolveTo, item = itemId } }
          end
          local ok, Game = pcall(require, "src.core.Game")
          local save = ok and type(Game) == "table" and Game.save or nil
          local have = save and save.inventory and save.inventory[itemId] or 0
          if have < 1 then return { used = false, text = Strings(NO_EFFECT) } end
          local nextCharge = charge + 1
          mon[chargeField] = nextCharge
          -- The threshold use plays the engine's stone animation, which spends
          -- the coin itself -- so do NOT remove one here or it is spent twice.
          if nextCharge >= coinCost and evolveTo then
            markEvolving(mon)
            local entry = Evolution.checkMon(context.data, mon,
              { force = true, item = context.item })
            if entry then return { used = true, evolution = entry } end
          end
          -- A below-threshold use reports used=false, so Game2 does not consume
          -- the item; the single coin is spent by hand instead.
          pcall(function() require("src.inventory.Bag").remove(save, itemId, 1) end)
          return { used = false, text = Strings(chargeText(nextCharge)) }
        end,
      }
    end

    for _, slug in ipairs(ids.SLUGS) do
      if not ids.isNative(slug, gen) then
        local itemId = ctx.itemId(slug)
        if itemId and mod.content.items:get(itemId) == nil then
          local name = ctx.itemName(slug)
          local isCoin = (slug == coinSlug)
          -- On Gen 1 an item that is not a plain use-item (a held-item, a
          -- trade item, or a dex item with no row at all) has no field to sit
          -- in, so it becomes a use-on-a-mon tool gated on the level its
          -- G9_ITEM_LEVEL row carries -- and falls back to the g9HeldItem
          -- toggle on a species it does not evolve.
          local allowHold = gen == 1 and not isCoin and useItems[slug] ~= true
          local isUseItem = useItems[slug] == true or isCoin or allowHold
          if gen == 2 then
            -- A use-item item goes to the party (ITEMMENU_PARTY); a held-only
            -- item is field-NOUSE so it only ever reaches the held-item menu.
            -- battleMenu is NOUSE for both: no evolution item is usable
            -- mid-battle, the same refusal a cart stone gives.
            mod.content.items:patch(itemId, {
              id = itemId,
              name = name,
              price = PRICE,
              tossable = true,
              fieldMenu = isUseItem and "ITEMMENU_PARTY" or "ITEMMENU_NOUSE",
              battleMenu = "ITEMMENU_NOUSE",
            })
            registeredItems = registeredItems + 1
            if isUseItem then
              mod.content.item_effects:patch(itemId,
                isCoin and gen2CoinEffect(itemId) or gen2StoneEffect(itemId))
              registeredEffects = registeredEffects + 1
            end
          else
            mod.content.items:patch(itemId, {
              id = itemId,
              name = name,
              price = PRICE,
              effect = itemId,
              needsTarget = true,
              tossable = true,
            })
            registeredItems = registeredItems + 1
            mod.content.item_effects:patch(itemId,
              isCoin and gen1CoinEffect(itemId)
                or gen1Effect(itemId, name, allowHold))
            registeredEffects = registeredEffects + 1
          end
        end
      end
    end

    mod.log:info("g9-evolutions: registered %d evolution item(s) and %d use "
      .. "effect(s) for generation %d", registeredItems, registeredEffects, gen)
  end,
}
