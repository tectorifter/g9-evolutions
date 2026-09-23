-- The item-id vocabulary g9-evolutions speaks, in ONE place.
--
-- national_dex's evolution records name their items as PokeAPI slugs
-- ("thunder-stone", "razor-claw", "kings-rock"), while the engine keys its item
-- registry by an id that differs BOTH between items and between generations.
-- The prior art (g9-battle-engine / its gen2_vocab pass) established the two
-- spellings:
--
--   * Gen 1 (Red/Blue/Yellow) calls the five native stones with underscores:
--     FIRE_STONE, WATER_STONE, THUNDER_STONE, LEAF_STONE, MOON_STONE.
--   * Gen 2 (Gold/Silver/Crystal) spells the six stones the cart owns as
--     FIRE_STONE, WATER_STONE, THUNDERSTONE, LEAF_STONE, MOON_STONE and
--     SUN_STONE (verified against src/core/gen2/ItemEffects.lua's own stone
--     table), and every OTHER Gold-native item with no separator at all
--     (KINGSROCK, METALCOAT, DRAGONSCALE, UPGRADE, DUBIOUSDISC, ...).
--
-- Every item national_dex's own catalogue names uses that same separator-free
-- uppercase spelling (its item tests assert "every id is separator-free
-- uppercase", and it deliberately DESCRIBES items without registering them).
-- The rule here is therefore: the handful of stones a cart already owns are
-- remapped to that cart's real id, and everything else keeps national_dex's
-- own id -- so a registered item and a national_dex catalogue entry agree by
-- construction, which is the compatibility the user asked for.
local M = {}

-- The five stones the engine already owns, per generation.  A slug in this
-- table is remapped to the cart's real id and is NOT re-registered as a second,
-- dead copy -- a duplicate record on an id the cart already holds is how a gym
-- prize ends up handing out the wrong item.
M.NATIVE_GEN1 = {
  ["fire-stone"] = "FIRE_STONE",
  ["water-stone"] = "WATER_STONE",
  ["thunder-stone"] = "THUNDER_STONE",
  ["leaf-stone"] = "LEAF_STONE",
  ["moon-stone"] = "MOON_STONE",
}

M.NATIVE_GEN2 = {
  ["fire-stone"] = "FIRE_STONE",
  ["water-stone"] = "WATER_STONE",
  ["thunder-stone"] = "THUNDERSTONE",
  ["leaf-stone"] = "LEAF_STONE",
  ["moon-stone"] = "MOON_STONE",
  ["sun-stone"] = "SUN_STONE",
}

-- Every distinct item slug the current national_dex evolution data names --
-- use-item triggers and held-item conditions alike, plus the Gimmighoul Coin
-- (which the `gimmighoul-coins` trigger implies rather than naming on its row).
-- Kept as a plain array so registration order is deterministic (a Lua table
-- iterated with pairs() has none, and a stable shelf/index order matters on
-- Gen 1).
M.SLUGS = {
  "auspicious-armor", "black-augurite", "chipped-pot", "cracked-pot",
  "dawn-stone", "deep-sea-scale", "deep-sea-tooth", "dragon-scale",
  "dubious-disc", "dusk-stone", "electirizer", "fire-stone",
  "galarica-cuff", "galarica-wreath", "gimmighoul-coin", "ice-stone", "kings-rock",
  "leaf-stone", "magmarizer", "malicious-armor", "masterpiece-teacup",
  "metal-alloy", "metal-coat", "moon-stone", "oval-stone", "peat-block",
  "prism-scale", "protector", "razor-claw", "razor-fang", "reaper-cloth",
  "sachet", "scroll-of-darkness", "scroll-of-waters", "shiny-stone",
  "sun-stone", "sweet-apple", "syrupy-apple", "tart-apple",
  "thunder-stone", "unremarkable-teacup", "up-grade", "water-stone",
  "whipped-dream",
}

-- The engine id for a slug on a given generation.  `gen` is 1 or 2; anything
-- else falls back to the Gen 1 spelling.
function M.engineId(slug, gen)
  if type(slug) ~= "string" or slug == "" then return nil end
  local native = (gen == 2) and M.NATIVE_GEN2 or M.NATIVE_GEN1
  if native[slug] then return native[slug] end
  return (slug:upper():gsub("[^%u%d]", ""))
end

-- The national_dex catalogue id for a slug -- the no-separator spelling,
-- independent of generation.  This is the id to ask national_dex's itemById
-- about when a display name is wanted.
function M.catalogueId(slug)
  if type(slug) ~= "string" or slug == "" then return nil end
  return (slug:upper():gsub("[^%u%d]", ""))
end

-- True when the slug is one of the five stones the running cart already owns
-- under its own id, so registration must be skipped.
function M.isNative(slug, gen)
  local native = (gen == 2) and M.NATIVE_GEN2 or M.NATIVE_GEN1
  return native[slug] ~= nil
end

-- A human name for a slug, used only when national_dex cannot answer one:
-- "deep-sea-tooth" -> "Deep Sea Tooth".
function M.displayName(slug)
  if type(slug) ~= "string" then return tostring(slug) end
  local out = slug:gsub("-", " ")
  out = out:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end)
  return out
end

return M
