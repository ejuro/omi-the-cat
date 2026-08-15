import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  visible: false

  // Fixed, not a setting: a level means the same amount of work on every
  // machine only if nobody can move the goalposts.
  readonly property int tokensPerBag: 1000000
  property int level: 1
  property int xp: 0
  property int happiness: 72
  property int foodBags: 0
  property int lifetimeFood: 0
  property int tokenRemainder: 0
  property var observed: ({})
  property string lastInteractionAt: ""
  property string happinessAt: ""
  property string lastFedAt: ""
  // Bindings cannot re-evaluate Date.now() on their own, so the poll timer
  // nudges this and everything time-derived follows.
  property double clockMs: Date.now()
  property string reaction: ""
  property bool loaded: false
  property var agentIds: []
  property var agents: []

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string stateRoot: stateHome + "/omi-the-cat"
  readonly property string statePath: stateRoot + "/state.json"
  // Derived from the shared base rather than by rewriting the tail of
  // stateRoot: the old form hid a dependency on this plugin's own folder name
  // and would have silently stopped finding the Agents records when it changed.
  readonly property string usageRoot: stateHome + "/omarchy/agents/usage"
  readonly property int xpNeeded: Model.xpForLevel(level)
  readonly property real hoursSinceFed: {
    var fed = Date.parse(lastFedAt)
    if (!isFinite(fed)) return 0
    return Math.max(0, (clockMs - fed) / 3600000)
  }
  // An unset meal clock is never hungry; loadState anchors it on first run.
  readonly property bool hungry: lastFedAt !== "" && hoursSinceFed >= Model.hungerAfterHours
  readonly property string mood: Model.mood(happiness, hungry, reaction)
  readonly property string moodLabel: Model.moodLabel(mood)
  readonly property int progressToBag: Math.max(0, tokenRemainder)

  signal rewarded(int bags)
  signal leveledUp(int level)

  Process {
    id: ensureStateDir
    command: ["mkdir", "-p", root.stateRoot]
    running: false
    onExited: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  Timer {
    id: saveTimer
    interval: 120
    repeat: false
    onTriggered: root.flushState()
  }

  Timer {
    id: reactionTimer
    interval: 1700
    repeat: false
    onTriggered: root.reaction = ""
  }

  // At 20 JOY/hour a point lands every three minutes, so the meter has to tick
  // at least that often to stay honest while the panel is open. Settling is a
  // subtraction against a stored timestamp, so the extra ticks cost nothing.
  Timer {
    id: decayTimer
    interval: 60000
    repeat: true
    running: root.loaded
    onTriggered: {
      root.clockMs = Date.now()
      root.settleHappiness()
    }
  }

  Process {
    id: listAgents
    command: ["find", root.usageRoot, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAgentListing(text)
    }
  }

  Instantiator {
    id: agentInstantiator
    model: root.agentIds
    delegate: UsageRecord {
      required property var modelData
      agentId: modelData
      path: root.usageRoot + "/" + modelData + ".json"
      onRecordChanged: root.reconcileUsage()
    }
    onObjectAdded: function(index, object) { root.rebuildAgents() }
    onObjectRemoved: function(index, object) { root.rebuildAgents() }
  }

  function applyAgentListing(output) {
    var ids = []
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name.slice(-5) === ".json") ids.push(name.slice(0, -5))
    }
    ids.sort()
    agentIds = ids
  }

  function rebuildAgents() {
    var result = []
    for (var i = 0; i < agentInstantiator.count; i++) {
      var agent = agentInstantiator.objectAt(i)
      if (agent) result.push(agent)
    }
    agents = result
    reconcileUsage()
  }

  function loadState(raw) {
    if (loaded && String(raw || "").trim() === "") return
    var parsed = {}
    try {
      if (String(raw || "").trim() !== "") parsed = JSON.parse(raw)
    } catch (error) {
      console.warn("omi-the-cat", "State file is invalid; using safe defaults", error)
    }
    var next = Model.normalizeState(parsed)
    level = next.level
    xp = next.xp
    happiness = next.happiness
    foodBags = next.foodBags
    lifetimeFood = next.lifetimeFood
    tokenRemainder = next.tokenRemainder
    observed = next.observed
    lastInteractionAt = next.lastInteractionAt
    happinessAt = next.happinessAt
    lastFedAt = next.lastFedAt
    clockMs = Date.now()
    loaded = true
    // A save from before hunger existed has no meal clock. Start it now rather
    // than treating "never fed" as "starving since the epoch".
    if (lastFedAt === "") {
      lastFedAt = new Date().toISOString()
      scheduleSave()
    }
    // Catch up on whatever elapsed while the shell was not running, then keep
    // the periodic timer honest from here.
    settleHappiness()
    listAgents.running = true
  }

  function stateObject() {
    return {
      version: 1,
      level: level,
      xp: xp,
      happiness: happiness,
      foodBags: foodBags,
      lifetimeFood: lifetimeFood,
      tokenRemainder: tokenRemainder,
      observed: observed,
      lastInteractionAt: lastInteractionAt,
      happinessAt: happinessAt,
      lastFedAt: lastFedAt
    }
  }

  function scheduleSave() {
    if (loaded) saveTimer.restart()
  }

  function flushState() {
    stateFile.setText(JSON.stringify(stateObject(), null, 2) + "\n")
  }

  function todayKey() {
    return Qt.formatDate(new Date(), "yyyy-MM-dd")
  }

  function reconcileUsage() {
    if (!loaded) return
    var nextObserved = {}
    for (var previousId in observed) nextObserved[previousId] = observed[previousId]
    var gainedTokens = 0
    var date = todayKey()

    for (var i = 0; i < agents.length; i++) {
      var agent = agents[i]
      var record = agent ? agent.record : null
      if (!record) continue
      var id = String(record.id || agent.agentId || "")
      if (id === "") continue
      var current = Math.max(0, Math.floor(Number(record.todayTotalTokens) || 0))
      var previous = nextObserved[id]
      if (!previous || previous.date !== date) {
        // New installs establish a baseline and earn nothing retroactively.
        //
        // On a day rollover the agent's own counter resets too, but not
        // necessarily before this scan runs. A counter that has already reset
        // reads lower than yesterday's figure, and all of it is new usage. One
        // that has not yet reset still shows yesterday's total, so only the
        // increase counts — crediting it whole would hand over a full day of
        // tokens at midnight.
        if (previous) {
          var yesterday = Number(previous.tokens || 0)
          gainedTokens += current < yesterday ? current : Math.max(0, current - yesterday)
        }
      } else if (current > Number(previous.tokens || 0)) {
        gainedTokens += current - Number(previous.tokens || 0)
      }
      nextObserved[id] = { date: date, tokens: current }
    }

    observed = nextObserved
    if (gainedTokens > 0) {
      var total = tokenRemainder + gainedTokens
      var threshold = Math.max(1, Number(tokensPerBag) || 1000000)
      var bags = Math.floor(total / threshold)
      tokenRemainder = total % threshold
      if (bags > 0) {
        // Earn past a full pantry and the surplus is dropped rather than
        // banked. Progress keeps cycling, so the moment a meal frees a slot
        // the next scan can fill it again.
        var awarded = Math.min(bags, Math.max(0, Model.pantryLimit - foodBags))
        if (awarded > 0) {
          foodBags += awarded
          rewarded(awarded)
        }
      }
    }
    scheduleSave()
  }

  function react(name) {
    reaction = name
    reactionTimer.restart()
  }

  // Applies the JOY owed since the last settlement. The timestamp advances by
  // exactly the hours spent on whole points, so the sub-point remainder is
  // carried rather than discarded.
  function settleHappiness() {
    if (!loaded) return
    var nowMs = Date.now()
    var sinceMs = Date.parse(happinessAt)

    // No anchor yet (fresh install or a save from before decay existed), or the
    // clock jumped backwards over an NTP correction: re-anchor to now instead
    // of decaying against a nonsense interval.
    if (!isFinite(sinceMs) || nowMs < sinceMs) {
      happinessAt = new Date(nowMs).toISOString()
      scheduleSave()
      return
    }

    var result = Model.settleJoy(happiness, (nowMs - sinceMs) / 3600000)
    if (result.consumedHours <= 0) return
    happiness = result.happiness
    happinessAt = new Date(sinceMs + result.consumedHours * 3600000).toISOString()
    scheduleSave()
  }

  // Never rate-limited: the cat is always available for a pat. The 100 ceiling
  // is the only limiter, so patting a full cat is simply its own reward.
  function pat() {
    settleHappiness()
    clockMs = Date.now()
    happiness = Math.min(100, happiness + Model.joyPerPat)
    lastInteractionAt = new Date().toISOString()
    react("pat")
    scheduleSave()
  }

  function feed() {
    if (foodBags < 1) return false
    settleHappiness()
    foodBags--
    lifetimeFood++
    happiness = Math.min(100, happiness + Model.joyPerFeed)
    var result = Model.levelAfterFeed(level, xp, Model.xpPerFeed)
    level = result.level
    xp = result.xp
    // Resets the meal clock, which hands the mood back to the JOY swings.
    var stamp = new Date()
    clockMs = stamp.getTime()
    lastFedAt = stamp.toISOString()
    lastInteractionAt = stamp.toISOString()
    react(result.leveled ? "level" : "feed")
    if (result.leveled) leveledUp(level)
    scheduleSave()
    return true
  }

  Component.onCompleted: ensureStateDir.running = true
}
