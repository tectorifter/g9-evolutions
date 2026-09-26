-- g9-evolutions -- the single authority over Pokemon evolution, for BOTH
-- generations (Red/Blue/Yellow AND Gold/Silver/Crystal), driven entirely by
-- national_dex's own evolution data.
--
-- Why this mod exists at all
-- --------------------------
-- national_dex registers a species for every Pokemon in the modern dex, but it
-- ships every one of them with an EMPTY evolutions table -- its own docs are
-- explicit that a registered species record keeps `evolutions = {}` and that a
-- consumer must fill the rows in.  Without a consumer, a species the dex adds
-- cannot evolve at all, and the earlier generation's own rows are whatever the
-- ROM extractor happened to write.  This mod is that consumer: it reads every
-- evolution national_dex describes (evolutionsOf / listEvolutions), converts
-- each one into the running generation's own evolutions[] row shape, and
-- patches the result onto the species -- so it is the one place evolution is
-- decided, and the rows an earlier registration (g9-battle-engine's, the
-- extractor's) left on a species are replaced by this mod's own.
--
-- The verb is `:patch`, never `:register` -- `register` is the OVERRIDE verb,
-- which on a record registry replaces the value outright and REFUSES an id that
-- already exists.  Every write this mod makes goes through national_dex's own
-- patch() door when the dex exposes one, so the dex's ledger and the engine's
-- registry move together; only a dex too old to have patch() falls back to the
-- registry directly.  See the "national_dex's patch door" block below.
--
-- The conversion policy lives in data/row_builder.lua, the method
-- implementations in evolutions/*.lua, and the items in items/*.lua; this file
-- is the wiring.  Every method the data carries is operated: level, use-item,
-- trade (with a single-player level alternative), friendship, stat comparison,
-- known-move, held-item (a real held item on Gold, a use-on-the-mon tool on
-- Gen 1), the Gimmighoul-coin evolution, and the regional-form evolutions that
-- this mod rewrites around three new region items (PRIMALAMBER /
-- SOVEREIGNCROWN / SOLSTICENECTAR).  Conditions this engine has no seam for
-- (spin, shed, use-move N times, recoil/damage totals, three hits, three
-- defeats, ...) are RECODED as a plain level-40 evolution rather than left to
-- strand a species -- reachable-and-easier beats unreachable.
-- =============================================================================
return function(mod)
  -- ------------------------------------------------------------------ helpers
  -- mod.log passes its message through string.format, so a literal % has to be
  -- doubled.  Callers that pass ARGS to the logger must not go through esc()
  -- (their %d / %s are intentional); esc() is for a message that IS the format.
  local function esc(s) return (tostring(s):gsub("%%", "%%%%")) end
  local function warn(msg) mod.log:warn(esc(msg)) end
  local function info(msg) mod.log:info(esc(msg)) end

  -- One broken sibling must not take the whole mod down (the loader rolls back
  -- every registration an entry chunk made if the chunk errors).  Every load
  -- goes through here and a failure is a logged, skipped piece.
  local function attempt(label, fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
      warn("g9-evolutions: " .. label .. " failed: " .. tostring(a))
      return false
    end
    return true, a, b, c
  end

  -- Sibling files are compiled from the mod's own byte source (mod:read), the
  -- documented mechanism.  Call sites pass LITERAL paths so the studio's
  -- dependency scan can see the whole file set from the entry chunk alone.
  local function loadSibling(file)
    local body = mod:read(file)
    if not body then
      warn("g9-evolutions: missing sibling file " .. file)
      return nil
    end
    local compile = loadstring or load
    local chunk, err = compile(body, "@" .. file)
    if not chunk then
      warn("g9-evolutions: " .. file .. " failed to compile: " .. tostring(err))
      return nil
    end
    local ok, value = pcall(chunk)
    if not ok then
      warn("g9-evolutions: " .. file .. " failed to run: " .. tostring(value))
      return nil
    end
    return value
  end

  -- ------------------------------------------------------------------ options
  -- The manifest points at options.lua, and this defines the rows from that
  -- very file, so the two copies cannot drift (the manager renders the file
  -- while the mod is disabled; this gives mod.options:get its defaults).
  local schema = loadSibling("options.lua")
  if type(schema) == "table" then
    attempt("options define", function() mod.options:define(schema) end)
  else
    warn("g9-evolutions: options.lua did not return a schema table")
  end

  local function opt(key) return mod.options:get(key) end
  local function on(key)
    local v = opt(key)
    return not (v == "false" or v == false)
  end
  -- A choice row stores the string the manager wrote (see options.lua), and
  -- GIMMIGHOUL DROP's own values carry their display "%" -- so read the leading
  -- number out of whatever arrives rather than insisting on a bare numeral.
  -- Every numeric option goes through here: `"20%"`, `"20"` and a bare 20 from
  -- an older save all mean twenty.
  local function numberOpt(key, fallback)
    local v = opt(key)
    local n = tonumber(v)
    if n then return n end
    if type(v) == "string" then
      n = tonumber(v:match("^%s*(%-?%d+%.?%d*)"))
      if n then return n end
    end
    return fallback
  end

  if not on("evolutions") then
    info("g9-evolutions: EVOLUTIONS is OFF -- every species keeps whatever "
      .. "evolution table its record already carries")
    return
  end

  -- ----------------------------------------------------------------- data
  local ItemIds = loadSibling("data/item_ids.lua")
  local HeldItem = loadSibling("data/held_item.lua")
  local Source = loadSibling("data/evolution_source.lua")
  local RowBuilder = loadSibling("data/row_builder.lua")
  local MoveEvo = loadSibling("data/move_evo.lua")
  -- The special rules the generic builder cannot express: day/night stones,
  -- the Rockruff line on Gen 1, and the Gimmighoul charge vocabulary.  Loaded
  -- BEFORE the build so its helpers ride on the build/needs contexts.
  local Alt = loadSibling("data/alt_evolutions.lua")
  if not (ItemIds and HeldItem and Source and RowBuilder) then
    warn("g9-evolutions: a core data module failed to load -- aborting")
    return
  end
  if type(Alt) ~= "table" then
    warn("g9-evolutions: data/alt_evolutions.lua did not load -- day/night "
      .. "stones, the Gen 1 Rockruff line and the Gimmighoul charge are off")
  end
  -- The species blacklist the wonder trade filters by, and (when g9-battle-
  -- sample is not installed) the list the OPTIONS-menu BLACKLIST window edits.
  -- See data/blacklist.lua for the one-array-of-ids convention that lets the
  -- sample's list, this module and g9-gui's skin share one store.
  local Blacklist = loadSibling("data/blacklist.lua")
  if type(Blacklist) ~= "table" then
    warn("g9-evolutions: data/blacklist.lua did not load -- the wonder trade "
      .. "will not filter delisted species and no BLACKLIST button is offered")
  end

  -- ------------------------------------------------------------ generation
  local gen = 1
  do
    local ok, value = pcall(function()
      local GameVersion = require("src.core.GameVersion")
      return GameVersion.generation(GameVersion.get())
    end)
    if ok and value then gen = value end
  end

  -- ------------------------------------------------------- national_dex
  -- national_dex is the SOURCE of the evolution data, but it is an OPTIONAL
  -- dependency: with it absent (or too old to carry the evolutionsOf API) only
  -- the data-modelled REBUILD below is skipped.  Every other wing -- the TRADE
  -- screen (a real trade evolution and the wonder trade), the inspectors, the
  -- G-FACTOR item and the whose-PC rows -- still installs and works, because
  -- none of them reads the dex: the wonder trade's pool is the running
  -- registry (game.data.pokemon) and the trade round trip uses the engine's
  -- own evolution machinery.  Nothing here may `return` early.
  local dex = mod.find and mod.find("national_dex") or nil
  local exports = type(dex) == "table" and dex.exports or nil
  local dexAvailable = Source.available(exports)
  if not dexAvailable then
    warn("g9-evolutions: national_dex is missing or too old (needs its "
      .. "evolutionsOf API, apiVersion >= 3) -- the evolution rebuild is off; "
      .. "trade, inspectors and the PC rows still install")
  end

  -- ------------------------------------------------------------- item ids
  -- One resolver, so the row builder and the item registrar can never disagree
  -- about what an item is called.  A stone a cart already owns keeps that
  -- cart's real id; everything else keeps national_dex's separator-free id.
  local function itemIdFor(slug)
    return ItemIds.engineId(slug, gen)
  end

  -- A display name from national_dex's own catalogue when it has one (added at
  -- apiVersion 5), else a title-cased slug.  Never fabricates a description;
  -- this is only the bag line.
  local function itemNameFor(slug)
    local catalogue = ItemIds.catalogueId(slug)
    if type(exports.itemById) == "function" then
      local ok, record = pcall(exports.itemById, catalogue)
      if ok and type(record) == "table" and type(record.name) == "string"
          and record.name ~= "" then
        return record.name
      end
    end
    return ItemIds.displayName(slug)
  end

  local function registered(speciesId)
    return mod.content.pokemon:get(speciesId) ~= nil
  end

  -- ------------------------------------------------- national_dex's patch door
  -- national_dex OWNS the species records, and its public patch() is the door a
  -- peer is meant to change them through: it keeps the change in the dex's own
  -- ledger and forwards the keys the ENGINE owns -- `evolutions` among them --
  -- to the registry underneath, so one call is both the dex's answer and the
  -- engine's.
  --
  -- Everything this mod writes -- a species' evolution rows, an evolution
  -- method -- goes through it when the dex exposes it, and straight to the
  -- registry only as the fallback for a dex too old to have patch().
  --
  -- BOTH paths are `:patch`, never `:register`.  `register` is the OVERRIDE
  -- verb: on a record registry it replaces the value outright AND refuses an id
  -- that already exists, so a re-load, a peer mod that already registered the
  -- id, or a second unit naming the same one turns into a refused/duplicated
  -- registration -- the mod's own unit failing, and any row left pointing at an
  -- id that never landed.  `patch` layers this mod's answer on top of whatever
  -- is already there and is idempotent: it can add or refine, never delete, and
  -- it cannot collide.
  local dexPatch = type(exports) == "table" and type(exports.patch) == "function"
    and exports.patch or nil

  local function patchMethod(id, record)
    if dexPatch then
      if dexPatch("evolutionMethod", id, record) then return true end
    end
    return attempt("method " .. tostring(id), function()
      mod.content.evolution_methods:patch(id, record)
    end)
  end

  local function patchSpecies(species, rows)
    if dexPatch then
      if dexPatch("species", species, { evolutions = rows }) then return true end
    end
    return attempt("patch " .. tostring(species), function()
      mod.content.pokemon:patch(species, { evolutions = rows })
    end)
  end

  -- ------------------------------------------------------------- specs -> rows
  -- NO MOVE EVO: when on, every known-move ("hint") evolution becomes a plain
  -- level-up at the level the mon learns the move plus one.  One resolver,
  -- built from the dex, answers the level for both the needs pass (which move
  -- methods to register) and the row builder (which rows to emit), so the two
  -- can never disagree.  See data/move_evo.lua for what "learns the move"
  -- means and the line-shape fallback when the move is not in the learnset.
  local noMoveEvo = on("no_move_evo")
  local moveEvoLevel = nil
  if dexAvailable and noMoveEvo and type(MoveEvo) == "table"
      and type(MoveEvo.resolver) == "function" then
    local ok, resolver = pcall(MoveEvo.resolver, exports)
    if ok and type(resolver) == "function" then moveEvoLevel = resolver end
  end

  local specs = {}
  if dexAvailable then
    specs = Source.specs(exports, Source.ids(exports))
    -- The synthetic targets the data does not hang on the species a player can
    -- actually own (Lycanroc-Dusk's Dusk Stone route on Gen 1).  Added before
    -- the needs pass so their items/methods are registered too.
    if type(Alt) == "table" and type(Alt.extraSpecs) == "function" then
      local extra = Alt.extraSpecs(gen, registered)
      for _, spec in ipairs(extra or {}) do specs[#specs + 1] = spec end
    end
  end
  local need = RowBuilder.collectNeeds(specs, {
    gen = gen,
    alt = Alt,
    noMoveEvo = noMoveEvo,
    moveEvoLevel = moveEvoLevel,
  })

  local buildCtx = {
    gen = gen,
    regionLevel = numberOpt("region_level", 36),
    tradeLevel = numberOpt("trade_level", 40),
    exoticLevel = numberOpt("exotic_level", 40),
    heldLevel = numberOpt("held_level", 40),
    noMoveEvo = noMoveEvo,
    moveEvoLevel = moveEvoLevel,
    alt = Alt,
    itemId = itemIdFor,
    registered = registered,
  }

  -- Rows grouped by the species that evolves.  A regional row is emitted
  -- BEFORE every other row of the same species, because the engine's walk
  -- returns the FIRST matching row: that is what makes a held region item the
  -- tie-break between "Samurott" and "Samurott-Hisui".
  local bySpecies, regionCount, skippedTargets, moveEvoCount = {}, 0, 0, 0
  for _, spec in ipairs(specs) do
    local built = RowBuilder.build(spec, buildCtx)
    if built then
      local rows = bySpecies[spec.from]
      if not rows then rows = {}; bySpecies[spec.from] = rows end
      for _, row in ipairs(built) do
        rows[#rows + 1] = row
        if row.method:sub(1, 10) == "G9_REGION_" then regionCount = regionCount + 1 end
      end
      -- a known-move evolution the option turned into a plain level-up
      if type(spec.method) == "table"
          and type(spec.method.knownMove) == "string"
          and built[1] and built[1].method == "G9_LEVEL" then
        moveEvoCount = moveEvoCount + 1
      end
    else
      skippedTargets = skippedTargets + 1
    end
  end

  local function isRegion(row) return row.method:sub(1, 10) == "G9_REGION_" end
  for _, rows in pairs(bySpecies) do
    table.sort(rows, function(a, b)
      local ar, br = isRegion(a), isRegion(b)
      if ar ~= br then return ar end
      return false
    end)
  end

  -- ------------------------------------------------------------------ context
  local ctx = {
    gen = gen,
    held = HeldItem,
    itemIds = ItemIds,
    regionItems = HeldItem.REGION_ITEMS,
    itemId = itemIdFor,
    itemName = itemNameFor,
    registered = registered,
    regionLevel = buildCtx.regionLevel,
    tradeLevel = buildCtx.tradeLevel,
    exoticLevel = buildCtx.exoticLevel,
    heldLevel = buildCtx.heldLevel,
    coinSlug = RowBuilder.GIMMIGHOUL_COIN,
    coinCost = numberOpt("gimmighoul_cost", 20),
    alt = Alt,
    noMoveEvo = noMoveEvo,
    source = Source,
    patchMethod = patchMethod,
    log = mod.log,
  }

  -- -------------------------------------------------------------- operators
  -- Each unit patches exactly the method ids it owns, through ctx.patchMethod
  -- (national_dex's door first, the registry underneath as the fallback).
  -- item_use.lua and trade.lua also reuse the engine's own ITEM/TRADE ids for
  -- the rows the engine's own machinery has to see; the rest are this mod's.
  local EVOLUTION_UNITS = {
    "evolutions/level.lua",
    "evolutions/item_use.lua",
    "evolutions/trade.lua",
    "evolutions/happiness.lua",
    "evolutions/happiness_stone.lua",
    "evolutions/stat.lua",
    "evolutions/held_item_level.lua",
    "evolutions/move.lua",
    "evolutions/region.lua",
    "evolutions/item_level.lua",
  }
  -- The method units exist to serve the rebuilt rows, so with no dex (and thus
  -- no rows) there is nothing for them to operate and they are skipped whole.
  local methodsRegistered = 0
  if dexAvailable then
    for _, path in ipairs(EVOLUTION_UNITS) do
      local unit = loadSibling(path)
      if type(unit) == "table" and type(unit.install) == "function" then
        local ok = attempt(path, unit.install, mod, ctx, need)
        if ok then methodsRegistered = methodsRegistered + 1 end
      else
        warn("g9-evolutions: " .. path .. " did not return an installer")
      end
    end
  end

  -- ------------------------------------------------------------------ items
  -- The region items and the evolution items exist to satisfy the rebuilt rows,
  -- so both installers are part of the rebuild wing (and skip with it).
  local itemsRegistered = 0
  if dexAvailable then
    local regional = loadSibling("items/regional_items.lua")
    if type(regional) == "table" and type(regional.install) == "function" then
      attempt("items/regional_items.lua", regional.install, mod, ctx)
      itemsRegistered = itemsRegistered + 1
    end
    local evolutionItems = loadSibling("items/evolution_items.lua")
    if type(evolutionItems) == "table"
        and type(evolutionItems.install) == "function" then
      attempt("items/evolution_items.lua", evolutionItems.install, mod, ctx, need)
      itemsRegistered = itemsRegistered + 1
    end
  end

  -- ------------------------------------- Gigantamax Factor (+ the PC row)
  -- The use-on-a-mon item that grants the Gigantamax Factor.  It reads the one
  -- vocabulary in data/gigantamax_factor.lua (id, name, candy, rate, wording),
  -- loaded here and handed to the item registrar -- and, further down, to the
  -- whose-PC row that mints it from ten Dynamax Candies.  The item and the row
  -- fail independently: a missing lib costs the item, a broken item registrar
  -- costs only the item, and a missing widget facade (mod.ui) costs only the
  -- row.
  local GFactor = loadSibling("data/gigantamax_factor.lua")
  if type(GFactor) ~= "table" then
    warn("g9-evolutions: data/gigantamax_factor.lua did not load -- G-FACTOR "
      .. "and its PC row are off")
  else
    local gfactorItem = loadSibling("items/gigantamax_factor.lua")
    if type(gfactorItem) == "table"
        and type(gfactorItem.install) == "function" then
      attempt("items/gigantamax_factor.lua", gfactorItem.install, mod, ctx,
        GFactor)
      itemsRegistered = itemsRegistered + 1
    else
      warn("g9-evolutions: items/gigantamax_factor.lua did not return an "
        .. "installer")
    end
  end

  -- ---------------------------------------------------------- shared style
  -- ui/style.lua is the suite's own drawing vocabulary -- the dark panels, the
  -- Saira face, the accent bars -- and the trade screen, the trade animation
  -- and the inspectors all draw with it.  Built ONCE here and shared, so a bad
  -- build costs every modern surface at once instead of being retried three
  -- different ways.
  --
  -- The modern-content LOCALIZER rides along: when g9-gui (with a translation
  -- mod active) is installed, ui/style.lua translates every string it draws
  -- through g9-gui's published `translation.line`, so the trade screen, its
  -- animation and the inspectors read the same language as the rest of the
  -- suite.  Resolved LAZILY -- g9-gui may finish initialising after this mod,
  -- and a MODERN UI: OFF boot never has it -- and never cached when absent.
  local translateLayer
  local function g9Localize(text)
    if type(text) ~= "string" or text == "" then return text end
    if translateLayer == nil then
      local ok, gui = pcall(mod.find, mod, "g9-gui")
      local t = ok and gui and gui.exports and gui.exports.translation
      if type(t) == "table" and type(t.line) == "function" then
        translateLayer = t
      end
    end
    if not translateLayer then return text end
    local ok, v = pcall(translateLayer.line, text)
    if ok and type(v) == "string" and v ~= "" then return v end
    return text
  end

  local StyleCache
  local function styleModule()
    if StyleCache ~= nil then return StyleCache or nil end
    local Style = loadSibling("ui/style.lua")
    if type(Style) == "function" then
      local okS, built = pcall(Style, mod)
      Style = okS and built or nil
    end
    if type(Style) == "table" and type(Style.setLocalizer) == "function" then
      pcall(Style.setLocalizer, g9Localize)
    end
    StyleCache = (type(Style) == "table") and Style or false
    return StyleCache or nil
  end

  -- ------------------------------------------------------------------ trade
  -- The TRADE screen lives on the whose-PC menu (the row ui/pc_rows.lua splices
  -- in), and its two options are the two trade flows.  Everything the screen
  -- needs is loaded here and handed over as ONE context, so ui/trade.lua owns
  -- the page and nothing else:
  --   * ui/mon_art.lua       the sprite reader -- g9-battle-sprites first, the
  --                          engine's own art as the floor (never blank)
  --   * ui/trade_anim.lua    the MODERN / NATIVE cinematic
  --   * trades/wonder.lua    the one-way wonder trade, with the pity clock
  --   * trades/evo.lua       the out-and-back trade that fires a REAL trade
  --                          evolution (the engine evolves what the local game
  --                          receives -- see trades/evo.lua's own note)
  --   * data/pity.lua        the rarity brackets + the IV factor
  --   * data/wonder_pool.lua the registry-wide pool and the alternate-form rule
  --   * data/form_items.lua  the Mega Stone / Z-Crystal tables
  --   * data/legendary.lua   the 5-star roster the pool reads
  local TradeMod, openTrade
  if on("trade") then
    local Pity = loadSibling("data/pity.lua")
    local Legendary = loadSibling("data/legendary.lua")
    local FormItems = loadSibling("data/form_items.lua")
    local WonderPool = loadSibling("data/wonder_pool.lua")
    local MonArt = loadSibling("ui/mon_art.lua")
    local TradeAnimFactory = loadSibling("ui/trade_anim.lua")
    local TradeFactory = loadSibling("ui/trade.lua")
    local Wonder = loadSibling("trades/wonder.lua")
    local Evo = loadSibling("trades/evo.lua")
    local Style = styleModule()
    local missing = {}
    local function need(label, value, kind)
      if type(value) ~= kind then missing[#missing + 1] = label end
    end
    need("data/pity.lua", Pity, "table")
    need("data/legendary.lua", Legendary, "table")
    need("data/form_items.lua", FormItems, "table")
    need("data/wonder_pool.lua", WonderPool, "table")
    need("ui/mon_art.lua", MonArt, "table")
    need("trades/wonder.lua", Wonder, "table")
    need("trades/evo.lua", Evo, "table")
    if type(Style) ~= "table" then missing[#missing + 1] = "ui/style.lua" end
    if type(TradeAnimFactory) ~= "function" then
      missing[#missing + 1] = "ui/trade_anim.lua"
    end
    if type(TradeFactory) ~= "function" then
      missing[#missing + 1] = "ui/trade.lua"
    end
    if #missing > 0 then
      warn("g9-evolutions: TRADE is on but these did not load -- the screen "
        .. "is off: " .. table.concat(missing, ", "))
    else
      local tradeCtx = {
        gen = gen,
        opt = opt,
        Style = Style,
        monArt = MonArt,
        wonder = Wonder,
        evo = Evo,
        pity = Pity,
        legendary = Legendary,
        formItems = FormItems,
        wonderPool = WonderPool,
        blacklist = Blacklist,
        exports = exports,
        -- A wonder-traded Gigantamax form is delivered as its base species
        -- with its Factor switched on (data/wonder_pool.lua's rule).  The
        -- write goes through data/gigantamax_factor.lua, whose isEligible
        -- gate asks the engine's own roster first, so a G-max form of a
        -- species the engine will not let Gigantamax (Eternatus) is handed
        -- over as its plain base form and the roll records no Factor.
        setGmaxFactor = function(mon, species)
          if type(GFactor) ~= "table" then return false end
          if type(GFactor.isEligible) == "function"
              and not GFactor.isEligible(mod, species) then
            return false
          end
          if type(GFactor.setFactor) ~= "function" then return false end
          return GFactor.setFactor(mod, mon) == true
        end,
      }
      local anim = TradeAnimFactory(mod, tradeCtx)
      tradeCtx.tradeAnim = anim
      local screen = TradeFactory(mod, tradeCtx)
      if attempt("ui/trade_anim.lua", anim.install)
          and attempt("ui/trade.lua", screen.install) then
        TradeMod = screen
        openTrade = function(game) return screen.open(game) end
      end
    end
  else
    info("g9-evolutions: TRADE is OFF -- the whose-PC menu gains no TRADE row "
      .. "and the trade screen is not installed")
  end

  -- -------------------------------------------------------------- BLACKLIST
  -- The wonder trade honours the suite's BLACKLIST, and when g9-battle-sample
  -- is not the one showing the button this mod offers the same OPTIONS row and
  -- the same (native / g9-gui-skinnable) window -- see ui/blacklist.lua.  The
  -- row is registered here but only ADDS itself at menu-build time, where it
  -- can see whether the sample loaded: a sample that loads after this mod still
  -- wins its registration, and this mod merely reads that list for its filter.
  if on("trade") and type(Blacklist) == "table" then
    local factory = loadSibling("ui/blacklist.lua")
    if type(factory) == "function" then
      local okB, BlacklistUI = attempt("ui/blacklist.lua", factory, mod, {
        gen = gen, opt = opt, blacklist = Blacklist,
      })
      if okB and type(BlacklistUI) == "table"
          and type(BlacklistUI.install) == "function" then
        attempt("blacklist install", BlacklistUI.install)
      end
    else
      warn("g9-evolutions: ui/blacklist.lua did not load -- the wonder trade "
        .. "still honours an existing blacklist, but no BLACKLIST button is "
        .. "offered when g9-battle-sample is absent")
    end
  end

  -- ------------------------------------------------------------ whose-PC rows
  -- MAX-FACTOR and TRADE both live on the "Access whose PC?" screen now (see
  -- ui/pc_rows.lua): Gen 1's openPC list, or Gold's CenterPcMenu, spliced in
  -- just above the exit row.  One install serves both, and either option can
  -- be off while the other stays on.
  if on("max_pc") or on("trade") then
    local PcRows = loadSibling("ui/pc_rows.lua")
    if type(PcRows) == "table" and type(PcRows.install) == "function" then
      attempt("ui/pc_rows.lua", PcRows.install, mod, ctx, {
        GF = GFactor,
        maxFactor = on("max_pc"),
        trade = on("trade"),
        openTrade = openTrade,
      })
    else
      warn("g9-evolutions: ui/pc_rows.lua did not return an installer")
    end
  else
    info("g9-evolutions: MAX PC and TRADE are both OFF -- the whose-PC menu is "
      .. "left exactly as the engine drew it")
  end

  -- ------------------------------------------- Gimmighoul charge bookkeeping
  -- The coin's re-entrancy guard (data/alt_evolutions.lua) is set on the mon
  -- the moment its threshold use hands the evolution to the engine.  Clearing
  -- it when the evolved record lands keeps the mark from ever outliving the
  -- use that set it.
  if type(Alt) == "table" and type(Alt.clearEvolving) == "function" then
    mod.events:on("pokemon.evolved", function(ev)
      local mon = type(ev) == "table" and ev.mon or nil
      if type(mon) == "table" then Alt.clearEvolving(mon) end
    end)
  end

  -- ------------------------------------------------------- patch the species
  local patched, unknown, totalRows = 0, 0, 0
  for species, rows in pairs(bySpecies) do
    if registered(species) then
      local ok = patchSpecies(species, rows)
      if ok then
        patched = patched + 1
        totalRows = totalRows + #rows
      end
    else
      unknown = unknown + 1
    end
  end

  -- --------------------------------------------- Gen 1 friendship tracker
  -- Red/Blue/Yellow has no friendship value anywhere, so the friendship rows
  -- this mod builds would never fire there.  When GEN 1 FRIENDSHIP is on, an
  -- invisible value is kept in `mon.g9Happiness` -- a fresh mon starts at 70
  -- and earns as it levels (+10) and wins (+2) -- and the happiness checks read
  -- it (see evolutions/happiness.lua).  A mon that already carries a real
  -- `happiness` (Gold's shape, or a save another mod blessed) is left alone on
  -- both generations, so this can never disagree with a real value.
  if gen == 1 and on("gen1_friendship") then
    mod.events:on("pokemon.level_up", function(ev)
      local mon = type(ev) == "table" and ev.mon or nil
      if type(mon) ~= "table" or tonumber(mon.happiness) ~= nil then return end
      local current = tonumber(mon.g9Happiness) or 70
      mon.g9Happiness = math.min(255, current + 10)
    end)

    -- Three emitters raise battle.ended and a native fight raises it twice, so
    -- the underlying battle is what gets deduped (the same guard g9-battle-
    -- sample uses): the UI payload's `battle` is the screen, whose own
    -- `.battle` is the model.
    local lastBattle = nil
    mod.events:on("battle.ended", function(ev)
      if type(ev) ~= "table" or ev.result ~= "win" then return end
      local battle = ev.battle
      if type(battle) == "table" and type(battle.battle) == "table" then
        battle = battle.battle
      end
      if battle == lastBattle then return end
      lastBattle = battle
      local ok, Game = pcall(require, "src.core.Game")
      local save = ok and type(Game) == "table" and Game.save or nil
      for _, mon in ipairs((save and save.party) or {}) do
        if type(mon) == "table" and tonumber(mon.happiness) == nil then
          local current = tonumber(mon.g9Happiness) or 70
          mon.g9Happiness = math.min(255, current + 2)
        end
      end
    end)
  end

  -- ------------------------------------------- Gimmighoul Coin drops
  -- Gholdengo needs Gimmighoul Coins (the coin's own use effect consumes
  -- GIMMIGHOUL COST of them), and the coins drop from a defeated/caught wild
  -- Gimmighoul.  The species is captured at battle.started because battle.ended
  -- carries no species and the enemy may already be torn down by then; the
  -- battle.ended payload is deduped the same way the friendship tracker dedupes
  -- it (a native fight raises it twice, and the UI payload's `battle` may be
  -- the screen rather than the model).
  local coinId = itemIdFor(RowBuilder.GIMMIGHOUL_COIN)
  local dropPercent = numberOpt("gimmighoul_drop", 0)
  -- The coin is registered by the rebuild wing, and a wild Gimmighoul is a
  -- national_dex species, so both the item and the drop belong to the rebuild.
  if dexAvailable and coinId and dropPercent > 0 then
    local wildSpecies = setmetatable({}, { __mode = "k" })
    mod.events:on("battle.started", function(ev)
      if type(ev) ~= "table" or ev.kind ~= "wild" then return end
      if type(ev.battle) ~= "table" or type(ev.species) ~= "string" then return end
      -- The payload's `battle` is the model on Gen 1 and the model's screen on
      -- Gen 2 (the screen's own `.battle` is the model), and Gold emits from
      -- BOTH, so record the species under whichever table(s) arrived.
      wildSpecies[ev.battle] = ev.species
      if type(ev.battle.battle) == "table" then
        wildSpecies[ev.battle.battle] = ev.species
      end
    end)

    local lastBattle
    mod.events:on("battle.ended", function(ev)
      if type(ev) ~= "table" then return end
      if ev.result ~= "win" and ev.result ~= "caught" then return end
      local raw = ev.battle
      local model = raw
      if type(raw) == "table" and type(raw.battle) == "table" then
        model = raw.battle
      end
      if type(model) ~= "table" or model == lastBattle then return end
      lastBattle = model
      local species = wildSpecies[model] or wildSpecies[raw]
      if type(species) ~= "string"
          or not species:find("GIMMIGHOUL", 1, true) then return end
      if math.random() * 100 >= dropPercent then return end
      local Game = require("src.core.Game")
      local save = Game and Game.save
      if not (save and save.inventory) then return end
      local ok = pcall(function()
        require("src.inventory.Bag").add(save, coinId, 1, Game.data)
      end)
      if ok then
        info("g9-evolutions: a wild Gimmighoul dropped a Gimmighoul Coin")
      end
    end)
  end

  -- ------------------------------------------------------------- inspectors
  -- The party-menu HAPPINESS / GIMMIGHOUL popups.  They are pure viewers, and
  -- fail independently: a missing style or screen module costs the rows, never
  -- the evolution rebuild above.
  local inspectorInstalled = false
  if on("happiness_inspector") or on("gimmighoul_inspector") then
    local Style = styleModule()
    if type(Style) ~= "table" then
      warn("g9-evolutions: ui/style.lua did not load -- no inspectors")
    else
      local factory = loadSibling("ui/inspector.lua")
      if type(factory) ~= "function" then
        warn("g9-evolutions: ui/inspector.lua did not load -- no inspectors")
      else
        -- The Gen 2 friendship figures the HAPPINESS screen prints.  The ENGINE
        -- owns them: src/core/gen2/Happiness is the module that actually moves
        -- the byte and reads the cart's own data/events/happiness_changes.asm,
        -- so requiring it here means a retuned engine is followed rather than
        -- contradicted.  data/happiness_gains.lua carries the same table (row
        -- for row) as the fallback for an engine too old to have the module,
        -- plus the labels and the tier rule the screen words itself with.
        local gains = loadSibling("data/happiness_gains.lua")
        if type(gains) ~= "table" then
          warn("g9-evolutions: data/happiness_gains.lua did not load -- the "
            .. "happiness screen will list its actions without figures")
        end
        local happiness = nil
        do
          local okH, engine = pcall(require, "src.core.gen2.Happiness")
          if okH and type(engine) == "table"
              and type(engine.delta) == "function" then
            happiness = engine
          end
        end
        local okI, Inspector = attempt("ui/inspector.lua", factory, mod, {
          gen = gen,
          opt = opt,
          alt = Alt,
          Style = Style,
          gains = gains,
          happiness = happiness,
          chargeMax = numberOpt("gimmighoul_cost", 20),
        })
        if okI and type(Inspector) == "table"
            and type(Inspector.install) == "function" then
          local okInst, installed = attempt("inspector install", Inspector.install)
          inspectorInstalled = (okInst and installed) and true or false
        end
      end
    end
  end

  -- ------------------------------------------------------------- exports
  mod.exports.evolutionsVersion = "1.6.0"
  mod.exports.regionItems = HeldItem.REGION_ITEMS
  mod.exports.isRegionItem = HeldItem.isRegionItem
  mod.exports.regionOfItem = HeldItem.regionOfItem
  mod.exports.heldItemOf = function(mon) return HeldItem.of(mon, gen) end

  if dexAvailable then
    info(string.format("g9-evolutions: rebuilt evolution for %d species "
      .. "(%d rows, %d regional, %d known-move converted, %d unmatched targets "
      .. "skipped) across %d method units; %d item unit(s) installed on "
      .. "generation %d",
      patched, totalRows, regionCount, moveEvoCount, skippedTargets,
      methodsRegistered, itemsRegistered, gen))
  else
    info(string.format("g9-evolutions: national_dex absent -- the evolution "
      .. "rebuild is off (0 species); the trade wing, inspectors and PC rows "
      .. "are installed on generation %d", gen))
  end
  if unknown > 0 then
    info(string.format("g9-evolutions: %d species with evolutions were not "
      .. "registered and were skipped", unknown))
  end
  if on("happiness_inspector") or on("gimmighoul_inspector") then
    info(string.format("g9-evolutions: inspectors %s (style %s; happiness %s, "
      .. "gimmighoul %s)",
      inspectorInstalled and "on" or "FAILED",
      tostring(opt("inspector_style") or "MODERN"),
      on("happiness_inspector") and "on" or "off",
      on("gimmighoul_inspector") and "on" or "off"))
  end
  if on("trade") then
    info(string.format("g9-evolutions: TRADE %s (style %s)",
      TradeMod and "on" or "FAILED",
      tostring(opt("trade_style") or "MODERN")))
  end
  if on("trade") and type(Blacklist) == "table" then
    -- Who OWNS the button is decided at menu-build time (the sample may load
    -- after this mod), so the boot line states the rule, not a guess.
    info("g9-evolutions: the wonder trade filters by the shared BLACKLIST; "
      .. "the OPTIONS BLACKLIST row is offered only when g9-battle-sample is "
      .. "absent")
  end
end
