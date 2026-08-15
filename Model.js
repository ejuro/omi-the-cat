.pragma library

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, Number(value) || 0))
}

function xpForLevel(level) {
  return 50 + Math.max(0, Number(level) - 1) * 25
}

// Four digits keeps the panel's "LV.NNNN" line from ever overflowing, and
// bounds the level-up loop below. Reaching it legitimately would take tens of
// thousands of meals; it exists to contain a corrupt or hand-edited save.
var levelCap = 9999

function normalizeState(value) {
  var state = value && typeof value === "object" ? value : {}
  var level = Math.max(1, Math.min(levelCap, Math.floor(Number(state.level) || 1)))
  return {
    version: 1,
    level: level,
    // XP is drained by every level-up, so a valid save never holds more than
    // the current level costs. Clamping to that is a no-op for real saves and
    // stops a corrupt value from driving the level-up loop for millions of
    // iterations on the UI thread.
    xp: Math.min(xpForLevel(level), Math.max(0, Math.floor(Number(state.xp) || 0))),
    happiness: clamp(state.happiness === undefined ? 72 : state.happiness, 0, 100),
    // Clamped so a save written before the pantry had a limit — or edited by
    // hand — settles to the cap instead of sitting above it forever.
    foodBags: Math.min(pantryLimit, Math.max(0, Math.floor(Number(state.foodBags) || 0))),
    lifetimeFood: Math.max(0, Math.floor(Number(state.lifetimeFood) || 0)),
    tokenRemainder: Math.max(0, Math.floor(Number(state.tokenRemainder) || 0)),
    observed: state.observed && typeof state.observed === "object" ? state.observed : {},
    lastInteractionAt: String(state.lastInteractionAt || ""),
    // When JOY was last settled. Distinct from lastInteractionAt, which marks
    // care and must not move when decay is merely applied. Blank on upgrade
    // from an older save; the caller anchors it to now so no one is
    // retroactively billed for time served before the feature existed.
    happinessAt: String(state.happinessAt || ""),
    // When the cat last ate. Same upgrade rule: blank means the caller anchors
    // it to now, so nobody opens the panel to a cat that has been starving
    // since before hunger was a thing.
    lastFedAt: String(state.lastFedAt || "")
  }
}

function levelAfterFeed(level, xp, gain) {
  var nextLevel = Math.max(1, Math.floor(Number(level) || 1))
  var nextXp = Math.max(0, Math.floor(Number(xp) || 0)) + Math.max(0, Math.floor(Number(gain) || 0))
  var leveled = false
  // Bounded independently of normalizeState so no caller can spin this loop.
  while (nextLevel < levelCap && nextXp >= xpForLevel(nextLevel)) {
    nextXp -= xpForLevel(nextLevel)
    nextLevel++
    leveled = true
  }
  return { level: nextLevel, xp: nextXp, leveled: leveled }
}

// JOY drifts down on a wall clock, not on shell uptime, so closing the bar or
// suspending the machine neither pauses nor punishes.
//
// The cat has two independent needs, each on its own clock.
//
// JOY is the pat track. It drifts down on a wall clock and is topped back up
// by patting, which is never rate-limited — the 100 ceiling is the only
// limiter, so a pat is always available and simply stops paying once the cat
// is full.
//
// At 20/hour JOY reads as a recency signal rather than a slow mood: a full cat
// is lonely 2.5 hours later and resting on the floor after 4. The floor is
// what keeps that liveable — the cat idles at 20 rather than bottoming out,
// and any single pat visibly moves the meter.
var joyDecayPerHour = 20
var joyFloor = 20

// Hunger is the feed track, and it is what actually sets the daily rhythm. It
// is measured purely as time since the last meal rather than as a slice of
// JOY, so "hungry" means hungry instead of doubling as a severity reading on a
// stat it never really described. Feeding resets the clock and hands the mood
// back to the JOY swings.
// One meal a day. Token spend varies by orders of magnitude between a heavy
// agent user and someone trying Claude Code for the first time, and the
// threshold has to stay low enough that the light user can feed Omi at all —
// so hunger is paced to what roughly a million tokens a day can sustain.
var hungerAfterHours = 24

// How many bags the pantry holds. This is what absorbs heavy users: a low
// per-bag threshold keeps Omi feedable for someone earning ~1M/day, and the
// cap stops someone earning 80M/day from banking hundreds. Overflow is simply
// not awarded — a full pantry means further work goes to waste, which is a
// gentle nudge to go feed the cat.
var pantryLimit = 10

// Interaction rewards. Single-sourced so GameState, the panel hints, and the
// help copy can never disagree about what a pat or a meal is worth.
var joyPerPat = 10
var joyPerFeed = 30
var xpPerFeed = 10

