-- The three regional evolution items, and the Gen 1 effect that "holds" one.
--
--   PRIMALAMBER      Hisui
--   SOVEREIGNCROWN   Galar
--   SOLSTICENECTAR   Alola
--
-- Registration shape follows battle_forms' own item records, because those are
-- the proven ones: an id, a name, a price, a Gen 1 bag byte and -- on Gen 1 -- an
-- `effect` pointing at an item_effects record, plus Gold's fieldMenu/battleMenu
-- "no USE verb" pair.  The Gen 2 record deliberately does NOT set `keyItem`,
-- because a key item cannot be given to a Pokemon on Gold and these items exist
-- precisely to be held; on Gen 1 the record does set it, because there they are
-- a use-on-a-mon tool rather than a held item and must not be tossed or sold.
--
-- Gen 1 placement: use-on-a-mon.  The engine has no held-item field, so the
-- effect marks the mon with `g9HeldItem` (the same slot g9-battle-engine's
-- held-item API uses) and returns "kept" -- the item is re-usable and NEVER
-- consumed, so one Amber can carry a whole team up their Hisuian lines.  Using
-- it on the same mon again takes the mark back off, so a misclick is fixable.
local NAMES = {
  hisui = "Primal Amber",
  galar = "Sovereign Crown",
  alola = "Solstice Nectar",
}

-- Gen 1 bag bytes.  Vanilla Red/Blue/Yellow occupy 1-97 with no gaps, and
-- battle_forms' own tables fill 98-233, so 234+ is the first range that cannot
-- collide with either the cart or that mod.  These three are permanent: moving
-- one would turn an item already in a bag into a different one.
local INDICES = { hisui = 234, galar = 235, alola = 236 }

-- Nominal.  A region item is a mechanic, not a purchase, but a zero price is
-- how a bag's own sell arithmetic divides by zero -- so it carries a real one.
local PRICE = 10000

local function gen1Record(itemId, name, index, region)
  return {
    id = itemId,
    name = name,
    price = PRICE,
    index = index,
    effect = itemId,
    needsTarget = true,
    keyItem = true,
    tossable = false,
  }
end

local function gen2Record(itemId, name)
  return {
    id = itemId,
    name = name,
    price = PRICE,
    index = nil,
    tossable = false,
    fieldMenu = "ITEMMENU_NOUSE",
    battleMenu = "ITEMMENU_NOUSE",
  }
end

return {
  NAMES = NAMES,
  INDICES = INDICES,

  install = function(mod, ctx)
    local Held = ctx.held
    for _, region in ipairs({ "hisui", "galar", "alola" }) do
      local itemId = ctx.regionItems[region]
      local name = NAMES[region]
      if ctx.gen == 2 then
        mod.content.items:patch(itemId, gen2Record(itemId, name))
      else
        local index = INDICES[region]
        mod.content.items:patch(itemId,
          gen1Record(itemId, name, index, region))
        mod.content.item_effects:patch(itemId, {
          needsTarget = true,
          battle = false,
          use = function(context)
            local target = context and context.target
            if type(target) ~= "table" then
              return "failed", { "It won't have\nany effect." }
            end
            -- Toggle: using the same item on the same mon again lets go.
            if Held.of(target, 1) == itemId then
              Held.set(target, 1, nil)
              return "kept", { name .. " was put\nback." }
            end
            Held.set(target, 1, itemId)
            return "kept", { name .. " is now held!" }
          end,
        })
      end
    end
  end,
}
