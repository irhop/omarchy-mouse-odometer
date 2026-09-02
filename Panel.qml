import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

// The odometer's history popup: today up top, then a fortnight of daily bars
// you can hover, then the totals. Built to answer one question — "am I moving
// the mouse less than I was?" — so every number is framed against a baseline.
Panel {
  id: root
  moduleName: "io.github.irhop.mouse-odometer"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string units: hostWidget ? hostWidget.units : "metric"
  readonly property var days: hostWidget ? hostWidget.recent.slice(-14) : []
  readonly property var hours: Format.todayHourly(hostWidget ? hostWidget.stats : null,
                                                  hostWidget ? hostWidget.now : new Date())
  readonly property var hourValues: Format.seriesValues(hours)
  property int hourHover: -1
  readonly property int currentHour: hostWidget ? hostWidget.now.getHours() : new Date().getHours()
  readonly property var today: hostWidget ? hostWidget.today : null
  readonly property real todayMeters: hostWidget ? hostWidget.todayMeters : 0
  readonly property real weekMeters: hostWidget ? hostWidget.weekMeters : 0
  readonly property real totalMeters: hostWidget ? hostWidget.totalMeters : 0
  readonly property real baselineMeters: hostWidget ? hostWidget.baselineMeters : 0
  readonly property real goalMeters: hostWidget ? hostWidget.goalMeters : 0
  readonly property bool stale: hostWidget ? hostWidget.stale : true
  readonly property bool hasData: !!(hostWidget && hostWidget.stats)

  readonly property real fortnightAverage: Format.averageMeters(days, true)
  readonly property string deltaText: Format.deltaText(todayMeters, baselineMeters)
  readonly property bool improving: baselineMeters > 0 && todayMeters < baselineMeters
  readonly property string since: hostWidget && hostWidget.stats ? String(hostWidget.stats.since || "") : ""

  // Which chart column the pointer is over; -1 is "none", and the caption
  // falls back to today so the line under the chart is never empty.
  property int hoverIndex: -1
  readonly property var hoverDay: hoverIndex >= 0 && hoverIndex < days.length ? days[hoverIndex] : today

  function open() {
    if (hostWidget) hostWidget.reload()
    root.controller.show()
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function openFromHotkey() { root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: if (opened) {
    hoverIndex = -1
    hourHover = -1
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.hostWidget) root.hostWidget.reload()
      onTextKey: function(key) {
        if (key === "u" || key === "U") { if (root.hostWidget) root.hostWidget.cycleUnits() }
        else if (key === "r" || key === "R") { if (root.hostWidget) root.hostWidget.reload() }
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // ---------- Hero: what today cost you ----------
        PanelHero {
          width: parent.width
          title: Format.distance(root.todayMeters, root.units)
          meta: "today"
          detail: root.deltaText
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: String.fromCodePoint(0xF037D)
              color: root.improving ? root.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          visible: root.deltaText !== ""
          text: root.improving
            ? "Lighter than your 7-day average — keep it there."
            : "Heavier than your 7-day average."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ---------- Daily goal ----------
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.goalMeters > 0

          Row {
            width: parent.width

            Text {
              id: goalLabel
              textFormat: Text.PlainText
              text: "Daily goal " + Format.distance(root.goalMeters, root.units)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Item {
              width: Math.max(Style.space(8), parent.width - goalLabel.implicitWidth - goalPercent.implicitWidth)
              height: 1
            }

            Text {
              id: goalPercent
              textFormat: Text.PlainText
              text: root.goalMeters > 0 ? Math.round(root.todayMeters / root.goalMeters * 100) + "%" : ""
              color: root.todayMeters > root.goalMeters ? (root.bar ? root.bar.urgent : Color.urgent) : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            Rectangle {
              width: Math.min(1, root.goalMeters > 0 ? root.todayMeters / root.goalMeters : 0) * parent.width
              height: parent.height
              radius: parent.radius
              color: root.todayMeters > root.goalMeters ? (root.bar ? root.bar.urgent : Color.urgent) : root.accent
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: "Today, hour by hour"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Sparkline {
          id: hourChart
          width: parent.width
          height: Style.space(44)
          values: root.hourValues
          interactive: true
          gap: Style.space(2)
          barWidth: (width - gap * 23) / 24
          minHeight: Style.space(2)
          barColor: root.foreground
          highlightColor: root.accent
          highlightIndex: root.currentHour
          hoverIndex: root.hourHover
          onColumnEntered: function(index) { root.hourHover = index }
          onColumnExited: function(index) { if (root.hourHover === index) root.hourHover = -1 }
        }

        Row {
          width: parent.width

          Text {
            id: hourAxisStart
            textFormat: Text.PlainText
            text: "00:00"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item {
            width: Math.max(Style.space(8), parent.width - hourAxisStart.implicitWidth - hourAxisNow.implicitWidth)
            height: 1
          }

          Text {
            id: hourAxisNow
            textFormat: Text.PlainText
            text: {
              var slot = root.hourHover >= 0 ? root.hours[root.hourHover] : null
              if (slot) return slot.label + " · " + Format.distance(slot.meters, root.units)
              var current = root.hours[root.currentHour]
              return current ? "this hour · " + Format.distance(current.meters, root.units) : "23:00"
            }
            color: root.hourHover >= 0 ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { foreground: root.foreground }

        PanelSectionHeader {
          text: "Last 14 days"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // ---------- The fortnight ----------
        Item {
          id: chart
          width: parent.width
          height: Style.space(92)

          readonly property real gap: Style.space(3)
          readonly property int columns: root.days.length
          readonly property real cellWidth: columns > 0 ? (width - gap * (columns - 1)) / columns : 0
          readonly property real labelHeight: Style.space(14)
          readonly property real plotHeight: height - labelHeight - Style.space(4)
          readonly property real peak: {
            var most = 0
            for (var i = 0; i < root.days.length; i++) most = Math.max(most, root.days[i].meters)
            return Math.max(most, 1)
          }

          // The average sits behind the bars as the line you are trying to
          // stay under, rather than as another number to read.
          Rectangle {
            visible: root.fortnightAverage > 0
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
            y: chart.plotHeight - (root.fortnightAverage / chart.peak) * chart.plotHeight
          }

          Row {
            anchors.fill: parent
            spacing: chart.gap

            Repeater {
              model: root.days

              Item {
                id: cell
                required property var modelData
                required property int index

                width: chart.cellWidth
                height: chart.height

                Rectangle {
                  width: parent.width
                  height: Math.max(Style.space(2), (cell.modelData.meters / chart.peak) * chart.plotHeight)
                  y: chart.plotHeight - height
                  radius: Style.space(2)
                  color: cell.modelData.isToday
                    ? root.accent
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                              root.hoverIndex === cell.index ? 0.75 : 0.32)
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Format.weekdayLetter(cell.modelData.date)
                  color: cell.modelData.isToday ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: root.hoverIndex = cell.index
                  onExited: if (root.hoverIndex === cell.index) root.hoverIndex = -1
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.hoverDay
            ? Format.shortDate(root.hoverDay.date) + " · " + Format.distance(root.hoverDay.meters, root.units)
              + " · " + Format.count(root.hoverDay.clicks) + " clicks · " + Format.duration(root.hoverDay.activeSeconds) + " active"
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Totals ----------
        Column {
          id: rows
          width: parent.width
          spacing: Style.space(6)

          readonly property var entries: [
            { label: "This week", value: Format.distance(root.weekMeters, root.units) },
            { label: "Daily average", value: Format.distance(root.fortnightAverage, root.units) },
            { label: "Clicks today", value: Format.count(root.today ? root.today.clicks : 0) },
            { label: "Scrolled today", value: Format.count(root.today ? root.today.scrolls : 0) + " ticks" },
            { label: "Active mousing", value: Format.duration(root.today ? root.today.activeSeconds : 0) },
            { label: "Pace", value: Format.distance(Format.metersPerActiveHour(root.today), root.units) + " / active hour" },
            { label: "All time", value: Format.distance(root.totalMeters, root.units) }
          ]

          Repeater {
            model: rows.entries

            Row {
              required property var modelData
              width: rows.width

              Text {
                id: rowLabel
                textFormat: Text.PlainText
                text: modelData.label
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Item {
                width: Math.max(Style.space(8), parent.width - rowLabel.implicitWidth - rowValue.implicitWidth)
                height: 1
              }

              Text {
                id: rowValue
                textFormat: Text.PlainText
                text: modelData.value
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          visible: root.since !== "" && !root.stale
          text: "Tracking since " + root.since + " · press U for " + (root.units === "metric" ? "feet and miles" : "metres and kilometres")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------- The tracker is not running ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.stale

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasData
              ? "The tracker has not written anything for a while — the numbers above are frozen."
              : "No measurements yet. The tracker service is what reads the mouse."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            text: "Start tracker"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: {
              if (root.bar) root.bar.run("systemctl --user enable --now omarchy-mouse-odometer.service")
              if (root.hostWidget) Qt.callLater(root.hostWidget.reload)
            }
          }
        }
      }
    }
  }
}
