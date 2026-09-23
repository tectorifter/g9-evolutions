-- Held-item access, generation-aware.
--
-- Gen 2 party records carry a real held item in `mon.item` -- the same field
-- Gold's own evolution code reads.  Gen 1 has NO held-item field anywhere in
-- the engine, so the one way to satisfy a "while holding X" condition there is
-- to keep the mark on the mon ourselves.  This mod stores it as `g9HeldItem`,
-- the exact field name g9-battle-engine's held-item API already uses, so the
-- two mods share one slot instead of fighting over two.
--
-- The accessor below is deliberately tolerant: it prefers `mon.item` when the
-- running game has it, then `g9HeldItem`, and answers nil for anything else.
-- A malformed save (a number, a table) reads as "holding nothing" rather than
-- throwing inside an evolution walk.
local M = {}

-- The regional evolution items this mod introduces.  The id is the
-- national_dex item vocabulary (uppercase, no separators) and the value is the
-- region token the row-builder encodes in a G9_REGION_* method id.
M.REGION_ITEMS = {
  hisui = "PRIMALAMBER",
  galar = "SOVEREIGNCROWN",
  alola = "SOLSTICENECTAR",
}

-- item id -> region token, built once for the reverse lookup.
local BY_ITEM = {}
for region, itemId in pairs(M.REGION_ITEMS) do BY_ITEM[itemId] = region end

-- The region token a region item id names, or nil for any other item.
function M.regionOfItem(itemId)
  if type(itemId) ~= "string" then return nil end
  return BY_ITEM[itemId]
end

-- True for the three region items, whatever their spelling.
function M.isRegionItem(itemId)
  return M.regionOfItem(itemId) ~= nil
end

local function asItem(value)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

-- What `mon` is currently holding, or nil.  `gen` is 1 or 2; on Gen 2
-- `mon.item` is authoritative, on Gen 1 `g9HeldItem` is, and either falls
-- back to the other so a mark written by a peer mod is still seen.
function M.of(mon, gen)
  if type(mon) ~= "table" then return nil end
  if gen == 2 then
    return asItem(mon.item) or asItem(mon.g9HeldItem)
  end
  return asItem(mon.g9HeldItem) or asItem(mon.item)
end

-- Record `itemId` as held.  On Gen 2 this writes the engine's own field; on
-- Gen 1 it writes this mod's slot.  Returns the field name used, or false when
-- the mon could not be written.
function M.set(mon, gen, itemId)
  if type(mon) ~= "table" then return false end
  itemId = asItem(itemId)
  if gen == 2 then
    mon.item = itemId
    return "item"
  end
  mon.g9HeldItem = itemId
  return "g9HeldItem"
end

-- Forget whatever is held (both fields, so a Gen 1 mark left by an older save
-- and a Gen 2 field can never disagree).
function M.clear(mon)
  if type(mon) ~= "table" then return false end
  mon.item = nil
  mon.g9HeldItem = nil
  return true
end

-- Is `mon` holding this exact item id?
function M.holds(mon, gen, itemId)
  if type(itemId) ~= "string" or itemId == "" then return false end
  return M.of(mon, gen) == itemId
end

return M
