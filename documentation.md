# g9-evolutions — manifest description

This file records the full `description` for the **g9-evolutions** mod
(`manifest.json`). The manifest's own `description` field is capped at
**80 characters** (a studio rule, so the Mod Manager row and the generator
listing stay readable), so the complete text lives here and the manifest
carries only a short summary.

## Current description (full)

The single authority over Pokemon evolution for BOTH generations (Red/Blue/Yellow AND Gold/Silver/Crystal), driven entirely by the national_dex mod's evolution data. It reads every species' evolution record from national_dex (apiVersion >= 3's evolutionsOf/listEvolutions), converts it into that generation's own evolutions[] row shape, and patches the rows onto every registered species -- so a species national_dex adds (which ships an EMPTY evolutions table) can finally evolve, and any earlier evolution registration in g9-battle-engine is superseded. Every evolution method the data carries is operated: plain level-up; use-an-item-on-the-mon (all stones, including the ones this mod registers itself); trade (with the item it demands) PLUS a level-40 alternative that lets a trade evolution fire without a second Game Boy; high friendship (160 or 220, honouring Gold's day/night window); stat comparison (Tyrogue's attack-vs-defence); level-up while knowing a move (Ancient Power, Mimic, Rollout, ...) with the NO MOVE EVO option (on by default) able to replace that requirement with a plain level-up at the level the Pokemon learns the move plus one -- or a line-shape default of 25 (first step of a three-stage line), 30 (a two-stage line) or 35 (the last step of a three-stage line) when the move is not in its level-up learnset; level-up while holding an item (Razor Claw, Razor Fang, Oval Stone); the Kubfu scrolls (Scroll of Darkness -> Urshifu, Scroll of Waters -> Urshifu-Rapid-Strike) as ordinary use-items on both generations; and the regional-form evolutions, which this mod REWRITES around three new key items. Regional item evolutions: PRIMALAMBER (Hisui), SOVEREIGNCROWN (Galar) and SOLSTICENECTAR (Alola) are registered as real items and, on both generations, a mon that HOLDS one of them while it levels to the target's level evolves into that region's variant -- Dewott holding a PRIMALAMBER at level 36 becomes Samurott-Hisui while a Dewott without one becomes plain Samurott, Rufflet/Bergmite/Dartrix/Goomy/Cyndaquil-line/Petilil/Koffing/Pikachu/Cubone/Mime Jr. and every other regional line work the same way, and Goodra-Hisui is deliberately NOT item-gated because it already evolves from Sliggoo-Hisui. On Gen 1, where the engine has no held-item field, a held-item or item-trade evolution becomes a use-on-a-mon tool gated on a level (HELD LEVEL, 40 by default): using the Razor Claw on a Sneasel at level 40 or higher evolves it and consumes the claw, while on a species the item does not evolve it falls back to the old toggle-the-g9HeldItem-mark behaviour so the item still works as a held item; region items stay re-usable marks. Conditions this engine has no seam for (spin, shed, use-move N times, recoil/take-damage totals, three hits, three defeats, the Kubfu towers) are RECODED to a plain level-up at EXOTIC LEVEL (40 by default) instead of being left permanently unreachable. Day and night routes also gain a STONE on both generations, since Red/Blue/Yellow has no clock at all and Gold's window is easy to miss: a day/morning route takes the SUN STONE and a night/dusk route the DUSK STONE, as pure use-items, and a route that also demanded friendship keeps demanding it (Espeon = Sun Stone + friendship, Umbreon = Dusk Stone + friendship), the stone replacing the missing clock rather than the bond; on Gold the real day/night level-up rows are kept and the stone is added alongside, while on Gen 1 the stone replaces the time route. The Rockruff line is rebuilt explicitly on Gen 1 alone: a plain level-up yields Lycanroc-Midnight, the Sun Stone yields Lycanroc-Midday and the Dusk Stone yields Lycanroc-Dusk (the Dusk route is injected as a synthetic target, since the data hangs it on the separate Own Tempo form). The Gimmighoul-coin evolution is its own saved-charge mechanic: a defeated or caught wild Gimmighoul drops a Gimmighoul Coin (20% by default, GIMMIGHOUL DROP), using the coin on a Gimmighoul adds exactly one point to a saved charge on that Pokemon (mon.g9GimmighoulCharge) and spends exactly one coin, and at GIMMIGHOUL COST points (20 by default) the Pokemon becomes Gholdengo. The charge is clamped to the threshold so a corrupted save can never overflow it (which is what would make the loop never terminate), a re-entrancy mark makes a use that is already mid-evolution a no-op instead of a nested second evolution, and the coin is EXCLUSIVE to Gimmighoul -- the species match is a prefix test that deliberately excludes GHOLDENGO, so the coin can never be used on a Gholdengo or any other species. The party menu also gains two read-only inspectors, each with its own on/off option (both on by default): a HAPPINESS screen for the selected Pokemon showing its friendship as a figure and a bar against the 160/220 thresholds the evolution data uses, the friendship-gated evolutions it is working toward and whether each is met, and a short list of how the value rises (level up, battle wins, and on Gold walking, vitamins and grooming); and a COIN CHARGE screen exclusive to Gimmighoul showing its saved charge as a segmented bar and how many coins are still to go. The inspectors are drawn in the g9-gui suite's modern style (dark translucent panels, accent rule, the vendored Saira face) by default, with an INSPECTOR STYLE option to switch them to a native look -- white paper, a black border and the engine's pixel font, drawn as the classic 160x144 Game Boy screen scaled to fill the page -- so they can match the cart; both styles own the same 540x360 page (Gen 1 through :uiSize, Gold through the drawsWidescreen/drawWidescreen contract), so an inspector is never collapsed into a canvas of the wrong shape. They open from the party menu's own action list through the engine's ui.party.submenu hook, so no engine file is replaced. Items are registered through the engine's own content registries with the national_dex item-id vocabulary, and the native stones are remapped to each generation's real native ids (FIRE_STONE on Red, THUNDERSTONE on Gold) instead of registering dead duplicates. Every evolution-method registration and every species evolution patch goes through national_dex's own patch() API when the dex exposes it (falling back to the engine registry's :patch on an older dex), never the registry's override verb, so installing or reloading this mod layers its rows on top of what national_dex and other mods registered instead of replacing records. It also registers the G-FACTOR item -- a use-on-a-mon tool, written through the engine's own patch API like every other item here, that is consumed to grant a Gigantamax-capable species the engine's per-mon gigantamaxFactor and is refused without spending on any species that cannot Gigantamax or on one that already carries the Factor -- and a MAX-FACTOR row on the PC's own "Access whose PC?" screen (both generations -- Gen 1's openPC list through the engine's own ui.pc.items hook, Gold's CenterPcMenu through a buildEntries/choose patch, since that screen raises no hook), spliced in just above the exit row, which asks through the engine's own dialogue box whether to convert 10 Max Candies into 1 MAX-FACTOR and, only on YES and only with ten candies in the bag, spends exactly ten MAX CANDY and adds one MAX-FACTOR. The MAX PC option turns that row and its conversion off entirely (the G-FACTOR item itself is unaffected). Alongside it, the same whose-PC screen gains a TRADE row (the TRADE option) opening a new TRADE page -- title TRADE, description "select the pokemon you wish to trade to evolve it" -- with two options. TRADE EVO performs two trades (the chosen Pokemon out, then the Pokemon just received sent back) so the engine's own trade evolution fires naturally on what the local game receives, exactly as a link cable would; the whole trade is presented in one of two styles chosen by TRADE STYLE: a modernised look matching the modern GUI (the suite's page, identical on both generations, with its own cable cinematic) or the cart's own look (the classic 160x144 Game Boy page scaled to fill the screen, and the cart's own Gen 1 / Gen 2 trade animation); either way the travelling cable icon is the g9-battle-sprites cell, and a wonder trade's received Pokemon stays ??? until the result page names it. WONDER TRADE is a one-way trade for a random Pokemon drawn from the whole registry including alternate forms (a rolled Mega or Totem arrives as its non-alternate species plus the Mega Stone or Z-Crystal that enables it, e.g. Incineroar comes with Incinium Z; a rolled Gigantamax form -- and Eternatus's Eternamax -- arrives as its base species with the Gigantamax Factor already activated, exactly as if a G-FACTOR had been used on it; and a rolled Stellar or Terastal form arrives as its plain base species): species are ranked into five star brackets by base-stat total (1 star up to 200, 2 up to 300, 3 up to 400, 4 up to 600 with no legendaries or mystical, 5 above 600 or any legendary/mystical; a record with no real special split -- a boot with no battle engine -- has its ONE Special counted for BOTH halves, and the read adapts to whatever field the running dex registers, so the pool works with or without national_dex), the bracket is rolled at 20%/30%/44.3%/5.1%/0.6% and an independent IV bonus is rolled at 50%/44.3%/5.1%/0.6% for +1/+2/+3/+4 (the six IVs are then generated inside that rung) -- and the SAME rung also generates the cart's own DV block, because a boot with no battle engine has no IV system at all: Gen 2's DV ladder tops at 90 (its shared Special DV counted twice) and Gen 1's at 80, with the same 50%/44.3%/5.1%/0.6% rungs read as fractions of each generation's own maximum -- and a single pity clock that past pull 55 ramps BOTH rolls at once makes the 70th wonder trade a certain 5-star species with a perfect IV set, and only a 5-star species resets the clock (the IV/DV rung is flavour and never does); a finished wonder trade or trade evolution returns to the TRADE menu with the cursor on the option used rather than to the PC. The wonder trade honours the suite's shared BLACKLIST (one id array on the save's per-mod bucket, the same list g9-battle-sample's randomizer uses and g9-gui's skin draws): a delisted species -- or a delisted base's alternate forms -- is absent from the pool and can never be drawn, the shipped default delists every Mega and Gigantamax form, and when g9-battle-sample is not installed this mod itself offers the same OPTIONS-menu BLACKLIST row and the same (native, or g9-gui-skinned) 320x180 window; when it is installed the sample's row wins and this mod only reads that list.

## Manifest summary (<= 80 chars)

Evolution, inspectors, PC trade (wonder/trade evo) and MAX-FACTOR.

## History

- **1.6.3** declares the mod's own repository in the manifest
  (`"github": "https://github.com/tectorifter/g9-evolutions"`), so the
  gen1recomp launcher can pull updates for an installed copy from its own
  GitHub release. No code change.
- **1.6.2** adds a third-party-IP notice (`THIRD-PARTY-NOTICES.md`): Pokemon and
  related assets belong to Nintendo, Creatures Inc., GAME FREAK inc. and The
  Pokemon Company; this is an unofficial fan mod owning only its own Lua
  (GPL-3.0-or-later); the Saira fonts stay under the SIL OFL 1.1. No code
  change.
- **1.6.1** relicenses the mod under the **GNU GPLv3** (it was MIT): the shipped
  `LICENSE` is now the full GNU General Public License, version 3, copyright
  **tectorifter** (<https://github.com/tectorifter/>). No code change.
- Full text moved here and the manifest `description` shortened to the
  summary above. Doc/description-only change, so no version bump.
- g9-evolutions 0.4.0 -> 0.5.0: the full description gained the day/night
  stones, the Rockruff Gen 1 line, the Gimmighoul saved-charge mechanic with
  its overflow/exclusivity safeguards, and the two party-menu inspectors with
  their style option. (The 80-char manifest summary is unchanged.)
- g9-evolutions 0.5.2 -> 0.6.0: no description change. The happiness screen's
  Gen 2 list gained the FIGURE every action pays, from the cart's own
  three-column happiness table (asked of the engine's src/core/gen2/Happiness
  first, with data/happiness_gains.lua as the fallback for an engine without
  it): the wide page prints all three columns, the native page the mon's own
  tier. (The 80-char manifest summary is unchanged.)
- g9-evolutions 0.5.0 -> 0.5.1 / 0.5.2: no description change. 0.5.1 fixed the
  inspector surface and made HAPPINESS about the selected Pokemon (both styles
  now own the same 540x360 page); 0.5.2 fixed the `INSPECTOR STYLE` and
  `GIMMIGHOUL DROP` choice rows, whose label/value order was swapped, so
  selecting NATIVE stored `"NATIVE"` and drew MODERN and a stepped drop value
  read as `nil`. (The 80-char manifest summary is unchanged.)
- g9-evolutions 0.6.0 -> 0.7.0: the full description gained the G-FACTOR item
  (a consumable use-on-a-mon tool that grants the engine's per-mon Gigantamax
  Factor to a Gigantamax-capable species and is refused, without spending, on
  any other) and the PC's MAX-FACTOR row (the last option before the exit row
  on both generations, converting 10 Max Candies into 1 MAX-FACTOR behind a
  YES/NO prompt). (The 80-char manifest summary is unchanged.)
- g9-evolutions 0.7.0 -> 0.8.0: the full description gained a clause noting the
  new MAX PC option, which turns the PC's MAX-FACTOR row and its conversion off
  entirely (ON by default; the G-FACTOR item is unaffected). (The 80-char
  manifest summary is unchanged.)
- g9-evolutions 0.8.0 -> 0.9.0: the full description gained the TRADE row and
  the new TRADE page (a real trade-evolution round trip, and a wonder trade for
  a random registry Pokemon with alternate forms, the Mega/Totem -> base + item
  rule, the five star brackets, the IV factor and a Genshin-style pity clock
  with a hard-guaranteed perfect 5-star on the 70th pull), and was corrected
  about where the MAX-FACTOR row lives (the "Access whose PC?" screen on both
  generations, not the storage/item PC menus). The 80-char manifest summary
  became "Evolution, inspectors, PC trade (wonder/trade evo) and MAX-FACTOR."
- g9-evolutions 0.9.0 -> 1.0.0: the full description's wonder-trade clause was
  extended with the battle-form rule -- a rolled Gigantamax form (and
  Eternatus's Eternamax) arrives as its base species with the Gigantamax Factor
  already activated, and a rolled Stellar or Terastal form arrives as its plain
  base species. (The 80-char manifest summary is unchanged.)
- g9-evolutions 1.0.0 -> 1.1.0: the full description's wonder-trade clause now
  states the exact rarity rates (bracket 20%/30%/44.3%/5.1%/0.6%, IV bonus
  50%/44.3%/5.1%/0.6%, the six IVs generated inside the rolled rung) and the
  single pity clock that ramps BOTH rolls and guarantees a 5-star + perfect IVs
  on the 70th pull, and notes that a finished trade returns to the TRADE menu
  with the cursor on the option used. (The 80-char manifest summary is
  unchanged.)
- g9-evolutions 1.1.0 -> 1.2.0: the full description's wonder-trade clause now
  states that the wonder trade honours the suite's shared BLACKLIST (one id
  array, the shipped Mega/Gigantamax default, a delisted base hides its forms),
  and that when g9-battle-sample is not installed this mod offers the same
  OPTIONS-menu BLACKLIST row and the same native / g9-gui-skinnable window
  while the sample's own row wins when it is. (The 80-char manifest summary is
  unchanged.) New files `data/blacklist.lua` and `ui/blacklist.lua`.
- g9-evolutions 1.2.0 -> 1.3.0: the full description's trade clause now says
  `TRADE STYLE` governs the whole trade -- the SCREEN as well as the animation
  (NATIVE draws the classic 160x144 Game Boy page scaled to fill the screen and
  plays the cart's own animation) -- that the travelling cable icon is the
  g9-battle-sprites cell in both styles and both generations, and that a wonder
  trade's received Pokemon stays `???` on every animation label until the result
  page names it. (The 80-char manifest summary is unchanged.)
- g9-evolutions 1.3.0 -> 1.3.1: no description change. A layout/appearance fix
  to the trade pages: the rarity stars are now fanned into convex triangles (the
  cart's love.graphics.polygon rendered the concave five-point star as a
  four-pointed sparkle in both styles), the NATIVE result page puts the RARITY
  caption and its stars on separate lines (they overlapped), every NATIVE trade
  page anchors its bottom cluster higher so the button hint and the last row of
  text sit inside the printed 160x144 border, and the NATIVE trade MOVIE's front
  pic is now the g9-battle-sprites front portrait of the respective Pokemon
  rather than the cart's own battle sprite (with the cart's sprite kept as the
  fallback). (The 80-char manifest summary is unchanged.)
- g9-evolutions 1.3.1 -> 1.4.0: no description change. **`national_dex` becomes
  an OPTIONAL dependency** (`dependencies` is now empty; `national_dex`,
  `g9-battle-engine`, `g9-battle-sprites` and `g9-battle-sample` all sit in
  `optional_dependencies`, with a `dependency_sources.national_dex` launcher
  hint). With national_dex absent the evolution rebuild skips, but the whole
  non-dex wing still installs and works: the TRADE screen's two flows (a real
  trade evolution through the engine's own machinery, and the wonder trade,
  whose pool is the running `game.data.pokemon` registry), the inspectors, the
  G-FACTOR item and the whose-PC rows. The mod previously `return`ed early when
  the dex was missing, so nothing at all installed. (The 80-char manifest
  summary is unchanged.)
- g9-evolutions 1.4.0 -> 1.5.0: the full description's wonder-trade clause now
  states the DV ladder (the same rung also generates the cart's own DV block,
  because a boot with no battle engine has no IV system: Gen 2 tops at 90 with
  its shared Special DV counted twice, Gen 1 at 80, the same rungs read as
  fractions of each maximum), and its pool clause notes the doubled Special on
  a record with no real split (so the pool works with or without national_dex).
  (The 80-char manifest summary is unchanged.)
- g9-evolutions 1.5.0 -> 1.5.1: the full description's wonder-trade clause now
  states that ONLY a 5-star species resets the pity clock -- the +1..+4 IV/DV
  rung is flavour the result page prints and never counts, so a 2-star species
  rolled at +3 is "just a 2" and advances the clock. (The 80-char manifest
  summary is unchanged.)
- g9-evolutions 1.5.1 -> 1.5.2: the trade, inspector and trade-animation pages
  mark themselves with the shared `__g9modern` flag, so g9-gui's COLOR
  PROTECTION toggle keeps gen1recomp's native OPTIONS > GRAPHICS > COLORS
  display mode off them too. The flag is a plain field read only by that mod --
  nothing here depends on g9-gui, and a boot without it ignores the flag. (No
  description text changes.)
- g9-evolutions 1.5.2 -> 1.5.3: no description change. The Saira faces this mod
  bakes now carry a FALLBACK for the three glyphs they lack that a translated
  Pokemon name can use -- U+2640 FEMALE SIGN, U+2642 MALE SIGN and U+2605 BLACK
  STAR -- through a new `assets/fonts/g9-symbols.ttf` supplement attached with
  LOVE 11.3's `Font:setFallbacks` (in `ui/style.lua`). That is the same
  supplement g9-gui's translation layer ships; nothing here depends on g9-gui,
  and an engine without `setFallbacks` simply keeps the old behaviour. (No
  description text changes.)
- g9-evolutions 1.5.3 -> 1.5.4: no description change. The `g9-symbols.ttf`
  supplement is rebuilt for the languages g9-gui's translation layer now covers,
  whose names use kana and Hangul that neither Saira nor the old four-glyph file
  carried -- regenerated from Noto Sans JP / Noto Sans KR / Noto Sans Symbols 2
  with the three symbols, the Japanese kana and the Korean Hangul (1086 glyphs,
  ~306 KB), attached with LOVE 11.3's `Font:setFallbacks` in `ui/style.lua`. The
  wiring is unchanged and the fallback only ever ADDS glyphs. (No description
  text changes.)
- g9-evolutions 1.5.4 -> 1.5.5: no description change. The `g9-symbols.ttf`
  supplement is rebuilt once more (1093 glyphs, 316116 B) so its glyph set keeps
  up with the codepoints g9-gui's translation layer and its new message lexicon
  use; it is still attached with LOVE 11.3's `Font:setFallbacks` in
  `ui/style.lua`, the wiring is unchanged, and the fallback only ever ADDS
  glyphs. (No description text changes.)
- g9-evolutions 1.5.5 -> 1.6.0: no description change. The TRADE page and its
  animation now translate through g9-gui's published translation layer
  (`main.lua` resolves `mod.find("g9-gui").exports.translation.line` lazily and
  hands it to `ui/style.lua`'s `Style.setLocalizer`; `Style.text` / `Style.w` /
  `Style.fit` all localize, and the native page's `wrap` translates the whole
  sentence before splitting it), fixing "trade and wonder trade remain
  unaffected by translation"; `g9-gui` joins `optional_dependencies`. A new
  WONDER COST option (choice, default 0; 0/250/500/1000/2000/5000) charges a
  money fee for a wonder trade: with enough money the cost is deducted and the
  trade proceeds, without it nothing is traded and the page shows
  `Not enough ¥, have at least ¥N.` (translated); 0 performs no check, and
  TRADE EVO is never charged.
