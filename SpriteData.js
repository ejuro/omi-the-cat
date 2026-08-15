.pragma library

// Omi: a chunky white cat rendered on a fixed character
// grid. Every frame of every mood is exactly `columns` wide and `rowCount`
// tall so mood/animation switches never shift the surrounding layout.
//
// Design language (shared by all states):
//   ears     /\  tips over  /  \___/  \  bases (pinned flat when sad)
//   eyes     o o calm | ^ ^ happy | O O hungry | . . sad | * * level up
//   blink    - -
//   mouth    w cat mouth | o open | ~ sad wobble
//   whiskers --   -- fanned on both cheeks
//   paws     (  )  (  )  side by side under the body
//   tail     always on the right: resting, wagging up, or flat when sad
//   dish     \_/ on the floor, left side (empty when hungry, full while
//            eating)

var columns = 27
var rowCount = 13

function pad(line) {
  var text = String(line || "")
  if (text.length > columns) return text.slice(0, columns)
  return text + " ".repeat(columns - text.length)
}

// Overwrite characters in-place at a fixed cell position. Frames are
// composed by stamping small details onto a shared body template, which
// keeps the silhouette identical between moods.
function put(rows, row, col, text) {
  var value = String(text || "")
  if (row < 0 || row >= rows.length || value === "") return
  var line = rows[row]
  rows[row] = line.slice(0, col) + value + line.slice(col + value.length)
}

// Base sitting body. Face details are stamped on afterwards.
//   row 0      effects (hearts, confetti)
//   rows 1-2   ears
//   row 3      head top / brow line
//   row 4      eyes
//   row 5      whiskers + mouth
//   rows 6-10  body (flaring out at row 7)
//   rows 11-12 haunches and front paws
function sittingBody() {
  var rows = [
    "",
    "       /\\         /\\",
    "      /  \\_______/  \\",
    "     /               \\",
    "    |                 |",
    "    |                 |",
    "    |                 |",
    "   /                   \\",
    "   |                   |",
    "   |                   |",
    "   |                   |",
    "    \\    __     __    /",
    "     \\__(  )___(  )__/"
  ]
  for (var i = 0; i < rows.length; i++) rows[i] = pad(rows[i])
  return rows
}

// Slumped variant for the lonely cat: ears pinned flat and the whole head
// sunk one row lower. Body and paws stay identical to the sitting pose.
function slumpedBody() {
  var rows = [
    "",
    "",
    "      /\\___________/\\",
    "     /               \\",
    "    |                 |",
    "    |                 |",
    "   /                   \\",
    "   |                   |",
    "   |                   |",
    "   |                   |",
    "   |                   |",
    "    \\    __     __    /",
    "     \\__(  )___(  )__/"
  ]
  for (var i = 0; i < rows.length; i++) rows[i] = pad(rows[i])
  return rows
}

function stampWhiskers(rows, eyeRow) {
  put(rows, eyeRow, 2, "--")
  put(rows, eyeRow, 23, "--")
  put(rows, eyeRow + 1, 2, "--")
  put(rows, eyeRow + 1, 23, "--")
}

// Front legs standing between the haunches, continuing the inner paw
// edges upward. Skipped while the arms are raised.
function stampLegs(rows) {
  put(rows, 9, 11, "|")
  put(rows, 9, 15, "|")
  put(rows, 10, 11, "|")
  put(rows, 10, 15, "|")
  put(rows, 11, 11, "|")
  put(rows, 11, 15, "|")
}

// Front paws thrown in the air for the level-up celebration.
function stampArms(rows) {
  put(rows, 1, 0, "_")
  put(rows, 2, 1, "\\")
  put(rows, 3, 2, "\\")
  put(rows, 4, 3, "\\")
  put(rows, 1, 26, "_")
  put(rows, 2, 25, "/")
  put(rows, 3, 24, "/")
  put(rows, 4, 23, "/")
}

// Tail overlays in the free cells right of the body.
function stampTail(rows, pose) {
  if (pose === "restA") {
    put(rows, 12, 22, "___/")
  } else if (pose === "restB") {
    put(rows, 12, 22, "__/")
    put(rows, 11, 25, "/")
  } else if (pose === "upA") {
    put(rows, 11, 23, "/")
    put(rows, 10, 24, "/")
    put(rows, 9, 25, "|")
    put(rows, 8, 25, "|")
  } else if (pose === "upB") {
    put(rows, 11, 23, "/")
    put(rows, 10, 24, "/")
    put(rows, 9, 25, "/")
    put(rows, 8, 26, "/")
  } else if (pose === "flat") {
    put(rows, 12, 22, "____")
  }
}

