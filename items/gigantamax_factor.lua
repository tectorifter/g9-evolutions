-- The Gigantamax Factor item ("G-FACTOR"): a use-on-a-mon item that marks a
-- Gigantamax-capable species as able to Gigantamax, and is CONSUMED doing so.
--
-- Its id, display name, price and the eligibility test all come from
-- data/gigantamax_factor.lua, shared with the PC row (ui/pc_maxfactor.lua) that
-- mints it -- so the item a player is handed is the item the PC describes.
--
-- Registration is `:patch` on both the item and its effect, never `:register`,
-- for the reason items/evolution_items.lua's header works through at length:
-- patch layers and cannot be refused, where the override verb replaces a value
-- and errors on an id that already exists (a peer mod that already registered
-- the id, or a second load, would strand every row pointing at it).
--
-- The use is refused WITHOUT consuming on two targets: a species that is not
-- Gigantamax-capable (nothing to grant), and a Pokemon that already carries the
-- Factor (a second one would be wasted).  Both are the engine's own "It won't
-- have any effect." refusal -- the same line a cart stone gives on a miss.
local NO_EFFECT = "It won't have\nany effect."
local ALREADY = "It already has\nthe Factor!"

return {
  install = function(mod, ctx, GF)
    if type(GF) ~= "table" then
      mod.log:warn("g9-evolutions: data/gigantamax_factor.lua did not load "
        .. "-- the G-FACTOR item is off")
      return
    end
    local gen = ctx.gen
    local id = GF.ITEM_ID

    -- The name a line prints.  A nickname wins, the species id is the last
    -- resort (the same order battle_forms' own monName uses).
    local function monName(mon)
      return tostring(mon and (mon.nickname or mon.name or mon.species) or "It")
    end

    -- The one use-on-a-mon body; the two generations wrap it in their own
    -- result shapes below (they genuinely differ, the same pair every item in
    -- items/evolution_items.lua spells out).  Answers ok, text.
    local function grant(mon)
      if type(mon) ~= "table" then return false, NO_EFFECT end
      if GF.hasFactor(mod, mon) then return false, ALREADY end
      if not GF.isEligible(mod, mon.species) then return false, NO_EFFECT end
      GF.setFactor(mod, mon)
      return true, ("%s can now\nGigantamax!"):format(monName(mon))
    end

    if gen == 2 then
      local Strings = require("src.core.Strings")
      mod.content.items:patch(id, {
        id = id,
        name = GF.NAME,
        price = GF.PRICE,
        needsTarget = true,
        tossable = true,
        -- A party-use item: the ITEM pocket, usable on a mon from the field,
        -- never mid-battle (the same pair battle_forms' own Dynamax Candy
        -- carries).
        fieldMenu = "ITEMMENU_PARTY",
        battleMenu = "ITEMMENU_NOUSE",
      })
      mod.content.item_effects:patch(id, {
        needsTarget = true,
        action = "form",
        field = true,
        battle = false,
        use = function(context)
          local ok, text = grant(context and context.mon)
          return { used = ok and true or false, text = Strings(text) }
        end,
      })
    else
      mod.content.items:patch(id, {
        id = id,
        name = GF.NAME,
        price = GF.PRICE,
        effect = id,
        needsTarget = true,
        tossable = true,
      })
      mod.content.item_effects:patch(id, {
        needsTarget = true,
        battle = false,
        field = true,
        use = function(context)
          local ok, text = grant(context and context.target)
          return ok and "consumed" or "failed", { text }
        end,
      })
    end

    mod.exports.gigantamaxFactorItem = id
    mod.log:info("g9-evolutions: registered the %s item (use on a "
      .. "Gigantamax-capable species)", GF.NAME)
  end,
}
