-- ui/style.lua -- the inspectors' look, in one place.
--
-- Two presentations out of one palette:
--
--   * MODERN is the g9-gui ("modern UI & stats") look: dark translucent
--     panels, a top highlight and a soft shadow, an accent-blue rule and
--     chevrons, gold for figures, and the Saira face (SIL OFL 1.1 -- the TTFs
--     and OFL.txt ship beside this file).  Saira is the proportional humanist
--     sans g9-gui chose to stand in for FINAL FANTASY XII's menu type; shipping
--     our own copy means the inspectors look like that suite whether or not it
--     is installed.  Sizes are small here (the panel is a popup, not a page):
--     16 body, 11 secondary, 20 title.
--
--   * NATIVE is the cart's own look: an opaque white box with a black border
--     and the engine's bundled Plain Pixel face (game.data.font.ttf.file), the
--     same fallback g9-gui uses.  It reads as a Game Boy window, so a player
--     who has not installed the modern UI gets an inspector that matches the
--     screen around it.
--
-- Nothing here touches Renderer:setUISize/setCanvas (the documented
-- silent-crash hazard from inside a state's draw).  A screen answers
-- :uiSize() and Game:draw sizes the surface.
--
-- Every text entry goes through scrub() first: LÖVE's font engine raises
-- ("UTF-8 decoding error") on a malformed byte, and names/strings can arrive
-- from a save, another mod, or a ROM cut mid-glyph.
return function(mod)
  local Style = {}

  Style.col = {
    void      = { 0.043, 0.055, 0.086, 1.00 },
    panel     = { 0.070, 0.092, 0.133, 0.96 },
    panelDeep = { 0.036, 0.050, 0.078, 0.98 },
    panelLit  = { 0.125, 0.165, 0.240, 0.98 },
    row       = { 0.115, 0.150, 0.220, 0.60 },
    rowLit    = { 0.220, 0.330, 0.460, 0.60 },
    border    = { 0.290, 0.380, 0.520, 0.70 },
    borderLit = { 0.520, 0.690, 0.900, 0.95 },
    shine     = { 1.000, 1.000, 1.000, 0.09 },
    ink       = { 0.930, 0.950, 0.990, 1.00 },
    inkDim    = { 0.620, 0.680, 0.790, 1.00 },
    inkFaint  = { 0.360, 0.420, 0.530, 1.00 },
    accent    = { 0.470, 0.800, 1.000, 1.00 },
    accentDim = { 0.210, 0.400, 0.560, 1.00 },
    gold      = { 0.960, 0.800, 0.360, 1.00 },
    good      = { 0.380, 0.880, 0.480, 1.00 },
    warn      = { 0.960, 0.790, 0.270, 1.00 },
    bad       = { 0.950, 0.380, 0.360, 1.00 },
    shadow    = { 0.000, 0.000, 0.000, 0.55 },
    black     = { 0.000, 0.000, 0.000, 1.00 },
    white     = { 1.000, 1.000, 1.000, 1.00 },
  }
  local C = Style.col

  -- ------------------------------------------------------------- UTF-8 guard
  local function scrub(s)
    if type(s) ~= "string" then return s end
    if not s:find("[\128-\255]") then return s end
    local out, i, n, start = {}, 1, #s, 1
    while i <= n do
      local b = s:byte(i)
      local len
      if b < 0x80 then len = 1
      elseif b >= 0xC2 and b <= 0xDF then len = 2
      elseif b >= 0xE0 and b <= 0xEF then len = 3
      elseif b >= 0xF0 and b <= 0xF4 then len = 4
      end
      local ok = len ~= nil and i + len - 1 <= n
      if ok and len > 1 then
        for j = i + 1, i + len - 1 do
          local c = s:byte(j)
          if c < 0x80 or c > 0xBF then ok = false break end
        end
        if ok then
          local b2 = s:byte(i + 1)
          if (b == 0xE0 and b2 < 0xA0) or (b == 0xED and b2 > 0x9F)
              or (b == 0xF0 and b2 < 0x90) or (b == 0xF4 and b2 > 0x8F) then
            ok = false
          end
        end
      end
      if ok then
        i = i + len
      else
        out[#out + 1] = s:sub(start, i - 1) .. "\xEF\xBF\xBD"
        i = i + 1
        start = i
      end
    end
    if start > n then return table.concat(out) end
    out[#out + 1] = s:sub(start)
    return table.concat(out)
  end
  Style.scrub = scrub

  -- --------------------------------------------------------------- fonts
  local FONT_REGULAR = "assets/fonts/Saira-Regular.ttf"
  local FONT_BOLD = "assets/fonts/Saira-SemiBold.ttf"

  local function baseName(path)
    return tostring(path or ""):match("[^/\\]+$") or ""
  end

  local function newFileData(bytes, name)
    local fn = (love.data and love.data.newFileData)
      or (love.filesystem and love.filesystem.newFileData)
    if not fn then return nil end
    local ok, fd = pcall(fn, bytes, name)
    if not (ok and fd) then ok, fd = pcall(fn, bytes) end
    return (ok and fd) or nil
  end

  local function tryFont(a, size)
    if not a then return nil end
    local ok, obj = pcall(love.graphics.newFont, a, size, "normal", 1)
    if not (ok and obj and obj.getWidth) then
      ok, obj = pcall(love.graphics.newFont, a, size)
    end
    if not (ok and obj and obj.getWidth) then return nil end
    return obj
  end

  local function fromMod(rel, size)
    local ok, bytes = pcall(mod.read, mod, rel)
    if ok and type(bytes) == "string" and #bytes > 0 then
      local fd = newFileData(bytes, baseName(rel))
      local f = fd and tryFont(fd, size)
      if f then return f end
    end
    if mod.assets and mod.assets.path then
      local ok2, path = pcall(mod.assets.path, mod.assets, rel)
      if ok2 and type(path) == "string" then
        local f = tryFont(path, size)
        if f then return f end
      end
    end
    return nil
  end

  local function engineFile(game)
    local def = game and game.data and game.data.font
    return (def and def.ttf and def.ttf.file) or nil
  end

  local fontCache = {}
  -- fonts(game, style) -> { title, body, small, bold }.  Cached per style once
  -- a game table is available (only the boot knows where the engine TTF is).
  function Style.fonts(game, style)
    local key = style or "modern"
    local hit = fontCache[key]
    if hit then return hit end
    local current
    local okF, cur = pcall(love.graphics.getFont)
    if okF then current = cur end
    local built
    if key == "native" then
      local path = engineFile(game)
      local body = tryFont(path, 12) or (path and tryFont(path, 12)) or current
      built = { title = tryFont(path, 13) or body, body = body,
        small = tryFont(path, 10) or body, bold = body }
    else
      local body = fromMod(FONT_REGULAR, 16) or tryFont(engineFile(game), 16) or current
      local small = fromMod(FONT_REGULAR, 11) or body
      local bold = fromMod(FONT_BOLD, 16) or body
      local title = fromMod(FONT_BOLD, 20) or bold
      built = { title = title, body = body, small = small, bold = bold }
    end
    if game then fontCache[key] = built end
    return built
  end

  -- ------------------------------------------------------------------ drawing
  local function rect(mode, x, y, w, h, r)
    w = (w or 0) < 0 and 0 or (w or 0)
    h = (h or 0) < 0 and 0 or (h or 0)
    if r and r > 0 then
      local ok = pcall(love.graphics.rectangle, mode, x, y, w, h, r, r)
      if ok then return end
    end
    love.graphics.rectangle(mode, x, y, w, h)
  end
  Style.rect = rect

  function Style.set(c, a)
    if not c then love.graphics.setColor(1, 1, 1, 1) return end
    love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
  end

  function Style.w(str, font)
    if not font then return 0 end
    local ok, w = pcall(font.getWidth, font, scrub(str))
    return ok and w or 0
  end

  function Style.text(str, x, y, font, align, color)
    str = scrub(tostring(str))
    if color then Style.set(color) end
    if font then love.graphics.setFont(font) end
    local w = font and Style.w(str, font) or 0
    local dx = x
    if align == "right" then dx = x - w
    elseif align == "center" then dx = x - w * 0.5 end
    love.graphics.print(str, math.floor(dx + 0.5), math.floor(y + 0.5))
    return w
  end

  function Style.fit(str, font, maxPx)
    if str == nil then return str end
    str = scrub(tostring(str))
    if not font or maxPx <= 0 then return str end
    local ok, w = pcall(font.getWidth, font, str)
    if not ok or w <= maxPx then return str end
    local lo, hi = 0, #str
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      local ok2, w2 = pcall(font.getWidth, font, str:sub(1, mid))
      if ok2 and w2 <= maxPx - 8 then lo = mid else hi = mid - 1 end
    end
    return lo > 0 and (str:sub(1, lo) .. "..") or str:sub(1, 1)
  end

  function Style.panel(x, y, w, h, opts)
    opts = opts or {}
    local r = opts.radius or 5
    if opts.shadow and opts.shadow > 0 then
      Style.set(C.shadow)
      rect("fill", x + opts.shadow, y + opts.shadow, w, h, r)
    end
    Style.set(opts.color or C.panel)
    rect("fill", x, y, w, h, r)
    Style.set(opts.border or C.border)
    rect("line", x + 0.5, y + 0.5, w - 1, h - 1, math.max(0, r - 1))
    if opts.highlight ~= false then
      Style.set(C.shine)
      rect("fill", x + 4, y + 1, math.max(0, w - 8), 1, 0)
    end
  end

  -- the classic Game Boy box: black border, white fill
  function Style.nativePanel(x, y, w, h)
    Style.set(C.white)
    rect("fill", x, y, w, h, 0)
    Style.set(C.black)
    rect("line", x + 0.5, y + 0.5, w - 1, h - 1, 0)
    rect("line", x + 1.5, y + 1.5, w - 3, h - 3, 0)
  end

  function Style.bar(x, y, w, h, frac, color, opts)
    opts = opts or {}
    frac = frac or 0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local r = opts.radius or 0
    Style.set(opts.bg or C.panelDeep)
    rect("fill", x, y, w, h, r)
    if frac > 0 then
      Style.set(color or C.good)
      rect("fill", x, y, math.max(1, w * frac), h, r)
    end
    if opts.border then
      Style.set(opts.border)
      rect("line", x + 0.5, y + 0.5, w - 1, h - 1, r)
    end
  end

  function Style.chevrons(x, y, size, color, pulse)
    local s = size or 8
    local off = pulse and pulse * 1.4 or 0
    Style.set(color or C.accent)
    local function tri(ox)
      love.graphics.polygon("fill", ox, y, ox + s * 0.6, y + s * 0.5, ox, y + s)
    end
    tri(x)
    tri(x + s * 0.62 + off)
  end

  return Style
end
