import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ejuro.omi-the-cat"
  ipcTarget: "io.github.ejuro.omi-the-cat"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var game: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // The theme's own accent key, not bar.urgent. The latter resolves to Base16
  // base08 — the error slot — which is red in nearly every theme, so ordinary
  // chrome was being painted in the alarm colour. Genuine alerts still use
  // Color.urgent; this is for emphasis.
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int selectedAction: 0
  // The action cursor is only painted once the keyboard is actually driving.
  // Otherwise PAT would sit highlighted from the moment the panel opens and
  // read as a stuck or pressed button to anyone using the mouse.
  property bool keyboardNav: false
  property int animationFrame: 0
  property bool helpExpanded: false
  // The help sheet is a detour, not a place to be left. Clearing it on close
  // rather than in open() catches every dismissal path — Escape, clicking
  // away, a popout switch, IPC — so the panel always reopens on the cat.
  onOpenedChanged: if (!opened) helpExpanded = false

  function open() {
    root.animationFrame = 0
    root.keyboardNav = false
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) close(); else open() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }
  function activateAction() {
    if (!game || helpExpanded) return
    if (selectedAction === 0) game.pat()
    else game.feed()
  }

  // Reactions and the dance both run on the faster cadence: at 420ms the
  // four-beat dance loop takes most of two seconds and reads as a slideshow
  // rather than a cat keeping time.
  Timer {
    interval: root.game && (root.game.reaction !== "" || root.game.mood === "dancing") ? 240 : 420
    running: root.opened
    repeat: true
    onTriggered: root.animationFrame = (root.animationFrame + 1) % 120
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.helpExpanded) return
        if (dx === 0 && dy === 0) return
        root.keyboardNav = true
        root.selectedAction = root.selectedAction === 0 ? 1 : 0
      }
      onActivateRequested: {
        if (!root.helpExpanded) root.keyboardNav = true
        root.activateAction()
      }
      // Escape peels off the help sheet first, then closes the panel.
      onCloseRequested: {
        if (root.helpExpanded) root.helpExpanded = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "?" || text === "h" || text === "H") root.helpExpanded = !root.helpExpanded
        else if (!root.game || root.helpExpanded) return
        else if (text === "p" || text === "P") root.game.pat()
        else if (text === "f" || text === "F") root.game.feed()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)
        // Faded rather than hidden: opacity leaves implicitHeight untouched,
        // so the card keeps its size while the help sheet is up.
        opacity: root.helpExpanded ? 0 : 1
        enabled: !root.helpExpanded

        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        Item {
          width: parent.width
          height: Math.max(headerLine.implicitHeight, helpToggle.height)

          Text {
            id: headerLine
            anchors.centerIn: parent
            text: "╭───────────── Omi ─────────────╮"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          HelpToggle {
            id: helpToggle
            anchors {
              right: parent.right
              verticalCenter: parent.verticalCenter
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(194)

          Column {
            anchors.centerIn: parent
            // Matches the visual gap above the art rather than the nominal
            // one. AsciiSprite puts Style.space(5) between the speech and the
            // grid, but row 0 is the effects row and is blank for every mood
            // except loved and sparkly — so the eye sees that margin plus one
            // empty cell. Reusing both terms keeps it matched under font
            // scaling instead of pinning a magic number.
            spacing: Style.space(5) + sprite.cellHeight

            AsciiSprite {
              id: sprite
              anchors.horizontalCenter: parent.horizontalCenter
              mood: root.game ? root.game.mood : "calm"
              frame: root.animationFrame
              foreground: root.foreground
              accent: root.accent
              urgent: Color.urgent
              fontFamily: root.fontFamily
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.game ? "< " + root.game.moodLabel + " >" : "< BOOTING >"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        // The level sits on its own line above the meters so it cannot push
        // the XP bar out of step with the JOY bar as it grows past LV.99.
        //
        // The meter rows are left-aligned against each other inside a column
        // that is itself centred, rather than each row being centred on its
        // own. Centring per row would misalign the bars again the moment the
        // trailing values differ in width ("35/200" versus "100%").
        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(4)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "LV." + (root.game ? String(root.game.level).padStart(2, "0") : "01")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            text: root.game
              ? "XP".padEnd(3) + "  " + Model.meter(root.game.xp, root.game.xpNeeded, 16) + "  " + root.game.xp + "/" + root.game.xpNeeded
              : "XP".padEnd(3) + "  [················]"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            text: root.game
              ? "JOY".padEnd(3) + "  " + Model.meter(root.game.happiness, 100, 16) + "  " + root.game.happiness + "%"
              : "JOY".padEnd(3) + "  [················]"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.foreground
          opacity: 0.25
        }

        // Pantry. Named in full and placed above the FEED button so the cost
        // of feeding is on screen before the button that spends it.
        Rectangle {
          width: parent.width
          height: pantryColumn.implicitHeight + Style.space(18)
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)

          Column {
            id: pantryColumn
            anchors.centerIn: parent
            spacing: Style.space(3)

            // Split so the accent lands on the count alone — the one number
            // that says whether FEED will do anything — while the label stays
            // in the ordinary foreground. An empty pantry is not worth
            // highlighting, so "NONE YET" is left plain.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter

              Text {
                text: "TOKEN BAGS  "
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: root.game ? Model.bagCountLabel(root.game.foodBags) : "NONE YET"
                color: root.game && root.game.foodBags > 0 ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              // A full pantry says so rather than showing a meter that can
              // never pay out — earning past the cap is dropped, not banked.
              text: !root.game
                ? "NEXT BAG  [············]  TOKENS USED"
                : root.game.foodBags >= Model.pantryLimit
                  ? "PANTRY FULL  ·  FEED OMI TO MAKE ROOM"
                  : "NEXT BAG  [" + Model.meter(root.game.progressToBag, root.game.tokensPerBag, 12).slice(1, -1) + "]  "
                    + Model.formatTokens(root.game.progressToBag) + " / " + Model.formatTokens(root.game.tokensPerBag) + " TOKENS USED"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Spans the full content width so the buttons share their left and
        // right edges with the pantry box and the key hints. They were the
        // only inset element in the column.
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(10)
          readonly property real cellWidth: (width - spacing) / 2

          ActionCell {
            width: actionRow.cellWidth
            label: "[ P ] PAT"
            hint: "FREE"
            selected: root.selectedAction === 0
            onClicked: if (root.game) root.game.pat()
          }

          ActionCell {
            width: actionRow.cellWidth
            label: "[ F ] FEED"
            hint: "−1 TOKEN BAG"
            selected: root.selectedAction === 1
            enabled: root.game && root.game.foodBags > 0
            onClicked: if (root.game) root.game.feed()
          }
        }

        Text {
          width: parent.width
          text: "P/F: CARE  ·  ?: HELP  ·  ←/→: SELECT  ·  ESC: CLOSE"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          text: "╰───────────────────────────────╯"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }
      }

      // Help sheet. Painted over the card instead of inside the column so
      // opening it never resizes the panel — the cat stays put underneath.
      Item {
        id: helpSheet
        anchors.fill: parent
        z: 10
        clip: true
        // The card's own background shows through; the content column beneath
        // is faded to zero, so the sheet needs no fill of its own and never
        // double-composites a translucent theme's popup color.
        visible: opacity > 0
        opacity: root.helpExpanded ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        // Swallows clicks so nothing underneath reacts while the sheet is up.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
        }

        Text {
          id: helpHeading
          anchors {
            top: parent.top
            left: parent.left
            right: parent.right
          }
          text: "╭────────── ABOUT OMI ──────────╮"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        HelpToggle {
          id: helpSheetToggle
          anchors {
            top: parent.top
            right: parent.right
          }
        }

        Column {
          id: helpColumn
          anchors {
            top: helpSheetToggle.bottom
            topMargin: Style.space(12)
            left: parent.left
            right: parent.right
          }
          spacing: Style.space(9)

          Repeater {
            model: Model.helpSections(root.game ? root.game.tokensPerBag : 1000000)

            delegate: Column {
              id: helpSection
              required property var modelData
              width: helpColumn.width
              spacing: Style.space(1)

              Text {
                width: parent.width
                text: helpSection.modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                width: parent.width
                text: helpSection.modelData.body
                color: root.foreground
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }
        }

        Text {
          anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
          }
          text: "?  OR  ESC  TO GO BACK"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // `selected` is the keyboard cursor only — clicking never latches it, so a
  // mouse press leaves no highlight behind once the pointer moves away. This
  // matches qs.Ui's own controls, where the hot state is hover-or-cursor.
  component ActionCell: Rectangle {
    id: action
    property string label: ""
    property string hint: ""
    property bool selected: false
    readonly property bool cursor: selected && root.keyboardNav
    readonly property bool hot: (actionMouse.containsMouse || cursor) && enabled
    signal clicked()

    // Callers set the width; this is only a fallback for a bare instance.
    width: Style.space(150)
    height: Style.space(46)
    radius: Style.cornerRadius
    color: hot ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    border.width: cursor ? 2 : 1
    border.color: enabled ? (cursor ? root.accent : root.foreground) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
    opacity: enabled ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 60 } }

    // Top-anchored rather than centered so both labels sit on the same line
    // whether or not the cell carries a hint underneath.
    Text {
      id: actionLabel
      anchors {
        top: parent.top
        topMargin: Style.space(10)
        horizontalCenter: parent.horizontalCenter
      }
      text: action.label
      color: action.cursor ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      visible: action.hint !== ""
      anchors {
        top: actionLabel.bottom
        topMargin: Style.space(3)
        horizontalCenter: parent.horizontalCenter
      }
      text: action.hint
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      enabled: action.enabled
      hoverEnabled: true
      cursorShape: action.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Touching a button with the pointer hands the highlight back to the
      // mouse, so the keyboard cursor never lingers next to a hovered cell.
      onContainsMouseChanged: if (containsMouse) root.keyboardNav = false
      onClicked: action.clicked()
    }
  }

  component HelpToggle: Rectangle {
    width: Style.space(24)
    height: Style.space(22)
    radius: Style.cornerRadius
    color: root.helpExpanded || helpToggleMouse.containsMouse
      ? Style.hoverFillFor(root.foreground, root.accent)
      : "transparent"
    border.width: root.helpExpanded ? 2 : 1
    border.color: root.helpExpanded ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)

    Behavior on color { ColorAnimation { duration: 60 } }

    Text {
      anchors.centerIn: parent
      text: root.helpExpanded ? "×" : "?"
      color: root.helpExpanded ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    MouseArea {
      id: helpToggleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.helpExpanded = !root.helpExpanded
    }
  }

}