// Occasionally folds one ear tip flat for a single frame.
function stampEarTwitch(rows, t) {
  if (t % 16 === 5) put(rows, 1, 18, "__")
  else if (t % 16 === 13) put(rows, 1, 7, "__")
}

// Floor dish, left of the cat. `food` draws kibble above the rim.
function stampDish(rows, food) {
  put(rows, 12, 0, "\\_/")
  if (food === "full") put(rows, 11, 0, ".:.")
  else if (food === "half") put(rows, 11, 0, ".")
}

function frame(mood, tick) {
  var t = Math.max(0, Math.floor(Number(tick) || 0))
  var alternate = t % 4 >= 2
  var flip = t % 2 === 1
  var blink = t % 12 === 9

  var speech = ""
  var speechRole = "accent"
  var rows

  if (mood === "lonely") {
    rows = slumpedBody()
    stampLegs(rows)
    stampWhiskers(rows, 4)
    put(rows, 3, 9, "/")
    put(rows, 3, 17, "\\")
    put(rows, 4, 9, blink ? "-" : ".")
    put(rows, 4, 17, blink ? "-" : ".")
    put(rows, 5, 13, "~")
    put(rows, alternate ? 6 : 5, 17, alternate ? "," : "'")
    stampTail(rows, "flat")
    speech = "pat pls?"
    speechRole = "urgent"
  } else if (mood === "hungry") {
    rows = sittingBody()
    stampLegs(rows)
    stampWhiskers(rows, 4)
    put(rows, 4, 9, blink ? "-" : "O")
    put(rows, 4, 17, blink ? "-" : "O")
    put(rows, 5, 13, "o")
    put(rows, alternate ? 6 : 5, 14, alternate ? "," : "'")
    stampDish(rows, "empty")
    stampTail(rows, alternate ? "restA" : "restB")
    speech = "food pls?"
    speechRole = "urgent"
  } else if (mood === "loved") {
    rows = sittingBody()
    stampLegs(rows)
    stampWhiskers(rows, 4)
    put(rows, 4, 9, "^")
    put(rows, 4, 17, "^")
    put(rows, 5, 13, "w")
    put(rows, 0, alternate ? 5 : 9, "<3")
    put(rows, 0, alternate ? 19 : 15, "<3")
    stampTail(rows, flip ? "upA" : "upB")
    speech = alternate ? "thank u!" : "purrr..."
  } else if (mood === "eating") {
    rows = sittingBody()
    stampLegs(rows)
    stampWhiskers(rows, 4)
    put(rows, 4, 9, "^")
    put(rows, 4, 17, "^")
    put(rows, 5, 13, flip ? "o" : "w")
    stampDish(rows, alternate ? "half" : "full")
    stampTail(rows, "restA")
    speech = alternate ? "cronch!" : "nom nom"
  } else if (mood === "sparkly") {
    rows = sittingBody()
    stampArms(rows)
    put(rows, 5, 2, "--")
    put(rows, 5, 23, "--")
    put(rows, 4, 9, flip ? "^" : "*")
    put(rows, 4, 17, flip ? "^" : "*")
    put(rows, 5, 13, "O")
    put(rows, 0, 4, flip ? "*   +   *   +   *" : "+   *   +   *   +")
    stampTail(rows, flip ? "upA" : "upB")
    speech = alternate ? "yay! +1" : "LEVEL UP!"
  } else if (mood === "happy") {
    rows = sittingBody()
    stampLegs(rows)
    stampWhiskers(rows, 4)
    put(rows, 4, 9, "^")
    put(rows, 4, 17, "^")
    put(rows, 5, 13, "w")
    stampEarTwitch(rows, t)
    stampTail(rows, flip ? "upA" : "upB")
    speech = "life is guud"
  } else {
    rows = sittingBody()
    stampLegs(rows)
    stampWhiskers(rows, 4)
    put(rows, 4, 9, blink ? "-" : "o")
    put(rows, 4, 17, blink ? "-" : "o")
    put(rows, 5, 13, "w")
    stampEarTwitch(rows, t)
    stampTail(rows, alternate ? "restA" : "restB")
  }

  return {
    rows: rows,
    columns: columns,
    speech: speech,
    speechRole: speechRole
  }
}
