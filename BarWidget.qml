import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.ejuro.omi-the-cat"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.game = game
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  GameState {
    id: game
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Leave this file out of any qmllint run. Current qmllint aborts with exit
  // 255 and no diagnostic on any file declaring an IpcHandler, down to a
  // four-line one, so a failure here says nothing about this file.
  IpcHandler {
    target: "io.github.ejuro.omi-the-cat"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function pat(): void { game.pat() }
    function feed(): void { game.feed() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.barIcon
    // The MDI cat is a wide, short glyph: at a given pixel size its ink is
    // ~87 units tall where the stock bar icons run 95-123, so it reads as
    // undersized next to them. OpticalGlyph only corrects horizontal
    // centring — it never rescales — so the correction has to happen here.
    // Expressed as a ratio so it follows the theme's own icon size, and the
    // slot size is left alone so bar spacing does not shift.
    fontSize: Style.bar.iconFont * 1.15
    tooltipText: "Omi · " + game.moodLabel
      + " · Lv." + game.level
      + " · " + (game.foodBags > 0
        ? game.foodBags + (game.foodBags === 1 ? " Token Bag ready" : " Token Bags ready")
        : "no Token Bags yet")
    // Hunger is the only thing that colours the icon; the rest of the time it
    // matches every other bar widget. A waiting Token Bag is good news, not an
    // alert, so it stays in the normal foreground.
    active: game.mood === "hungry"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) game.pat()
      else root.toggle()
    }
  }
}
