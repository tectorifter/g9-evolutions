-- ui/mon_art.lua -- the one place the trade screens ask for a Pokemon's
-- picture, so the modern animation, the party list on the trade screen and the
-- wonder-trade result all draw a species the same way.
--
-- TWO SOURCES, PACK FIRST.  A Pokemon's front battle art and its party icon
-- come from the g9-battle-sprites mod when it is installed -- its always-on
-- `frontArt` / `iconArtHD` / `iconArt16` exports, reached through
-- mod.find("g9-battle-sprites").exports (the same channel g9-gui's portraits
-- use, and the only one there is: a peer mod's files are not readable).  With
-- that mod absent, disabled, or missing a sheet for the species, the ENGINE's
-- own front pic and icon are drawn in the same slot, so a screen is never
-- empty.
--
-- THE SIZE RULE IS THE PACK'S OWN.  Art is drawn at its authored pixel size
-- and stepped DOWN by a whole integer divisor only when it outgrows the slot
-- -- never up-scaled -- which is what keeps a Weedle a Weedle beside an
-- Eternatus and stops the creature changing shape with the screen.  The icon
-- is the exception: a caller asks for a BOX (design units) and the icon is
-- scaled to sit inside it, because an icon is meant to read at one size
-- wherever it is drawn (the request's "adjusted size to not deform it with
-- bigger/smaller screen size").
local M = {}

-- The sprites mod's exports table, memoised once resolved.  A MISS is NOT
-- remembered: g9-gui's own portraits re-ask their peer every frame, and the
-- one boot that matters here (g9-evolutions loading before the sprites mod
-- finishes registering) would otherwise pin this to nil for the session and
-- leave every icon on the engine fallback.  Once a table with the icon arms
-- answers, it is kept.
local cached

function M.peer(mod)
  if cached then return cached end
  local handle = mod and mod.find and mod.find("g9-battle-sprites") or nil
  local ex = type(handle) == "table" and handle.exports or nil
  if type(ex) == "table"
      and (type(ex.frontArt) == "function"
        or type(ex.iconArtHD) == "function"
        or type(ex.iconArt16) == "function") then
    cached = ex
    return cached
  end
  return nil
end

-- forget the memo when the engine flushes its asset caches (dev hot reload or
-- a mod's sprite swap landing), the same hook g9-gui's portraits use
local Assets = nil
do
  local ok, value = pcall(require, "src.render.Assets")
  if ok and type(value) == "table" then Assets = value end
end
if Assets and type(Assets.register) == "function" then
  pcall(Assets.register, function() cached = nil end)
end

local function image(path)
  if not path then return nil end
  local Assets2 = Assets or require("src.render.Assets")
  local ok, img = pcall(Assets2.image, path)
  return ok and img or nil
end

local function quadOf(q)
  if type(q) == "table" and q.full then return q.full end
  return q
end

-- The engine's own front-pic path for a mon, pcall-guarded (a species the
-- running cart has no sheet for answers nil, not an error).
local function engineFront(game, mon)
  local data = game and game.data
  if not (data and mon) then return nil end
  local Sprites = require("src.pokemon.Sprites")
  local path
  local okP, value = pcall(Sprites.path, data, mon.species, "front",
    { mon = mon, kind = "trade" })
  if okP then path = value end
  if not path then
    local def = data.pokemon and data.pokemon[mon.species]
    path = def and def.spriteFront
  end
  local img = image(path)
  return img
end

-- Draw an Image inside the box (x, y, w, h), never up-scaled.  `anchor` is
-- "center" (the default) or "bottom": the pack's portrait is TRIMMED to the
-- creature, so it carries no floor of its own, and a caller that slots it where
-- the cart's padded 56px sprite stood wants the feet on the slot's floor rather
-- than the picture floating in the middle of it.  Answers the drawn rectangle
-- so a caller can mark it full-colour for the engine's palette post-pass.
local function blit(img, x, y, w, h, anchor)
  if not (img and type(img.getDimensions) == "function") then return false end
  local iw, ih = img:getDimensions()
  if not (iw and ih and iw > 0 and ih > 0) then return false end
  local scale = 1
  if iw > w or ih > h then
    scale = 1 / math.max(1, math.ceil(math.max(iw / w, ih / h)))
  end
  local dw, dh = iw * scale, ih * scale
  local dx = math.floor(x + (w - dw) * 0.5)
  local dy = (anchor == "bottom") and math.floor(y + (h - dh))
    or math.floor(y + (h - dh) * 0.5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, dx, dy, 0, scale, scale)
  return true, dx, dy, dw, dh
end

-- The mon's front battle art centred in a box.  Answers true when something
-- was drawn.  `opts.natural` skips the pack and draws the engine's own pic at
-- its own size (used where a caller wants the cart's art specifically);
-- `opts.anchor` is passed through to blit ("bottom" stands the creature on the
-- box's floor).  On success it also answers the drawn rectangle.
function M.front(mod, game, mon, x, y, w, h, opts)
  opts = opts or {}
  if type(mon) ~= "table" then return false end
  local ex = not opts.natural and M.peer(mod) or nil
  if ex and type(ex.frontArt) == "function" then
    local result = { pcall(ex.frontArt, mon) }
    if result[1] and result[2] then
      -- answers (image, w, h, box); the image is already trimmed to frame 1
      local drawn, dx, dy, dw, dh = blit(result[2], x, y, w, h, opts.anchor)
      if drawn then return true, dx, dy, dw, dh end
    end
  end
  return blit(engineFront(game, mon), x, y, w, h, opts.anchor)
end

-- Does the pack hold its OWN picture for this mon?  The native trade movie has
-- to know this BEFORE it draws, because hiding the engine's own sprite is only
-- right when there is something to put in its place.  A sheet still baking (the
-- pack answers nil while it decodes) says false, so the vanilla sprite stands
-- for those frames -- never a hole.
function M.hasPortrait(mod, mon)
  if type(mon) ~= "table" then return false end
  local ex = M.peer(mod)
  if not (ex and type(ex.frontArt) == "function") then return false end
  local ok, img = pcall(ex.frontArt, mon)
  return (ok and img ~= nil) and true or false
end

-- The engine's own icon registry, resolved exactly as src/ui/PartyMenu.lua
-- resolves it: a per-species override (icons.bySpecies) or the record's own
-- `icon`, else the dex-indexed default (icons.byDex[def.dex]); that name is a
-- key into icons.icons.  Gen 2 keeps its icons in a different registry
-- (data.gen2Icons: species -> sheet id -> { image }), the one its own TradeAnim
-- reads.  Everything is pcall-guarded: a cart/mod shape this does not know
-- answers nil rather than raising inside a draw.
local function engineIconPath(game, mon)
  local data = game and game.data
  if not (data and mon) then return nil end
  local g2 = data.gen2Icons
  if type(g2) == "table" then
    local id = g2.species and g2.species[mon.species]
    local entry = id and g2.icons and g2.icons[id]
    if type(entry) == "table" and type(entry.image) == "string" then
      return entry.image
    end
  end
  local icons = data.icons
  if type(icons) ~= "table" then return nil end
  local def = data.pokemon and data.pokemon[mon.species]
  local name, path, trueColor
  local entry = (icons.bySpecies and icons.bySpecies[mon.species])
             or (def and def.icon)
  if type(entry) == "string" then
    name = entry
    path = icons.icons and icons.icons[entry]
  elseif type(entry) == "table" then
    path = entry.image
    trueColor = entry.trueColor
  end
  if type(path) ~= "string" then
    name = def and def.dex and icons.byDex and icons.byDex[def.dex]
    path = name and icons.icons and icons.icons[name]
  end
  if type(path) ~= "string" then return nil end
  local okS, Sprites = pcall(require, "src.pokemon.Sprites")
  if okS and type(Sprites) == "table"
      and type(Sprites.iconPath) == "function" then
    local okC, hooked = pcall(Sprites.iconPath, data, mon, path,
      { name = name, trueColor = trueColor })
    if okC and type(hooked) == "string" then path = hooked end
  end
  return path
end

-- The engine's own icon Image.  Gen 1 icon art is 2bpp OBJ art and PartyMenu
-- bakes it through the running OBP0 palette; do the same when the renderer is
-- there, else take the raw image.  Answers (image, cellPixels).
local function engineIcon(game, mon)
  local path = engineIconPath(game, mon)
  if not path then return nil end
  local okPF, PF = pcall(require, "src.render.PaletteFX")
  if okPF and type(PF) == "table" and type(PF.usesSpriteObp) == "function" then
    local okUse, use = pcall(PF.usesSpriteObp)
    if okUse and use then
      local okO, og = pcall(PF.ogObjNormal)
      local okSR, SR = pcall(require, "src.render.SpriteRenderer")
      if okO and og and okSR and type(SR) == "table"
          and type(SR.obpImage) == "function" then
        local okI, img = pcall(SR.obpImage, path, og[1], og[2])
        if okI and img then return img, 16 end
      end
    end
  end
  return image(path), 16
end

-- The mon's party icon, scaled to fit a `size` x `size` box (design units),
-- centred on (cx, cy).  `frame` is an optional 0-based animation frame; the
-- pack's resting frame (0) is the default so an icon holds still.  Answers
-- true when something was drawn.
function M.icon(mod, game, mon, cx, cy, size, frame)
  if type(mon) ~= "table" or not (size and size > 0) then return false end
  local ex = M.peer(mod)
  local img, q, cell
  if ex then
    local fn = ex.iconArtHD or ex.iconArt16
    if type(fn) == "function" then
      local ok, quads, image2, cellpx = pcall(fn, mon, frame)
      if ok and image2 and type(quads) == "table" then
        q = quadOf(quads)
        img = image2
        cell = tonumber(cellpx) or 0
        if cell and q and type(q.getViewport) == "function" then
          local okV, _, _, qw, qh = pcall(q.getViewport, q)
          if okV and qw and qh then cell = qw end
        end
      end
    end
  end
  if not img then
    local eimg, ecell = engineIcon(game, mon)
    img, cell, q = eimg, ecell or 16, nil
  end
  if not (img and type(img.getDimensions) == "function") then
    -- a drawn stand-in, so a slot is never a hole
    love.graphics.setColor(0.2, 0.3, 0.45, 1)
    love.graphics.circle("fill", cx, cy, size * 0.4)
    love.graphics.setColor(1, 1, 1, 1)
    return false
  end
  cell = tonumber(cell) or 16
  if cell <= 0 then cell = 16 end
  local scale = size / cell
  -- Small (16px) icon art is kept on whole-number scales so it stays crisp;
  -- the pack's 64px HD cell takes the exact ratio.
  if cell <= 16 then
    scale = math.max(1, math.floor(size / cell))
  end
  local dw, dh = cell * scale, cell * scale
  love.graphics.setColor(1, 1, 1, 1)
  if q and type(q.getViewport) == "function" then
    love.graphics.draw(img, q, math.floor(cx - dw * 0.5), math.floor(cy - dh * 0.5),
      0, scale, scale)
  else
    local iw, ih = img:getDimensions()
    local sq = math.min(iw, ih, cell)
    local quad = love.graphics.newQuad(0, 0, sq, sq, iw, ih)
    love.graphics.draw(img, quad, math.floor(cx - dw * 0.5),
      math.floor(cy - dh * 0.5), 0, scale, scale)
  end
  return true
end

return M
