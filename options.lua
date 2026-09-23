-- g9-evolutions option schema.
--
-- Declared in manifest.json's "options_schema" field so the Mod Manager can
-- render the rows before the mod's own entry chunk has run, and re-declared
-- by main.lua with this EXACT table at load time (mod.options:define reads it)
-- so the two never drift.
--
-- Visible labels stay short: the Mod Manager truncates long ones.
--
-- CHOICE ORDER IS { label, VALUE } -- the manager DISPLAYS choices[i][1] and
-- STORES choices[i][2] (src/mods/ManagerState.lua: it reads `choice[2] == cur`
-- to find the label, and setOption writes `choices[index][2]`), so the SECOND
-- element is what every `opt(key)` read ever sees and `default` must equal one
-- of them.  Writing a choice the other way round makes the row look like it
-- toggles while the stored value never matches what the code compares against
-- (this very file shipped INSPECTOR STYLE as { "native", "NATIVE" } -- read as
-- label "native", value "NATIVE" -- so stepping to NATIVE stored the string
-- "NATIVE" while the inspector tested `v == "native"` and drew MODERN).
--
-- `INSPECTOR STYLE` and `GIMMIGHOUL DROP` keep the SPELLING earlier 0.5.x
-- versions already stored -- "MODERN" / "NATIVE", and the percents with their
-- "%" -- and their readers tolerate it (`ui/inspector.lua`'s styleName
-- lower-cases; main.lua's numberOpt reads the leading number out of "20%").
-- That matters because the manager falls back to the FIRST choice's label
-- whenever a stored value matches no choice: re-spelling the values would leave
-- an existing save whose row reads "MODERN" while the screen drew native (and
-- one whose drop row read "0%" while the mod used 20).  Every row's choice
-- VALUES equal its `default`, which `tools/verify.lua`'s schema-integrity check
-- asserts (`default == choices[i][2]`).
return {
  {
    key = "evolutions",
    label = "EVOLUTIONS",
    type = "toggle",
    default = true,
    description = "ON (default): g9-evolutions rebuilds every species' evolution table from national_dex's own data and operates all of its methods on both generations -- level, item, trade (with a level-40 alternative), friendship, stat comparison, known-move, held-item, the regional-item evolutions and the Gimmighoul-coin evolution. Conditions this engine cannot express (spin, shed, use-move N times, recoil/take-damage totals, three hits, three defeats, the Kubfu towers) are recoded to a plain level-up at EXOTIC LEVEL. OFF: the mod installs nothing and every species keeps whatever evolutions its record already carries.",
  },
  {
    key = "region_level",
    label = "REGION LEVEL",
    type = "choice",
    default = "36",
    choices = { { "28", "28" }, { "32", "32" }, { "36", "36" },
                { "40", "40" }, { "45", "45" } },
    description = "The level a REGIONAL evolution needs when the data only names a stone for it (e.g. Pikachu into Alolan Raichu, Petilil into Hisuian Lilligant): hold the region item and level up to this level. Region evolutions that already carry their own level in the data (Dewott's 36, Rufflet's 54, Cubone's 28, ...) use that level instead, so this only ever applies to the stone-shaped rows. 36 by default.",
  },
  {
    key = "trade_level",
    label = "TRADE LEVEL",
    type = "choice",
    default = "40",
    choices = { { "30", "30" }, { "35", "35" }, { "40", "40" },
                { "45", "45" }, { "50", "50" } },
    description = "Trade evolutions -- Kadabra, Machoke, Graveler, Haunter, Onix, Scyther, Seadra, the item trades -- would normally need a second Game Boy. With this set they ALSO fire on a level-up at this level or higher, so a trade evolution is finally reachable in a single-player run. A trade that demands a held item still demands it (via the held-item mark on Gen 1, mon.item on Gen 2). 40 by default.",
  },
  {
    key = "exotic_level",
    label = "EXOTIC LEVEL",
    type = "choice",
    default = "40",
    choices = { { "30", "30" }, { "35", "35" }, { "40", "40" },
                { "45", "45" }, { "50", "50" } },
    description = "The level uncodable evolution conditions are recoded to. national_dex carries conditions this engine has no seam for -- Milcery's spin, Nincada's shed, Primeape's use-move-N-times, Basculin's recoil-damage total, Bisharp's three defeats, Galarian Farfetch'd's three crits, Yamask's take-damage total, Stantler's agile-style move. Rather than leave those species permanently unable to evolve, g9-evolutions turns each into a plain level-up at this level. 40 by default.",
  },
  {
    key = "held_level",
    label = "HELD LEVEL",
    type = "choice",
    default = "40",
    choices = { { "30", "30" }, { "35", "35" }, { "40", "40" },
                { "45", "45" }, { "50", "50" } },
    description = "On Red/Blue/Yellow -- which has no held-item field -- a held-item or item-trade evolution becomes a use-on-a-mon tool gated on a level. This is that level, used whenever the data names no level of its own (Razor Claw into Weavile, King's Rock into Politoed, Metal Coat into Steelix, ...). On Gold/Silver/Crystal a held item is real and this option is unused. 40 by default.",
  },
  {
    key = "gimmighoul_drop",
    label = "GIMMIGHOUL DROP",
    type = "choice",
    default = "20%",
    choices = { { "0%", "0%" }, { "2%", "2%" }, { "5%", "5%" },
                { "10%", "10%" }, { "20%", "20%" } },
    description = "The percent chance a defeated or caught wild Gimmighoul drops a Gimmighoul Coin. Gholdengo needs a pile of them (see GIMMIGHOUL COST). 20% by default; set 0 to disable drops entirely, or 2% for the rarer fallback rate.",
  },
  {
    key = "gimmighoul_cost",
    label = "GIMMIGHOUL COST",
    type = "choice",
    default = "20",
    choices = { { "5", "5" }, { "10", "10" }, { "20", "20" },
                { "30", "30" }, { "40", "40" } },
    description = "How many times the Gimmighoul Coin must be used on a Gimmighoul before it evolves. Each use spends exactly one coin and adds one point to a saved charge on that Pokemon; at this many points it becomes Gholdengo. The coin works on a Gimmighoul and NOTHING else -- not even a Gholdengo -- and cannot overflow the counter. 20 by default.",
  },
  {
    key = "happiness_inspector",
    label = "HAPPINESS INSPECTOR",
    type = "toggle",
    default = true,
    description = "ON (default): the party menu gains a HAPPINESS row that opens an inspector for the selected Pokemon -- its friendship (Gold's real happiness, or the Gen 1 value this mod keeps with GEN 1 FRIENDSHIP on) as a figure and a bar against the thresholds the evolution data uses, the friendship evolutions it is working toward, and how the value rises. OFF: the row and the screen are not installed and the party menu is left exactly as the engine drew it.",
  },
  {
    key = "inspector_style",
    label = "INSPECTOR STYLE",
    type = "choice",
    default = "MODERN",
    choices = { { "MODERN", "MODERN" }, { "NATIVE", "NATIVE" } },
    description = "How the happiness and Gimmighoul inspectors are drawn. MODERN (default): the g9-gui suite's look -- dark translucent panels, the Saira face, accent bars -- matching the modern menu taken over by that mod. NATIVE: the cart's own look -- white paper, a black border and the engine's pixel font -- drawn as the classic 160x144 Game Boy screen scaled to fill the page, so a player who has not installed the modern UI gets a full-screen inspector that matches the cart.",
  },
  {
    key = "gimmighoul_inspector",
    label = "GIMMIGHOUL INSPECTOR",
    type = "toggle",
    default = true,
    description = "ON (default): a Gimmighoul offers an extra party-menu row that opens its coin-charge inspector -- the saved `g9GimmighoulCharge` counter drawn as segments, so a player can see exactly how many coins the Pokemon has swallowed and how many are left before Gholdengo. The row appears on a Gimmighoul only; no other species ever shows it. OFF: the row and the screen are not installed.",
  },
  {
    key = "gen1_friendship",
    label = "GEN 1 FRIENDSHIP",
    type = "toggle",
    default = true,
    description = "ON (default): on Red/Blue/Yellow -- which has no friendship system at all -- g9-evolutions keeps an invisible friendship value for each Pokemon so the friendship evolutions national_dex brings in (Pichu, Cleffa, Togepi, Goomy's kin, Eevee into Espeon/Umbreon, ...) are reachable. A fresh Pokemon starts at 70 and earns friendship as it levels up and wins battles. OFF: friendship evolutions simply never fire on Gen 1 (Gold/Silver/Crystal keep using the engine's real happiness value either way).",
  },
  {
    key = "no_move_evo",
    label = "NO MOVE EVO",
    type = "toggle",
    default = true,
    description = "ON (default): a \"level up while knowing <move>\" evolution (Aipom, Tangela, Yanma, Piloswine, Steenee and the rest of the 14) stops demanding the move and becomes a plain level-up at the level the Pokemon LEARNS that move, plus one -- a move learned at 40 means it evolves at 41. The level comes from national_dex's own learnset (the complete modern one where it has it, the cart's native one otherwise); if the move is not in that Pokemon's level-up learnset at all, the level falls back to the shape of its line: 25 for the first step of a three-stage line, 30 for a two-stage line (Scyther), 35 for the last step of a three-stage line (Piloswine, Steenee). OFF: the original rule stands -- the Pokemon must actually know the move when it levels up.",
  },
  {
    key = "max_pc",
    label = "MAX PC",
    type = "toggle",
    default = true,
    description = "ON (default): the PC's own menus (BILL's PC / <player>'s PC / the item PC, on both Red/Blue/Yellow and Gold/Silver/Crystal) gain a MAX-FACTOR row -- the last option before LOG OFF / SEE YA! / TURN OFF -- that converts 10 MAX CANDY into 1 MAX-FACTOR behind a YES/NO prompt. This is the only way the mod itself mints a G-FACTOR. OFF: the row, its prompt and its conversion are not installed and the PC is left exactly as the engine drew it; the G-FACTOR item itself is unaffected either way (it can still be obtained another way and used on a Gigantamax-capable species).",
  },
}
