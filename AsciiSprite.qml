import QtQuick
import qs.Commons
import "SpriteData.js" as SpriteData

Item {
  id: root

  property string mood: "calm"
  property int frame: 0
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  property real cellWidth: Style.spaceReal(7.5)
  property real cellHeight: Style.spaceReal(10.5)
  property real fontSize: Style.font.bodySmall

  readonly property var sprite: SpriteData.frame(mood, frame)
  readonly property real gridWidth: sprite.columns * cellWidth
  readonly property real gridHeight: sprite.rows.length * cellHeight

  implicitWidth: gridWidth
  implicitHeight: speech.implicitHeight + Style.space(5) + gridHeight

  function cellColor(character, row) {
    if (row === 0 && character !== " ") return accent
    if (character === "<" || character === "3" || character === "+" || character === "*") return accent
    return foreground
  }

  Text {
    id: speech
    anchors {
      top: parent.top
      horizontalCenter: parent.horizontalCenter
    }
    text: root.sprite.speech === "" ? "" : "< " + root.sprite.speech + " >"
    color: root.sprite.speechRole === "urgent" ? root.urgent : root.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Item {
    id: grid
    anchors {
      top: speech.bottom
      topMargin: Style.space(5)
      horizontalCenter: parent.horizontalCenter
    }
    width: root.gridWidth
    height: root.gridHeight

    Repeater {
      model: root.sprite.rows

      delegate: Item {
        id: rowItem
        required property string modelData
        required property int index
        property int rowIndex: index
        y: rowIndex * root.cellHeight
        width: grid.width
        height: root.cellHeight

        Repeater {
          model: rowItem.modelData.split("")

          delegate: Text {
            required property string modelData
            required property int index
            x: index * root.cellWidth
            width: root.cellWidth
            height: root.cellHeight
            text: modelData
            color: root.cellColor(modelData, rowItem.rowIndex)
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }
}