// Returns the settled JOY plus the slice of `elapsedHours` that was actually
// spent on whole points. The caller advances its timestamp by exactly that
// much, so fractional decay carries over instead of being rounded away — the
// reason a short poll interval does not silently decay nothing forever.
function settleJoy(happiness, elapsedHours) {
  var current = clamp(happiness, 0, 100)
  var elapsed = Math.max(0, Number(elapsedHours) || 0)
  // A non-finite interval would hand the caller an unusable timestamp.
  if (!isFinite(elapsed) || elapsed <= 0) return { happiness: current, consumedHours: 0 }
  // Already resting on the floor: retire the whole window. Banking weeks of
  // unspent decay here would make the next pat evaporate on contact.
  if (current <= joyFloor) return { happiness: current, consumedHours: elapsed }

  var points = Math.floor(elapsed * joyDecayPerHour)
  if (points < 1) return { happiness: current, consumedHours: 0 }

  var next = Math.max(joyFloor, current - points)
  if (next <= joyFloor) return { happiness: joyFloor, consumedHours: elapsed }
  return { happiness: next, consumedHours: points / joyDecayPerHour }
}

// Hunger outranks the JOY moods: an unfed cat says so even when it is
// otherwise delighted, which is the whole point of giving it a separate clock.
// A meal hands the mood straight back to the JOY swings below.
function mood(happiness, hungry, reaction) {
  if (reaction === "pat") return "loved"
  if (reaction === "feed") return "eating"
  if (reaction === "level") return "sparkly"
  if (hungry) return "hungry"
  if (Number(happiness) >= 80) return "happy"
  if (Number(happiness) < 50) return "lonely"
  return "calm"
}

// Bar identity. Omarchy's own widgets each own exactly one filled Nerd Font
// glyph and say everything else with color, so Omi the Cat does the same: the
// MDI cat (U+F011B) never changes shape, and the urgent color is reserved for
// the two states the user can actually act on.
var barIcon = "󰄛"


function moodLabel(moodName) {
  var labels = {
    loved: "FEELS LOVED",
    eating: "NOM NOM NOM",
    sparkly: "LEVEL UP!",
    happy: "VERY HAPPY",
    hungry: "NEEDS A SNACK",
    lonely: "WANTS A PAT",
    calm: "DOING FINE"
  }
  return labels[moodName] || labels.calm
}

function meter(value, maximum, width) {
  var count = Math.max(1, Math.floor(Number(width) || 10))
  var ratio = maximum > 0 ? clamp(Number(value) / Number(maximum), 0, 1) : 0
  var filled = Math.round(count * ratio)
  return "[" + "■".repeat(filled) + "·".repeat(count - filled) + "]"
}

function formatTokens(value) {
  var amount = Math.max(0, Number(value) || 0)
  if (amount >= 1000000) return (amount / 1000000).toFixed(amount >= 10000000 ? 0 : 1) + "M"
  if (amount >= 1000) {
    var thousands = (amount / 1000).toFixed(amount >= 100000 ? 0 : 1)
    // 999,999 rounds to "1000K". Promote it, so the progress line reads
    // "1.0M / 1.0M" in the moment before a bag lands rather than "1000K".
    if (Number(thousands) >= 1000) return "1.0M"
    return thousands + "K"
  }
  return String(Math.floor(amount))
}

// Full digits with thousands separators, for prose where "1.0M" reads as a
// rounded guess rather than the exact threshold it is.
function groupDigits(value) {
  var digits = String(Math.max(0, Math.floor(Number(value) || 0)))
  var out = ""
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ","
    out += digits.charAt(i)
  }
  return out
}

function bagCountLabel(foodBags) {
  var bags = Math.max(0, Math.floor(Number(foodBags) || 0))
  if (bags === 0) return "NONE YET"
  if (bags >= pantryLimit) return "×" + bags + " PANTRY FULL"
  return "×" + bags + " READY TO FEED"
}

// Copy for the panel's [?] drawer. Introduces the cat and the one piece of
// vocabulary the UI invents (Token Bag) — not a stat sheet. The exact JOY and
// XP a pat or a meal is worth is deliberately left out; the meters already
// show it happening. The two numbers that do appear are the ones a player
// cannot infer by watching, and both are read from the live settings.
function helpSections(tokensPerBag) {
  var threshold = groupDigits(Math.max(1, Number(tokensPerBag) || 1000000))
  return [
    {
      title: "MEET OMI",
      body: "A cat who lives in your bar. Omi has a peculiar taste in food and will eat exactly one thing: tokens. Nobody has managed to talk Omi out of it."
    },
    {
      title: "TOKEN BAGS",
      body: "Omi will not be satisfied by a token here and there — it takes a proper chunk. That chunk is a Token Bag: " + threshold + " tokens. You earn them just by working; whenever your agents chew through that many, another lands in the pantry. The pantry holds " + pantryLimit + "."
    },
    {
      title: "FEEDING",
      body: "One bag per meal. Omi needs feeding at least once every " + hungerAfterHours + " hours and will make that abundantly clear, but never says no to seconds. Feeding is also how Omi grows up, so a well-fed cat is a distinguished cat."
    },
    {
      title: "PATS",
      body: "Besides food, there is one other thing Omi likes: pats. Especially behind the ear. Pat whenever you pass by — it is free, there is no limit, and it makes Omi happy."
    },
    {
      title: "SMALL PRINT",
      body: "Omi is a cat, not a spy! The token counts come straight from Omarchy's built-in Agents plugin. Nothing else is read."
    }
  ]
}
