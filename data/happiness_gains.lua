-- data/happiness_gains.lua -- what raises Gen 2 friendship, and by how much.
--
-- The happiness inspector prints ONE FIGURE PER ACTION, and the figure is not a
-- constant: the cart's ChangeHappiness looks the step up in
-- data/events/happiness_changes.asm -- a `table_width 3` block whose three
-- columns are chosen by the value BEFORE the change (below 100, below 200, and
-- 200 or more).  A mon that already adores you gains less.  This file carries
-- that table, the labels, and the tier rule, so the screen can print `+5` at 40
-- friendship and `+2` at 210 without inventing anything.
--
-- It is a FALLBACK and a label table, not the authority.  At load time main.lua
-- tries to require the engine's own src/core/gen2/Happiness -- the module that
-- actually MOVES the byte -- and hands it here through the inspector's ctx, and
-- every figure is asked of IT first (Happiness.delta(event, current): the engine
-- already knows the names and the numbers).  Only when that require fails -- an
-- engine older than the one that added the module -- do the rows below answer,
-- and they are transcribed row for row from the same asm block, so the two
-- agree by construction.  The labels and the order are this file's own either
-- way: the engine has no opinion about what a menu should say.
--
-- Only the RAISING events are listed.  A screen about how happiness goes up has
-- no business printing the bitter herbs and the faints.
local M = {}

-- The byte, and the value a mon starts on (constants/pokemon_data_constants.asm,
-- "significant happiness values"; a FRIEND_BALL catch comes in at 200).
M.MAX = 255
M.START = 70

-- The tier boundaries, straight off HappinessChanges' `e` counter: under 100
-- reads column 1, under 200 column 2, else column 3.
M.TIERS = { 100, 200 }

-- A value inside each tier, used when asking the engine (or the table below)
-- for that column's figure.
M.TIER_SAMPLE = { 0, 100, 200 }

-- StepHappiness: one point for the whole party every 512 footfalls.  It has no
-- HAPPINESS_* event of its own -- the routine runs on every 256-step wrap and
-- pays out every other time, and its step is always one point.
M.WALK_STEPS = 512

-- name -> { below 100, below 200, 200 up }.  The keys are the engine's own
-- HAPPINESS_* names, which Happiness.delta accepts with or without the prefix.
-- GetSecondHappiness's Crystal-only "gained a level where it was caught" row is
-- here too (10/6/4) -- it is the same event, picked by Happiness.levelUpEvent.
M.GAINS = {
  GAINLEVEL       = {  5,  3,  2 },
  USEDITEM        = {  5,  3,  2 },
  USEDXITEM       = {  1,  1,  0 },
  GYMBATTLE       = {  3,  2,  1 },
  LEARNMOVE       = {  1,  1,  0 },
  OLDERCUT1       = {  1,  1,  1 },
  OLDERCUT2       = {  3,  3,  1 },
  OLDERCUT3       = {  5,  5,  2 },
  YOUNGCUT1       = {  1,  1,  1 },
  YOUNGCUT2       = {  3,  3,  1 },
  YOUNGCUT3       = { 10, 10,  4 },
  GROOMING        = {  3,  3,  1 },
  GAINLEVELATHOME = { 10,  6,  4 },
}

-- What the screen prints, in the order it prints it, each row carrying the
-- label a wide panel shows and the shorter one the 160x144 grid uses.
-- `events` is the set the row summarises: one name for a single action, the six
-- hairstyles for HAIRCUT (whose styles pay anywhere from +1 to +10, so that row
-- prints a SPAN rather than one figure).  `walk` is StepHappiness, which has no
-- event name because no HAPPINESS_* constant describes it.
M.RAISERS = {
  { label = "LEVEL UP",   short = "LEVEL", events = { "GAINLEVEL" } },
  { label = "VITAMIN",    short = "VIT",   events = { "USEDITEM" } },
  { label = "GYM BATTLE", short = "GYM",   events = { "GYMBATTLE" } },
  { label = "HAIRCUT",    short = "HAIR",  events = {
      "OLDERCUT1", "OLDERCUT2", "OLDERCUT3",
      "YOUNGCUT1", "YOUNGCUT2", "YOUNGCUT3" } },
  { label = "GROOMING",   short = "GROOM", events = { "GROOMING" } },
  { label = "TM MOVE",    short = "TM",    events = { "LEARNMOVE" } },
  { label = "WALK 512",   short = "WALK",  walk = true },
}

-- Which column a value reads: 1, 2 or 3.  The asm's own `e` counter.
function M.tierOf(value)
  value = tonumber(value) or 0
  if value < M.TIERS[1] then return 1 end
  if value < M.TIERS[2] then return 2 end
  return 3
end

-- One HAPPINESS_* name's step at a value.  The engine's answer first (it is the
-- module that owns the table, so a retuned engine is followed rather than
-- contradicted), the transcription otherwise.
function M.deltaOf(engine, event, value)
  if engine and type(engine.delta) == "function" then
    local ok, step = pcall(engine.delta, event, value)
    if ok and type(step) == "number" then return step end
  end
  local row = M.GAINS[event]
  if not row then return nil end
  return row[M.tierOf(value)]
end

-- A raiser's three tier figures as { min, max } spans -- one figure per tier
-- unless the row covers several styles (HAIRCUT).  nil entries are dropped, and
-- a row nothing could answer returns three { 0, 0 } spans so the caller always
-- has three printable columns.
function M.spansOf(engine, entry)
  local spans = {}
  for tier = 1, 3 do
    local lo, hi
    if entry and entry.walk then
      lo, hi = 1, 1
    else
      for _, name in ipairs((entry and entry.events) or {}) do
        local step = M.deltaOf(engine, name, M.TIER_SAMPLE[tier])
        if step then
          if lo == nil or step < lo then lo = step end
          if hi == nil or step > hi then hi = step end
        end
      end
    end
    if lo == nil then lo, hi = 0, 0 end
    spans[tier] = { lo, hi }
  end
  return spans
end

return M
