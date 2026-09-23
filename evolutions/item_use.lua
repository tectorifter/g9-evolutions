-- USE-ITEM evolutions -- the item-on-a-Pokemon trigger (every stone, plus the
-- items that only exist to evolve one species).
--
-- These rows deliberately keep the ENGINE's own method id: `ITEM` on Gen 1 and
-- `EVOLVE_ITEM` on Gen 2.  That is not laziness -- it is forced by how the
-- engine reaches them.  On Red/Blue/Yellow the item-use machinery is keyed
-- directly on the spelling, not on the registry:
--
--   * src/inventory/ItemEffects.lua  -- `if evo.method == "ITEM" and evo.item
--     == itemId` decides whether a stone evolves the target at all;
--   * src/ui/PartyMenu.lua           -- the same test drives the ABLE / NOT
--     ABLE column the stone's party picker shows;
--   * src/link/Protocol.lua          -- and the same idea for `TRADE`.
--
-- Renaming the id would take evolution stones away from all three.  So this
-- mod owns the ROW (which target, which item, on which generation) and the
-- engine keeps owning the OPERATOR.  The five stones the cart already has are
-- remapped to that cart's real id rather than re-registered; every other
-- evolution item is registered by items/evolution_items.lua, which also wires
-- the item-use effect the engine needs to reach the row.
--
-- The install step is therefore a guard: it proves the operator this mod is
-- relying on is still present, and logs loudly if a future engine changed its
-- id, instead of shipping rows that silently never fire.
return {
  -- The engine method ids item rows reference, per generation.
  ids = { gen1 = "ITEM", gen2 = "EVOLVE_ITEM" },

  install = function(mod, ctx)
    local path = ctx.gen == 2 and "src.core.gen2.Evolution"
      or "src.pokemon.Evolution"
    local ok, Evolution = pcall(require, path)
    if not ok or type(Evolution) ~= "table" or type(Evolution.METHODS) ~= "table" then
      mod.log:warn("g9-evolutions: could not inspect %s -- item evolutions "
        .. "rely on its %s operator", path, ctx.gen == 2 and "EVOLVE_ITEM" or "ITEM")
      return
    end
    local id = ctx.gen == 2 and "EVOLVE_ITEM" or "ITEM"
    if type(Evolution.METHODS[id]) ~= "table" then
      mod.log:warn("g9-evolutions: %s no longer defines the %s method -- "
        .. "item evolutions may not fire on this engine", path, id)
    end
  end,
}
