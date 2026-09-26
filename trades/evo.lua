-- trades/evo.lua -- TRADE EVO: the two-pass trade that makes a real trade
-- evolution fire in a single-player game.
--
-- THE TRICK.  The engine evolves the Pokemon the LOCAL game RECEIVES, not the
-- one it sends: src/link/Protocol.lua TradeSession:apply says so in as many
-- words ("trade evolutions like Kadabra -> Alakazam trigger on the receiving
-- side, as on a real link cable") and looks the row up on the received record.
-- So the only way to evolve the player's OWN Pokemon without a second Game Boy
-- is to have it come BACK:
--
--   pass 1  send the chosen mon, receive a mirror of it   (the partner's copy)
--   pass 2  send the mirror,       receive the chosen mon (now on the wire)
--
-- and then run the engine's own trade-evolution on the mon received in pass 2 --
-- the player's original, exactly as a cable round-trip would deliver it.  The
-- mirror is a throwaway display copy: it never touches a save.
--
-- WHEN IT CANNOT.  A species with no trade evolutions (or, on Gold, one whose
-- trade row demands a held item the mon is not carrying, or an Everstone)
-- answers false, and the caller says so instead of running an animation that
-- cannot change anything.
local M = {}

local function shallow(t)
  local out = {}
  for key, value in pairs(t) do out[key] = value end
  return out
end

-- A display copy of a party record.  Nesting the tables the animation and the
-- art readers touch keeps a mutation on the copy (a nickname, a stats block)
-- from reaching the real Pokemon.
function M.copyMon(mon)
  if type(mon) ~= "table" then return nil end
  local copy = shallow(mon)
  for _, key in ipairs({ "dvs", "ivs", "stats" }) do
    if type(mon[key]) == "table" then copy[key] = shallow(mon[key]) end
  end
  if type(mon.moves) == "table" then
    local moves = {}
    for i, move in ipairs(mon.moves) do
      moves[i] = type(move) == "table" and shallow(move) or move
    end
    copy.moves = moves
  end
  return copy
end

-- The species this mon would evolve into on a trade, or nil.  Asks the same
-- engine the real trade path does, so a row a peer mod added is followed and a
-- row this mod recoded (G9_TRADE_LEVEL) is deliberately NOT -- that one is the
-- single-player alternative, not a trade.
function M.target(game, gen, mon)
  if type(mon) ~= "table" or not (game and game.data) then return nil end
  if gen == 2 then
    local ok, Evolution = pcall(require, "src.core.gen2.Evolution")
    if ok and type(Evolution) == "table"
        and type(Evolution.checkMon) == "function" then
      local entry = Evolution.checkMon(game.data, mon, { link = true })
      return entry and entry.into or nil
    end
    return nil
  end
  local ok, Evolution = pcall(require, "src.pokemon.Evolution")
  if ok and type(Evolution) == "table"
      and type(Evolution.pendingFor) == "function" then
    return Evolution.pendingFor(game, mon, { kind = "trade" })
  end
  return nil
end

function M.canEvolve(game, gen, mon)
  return M.target(game, gen, mon) ~= nil
end

-- The two passes, in order.
function M.plan(mon)
  local mirror = M.copyMon(mon)
  return {
    { sent = mon, received = mirror, verb = "TRADE EVO" },
    { sent = mirror, received = mon, verb = "TRADE EVO" },
  }
end

-- Run the engine's own trade evolution on `mon`.  `index` must be its slot in
-- `save.party`, because Gold's animation writes the evolved record back into
-- the party itself (src/ui/gen2/EvolutionAnim.lua commit).  onDone(evolved) is
-- called once, evolved=false when nothing fired.
function M.evolve(game, gen, mon, save, index, onDone)
  local done = onDone or function() end
  if not M.target(game, gen, mon) then
    done(false)
    return false
  end
  if gen == 2 then
    local Screens = require("src.ui.Screens")
    local Evolution = require("src.core.gen2.Evolution")
    local entry = Evolution.checkMon(game.data, mon, { link = true })
    if not entry then
      done(false)
      return false
    end
    if not (game.stack and type(game.stack.push) == "function") then
      done(true)
      return true
    end
    local party = (save and save.party) or {}
    Screens.push(game, "Gen2EvolutionAnim", {
      mon = mon,
      entry = entry,
      index = index or 1,
      party = party,
      save = save,
      -- A trade evolution cannot be cancelled with B on the cart either
      -- (engine/pokemon/evolve.asm .pressed_b is gated on wForceEvolution) --
      -- and the local game is the RECEIVER here, so nothing may stop it.
      force = true,
      onDone = function(result)
        done(true, result)
      end,
    })
    return true
  end
  local Evolution = require("src.pokemon.Evolution")
  -- Evolution.request plays the whole movie (g9-gui's modern surface when it
  -- is installed) and calls back once it has applied the evolution.
  Evolution.request(game, mon, { kind = "trade" }, function() done(true) end)
  return true
end

return M
