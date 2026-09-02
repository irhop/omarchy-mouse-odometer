import QtQuick
import qs.Commons

// A column chart small enough to live in a 26px bar, and the same component
// the panel uses at full size. Plain Rectangles rather than a Canvas: they
// stay crisp at 2px wide, repaint themselves when the theme changes, and cost
// nothing to animate.
Item {
  id: root

  property var values: []
  property color barColor: Color.foreground
  property color highlightColor: Color.accent
  // Which column is "now" — highlighted so the eye lands on the live end.
  property int highlightIndex: values.length - 1
  property int hoverIndex: -1
  property real barWidth: 2
  property real gap: 1
  property real minHeight: 1
  property real baseOpacity: 0.35
  property real hoverOpacity: 0.8
  // A shared ceiling lets two sparklines be read against each other; left at
  // 0 each one scales to its own peak.
  property real peak: 0
  property bool interactive: false

  signal columnEntered(int index)
  signal columnExited(int index)

  readonly property real effectivePeak: {
    if (peak > 0) return peak
    var most = 0
    for (var i = 0; i < values.length; i++) most = Math.max(most, Number(values[i]) || 0)
    return most > 0 ? most : 1
  }

  implicitWidth: values.length > 0 ? values.length * (barWidth + gap) - gap : 0
  implicitHeight: 12

  Row {
    anchors.fill: parent
    spacing: root.gap

    Repeater {
      model: root.values

      Item {
        id: cell
        required property var modelData
        required property int index

        width: root.barWidth
        height: root.height

        Rectangle {
          width: parent.width
          height: Math.max(root.minHeight, (Number(cell.modelData) || 0) / root.effectivePeak * root.height)
          y: parent.height - height
          radius: width >= 3 ? Math.min(2, width / 2) : 0
          color: cell.index === root.highlightIndex ? root.highlightColor : root.barColor
          opacity: cell.index === root.highlightIndex
            ? 1
            : (cell.index === root.hoverIndex ? root.hoverOpacity : root.baseOpacity)

          Behavior on height {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.interactive
          hoverEnabled: root.interactive
          acceptedButtons: Qt.NoButton
          onEntered: root.columnEntered(cell.index)
          onExited: root.columnExited(cell.index)
        }
      }
    }
  }
}
