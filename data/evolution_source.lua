-- Reads national_dex's evolution payload and hands back plain specs.
--
-- national_dex publishes evolutionsOf(id) -- a DISPLAY record: chain, stage,
-- evolvesFrom/evolvesInto and, per target, a list of `methods`.  Its own
-- header is explicit that none of this is the registered `evolutions` field
-- (which stays {} on every record it supplies), so a consumer must convert it
-- into engine rows itself.  This file is that consumer's read half.
--
-- One spec per TARGET, using methods[1].  The API documents methods as "every
-- distinct way the evolution is known to happen, the one PokeAPI marks current
-- first (isDefault)"; the first entry is therefore the canonical route and,
-- critically, is the one that avoids PokeAPI's earlier-generation quirks (e.g.
-- Cyndaquil -> Quilava lists the ordinary level-14 method first and a
-- Hisui-only level-17 method second, so reading methods[1] keeps Cyndaquil out
-- of the regional system entirely).
--
-- Every reply is a deep copy (national_dex's own doing), so mutating a spec
-- can never reach the mod's cached shard.  Rows are built from specs, never
-- mutated in place.
local M = {}

-- Does this national_dex install carry the evolution API at all?  Version 3
-- added evolutionsOf/listEvolutions; an older dex simply has neither.
function M.available(exports)
  if type(exports) ~= "table" then return false end
  if type(exports.evolutionsOf) ~= "function" then return false end
  local version = tonumber(exports.apiVersion) or 0
  if version < 3 then return false end
  return true
end

-- Every species id national_dex carries an evolution record for, or {} when
-- the list cannot be read.
function M.ids(exports)
  if not M.available(exports) then return {} end
  local ok, list = pcall(exports.listEvolutions)
  if not ok or type(list) ~= "table" then return {} end
  local out = {}
  for _, id in ipairs(list) do
    if type(id) == "string" and id ~= "" then out[#out + 1] = id end
  end
  return out
end

-- Every evolution TARGET, flattened into specs:
--   { from = <species id>, target = <species id>, method = <method table>,
--     targetName = <display name or nil> }
-- A record with no evolvesInto, or a target with no methods, contributes
-- nothing rather than a half-built row.
function M.specs(exports, ids)
  ids = ids or M.ids(exports)
  local out = {}
  for _, from in ipairs(ids) do
    local ok, record = pcall(exports.evolutionsOf, from)
    if ok and type(record) == "table" then
      for _, into in ipairs(record.evolvesInto or {}) do
        local methods = type(into) == "table" and into.methods or nil
        local method = type(methods) == "table" and methods[1] or nil
        if type(into) == "table" and type(into.id) == "string"
            and into.id ~= "" and type(method) == "table" then
          out[#out + 1] = {
            from = from,
            target = into.id,
            method = method,
            targetName = into.name,
          }
        end
      end
    end
  end
  return out
end

-- The canonical method table for a target, or nil.  Exposed so the tests can
-- build a spec without going through listEvolutions.
function M.firstMethod(into)
  if type(into) ~= "table" then return nil end
  local methods = into.methods
  if type(methods) ~= "table" then return nil end
  return methods[1]
end

return M
