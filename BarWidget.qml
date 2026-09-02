import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Mouse Odometer — a live graph of how far your hand is pushing the mouse,
// with the number beside it.
//
//     󰍽 ▁▂▃▅▇▃▁ 412m ↓12%
//
// The measuring is done by `bin/omarchy-mouse-odometer`, a daemon that reads
// raw evdev counts and writes a JSON tally; this widget only reads that file.
// Left click opens the history, right click cycles the number, middle click
// cycles the graph between the last hours, the last days, and off.
BarWidget {
  id: root
  moduleName: "odin.mouse-odometer"

  // ---- settings (shell.json layout entry, `omarchy bar set`)
  readonly property string units: String(setting("units", "metric")) === "imperial" ? "imperial" : "metric"
  readonly property string labelMode: {
    var mode = String(setting("show", "today"))
    return ["today", "week", "total"].indexOf(mode) >= 0 ? mode : "today"
  }
  readonly property string graphMode: {
    var mode = String(setting("graph", "hours"))
    return ["hours", "days", "off"].indexOf(mode) >= 0 ? mode : "hours"
  }
  readonly property int graphPoints: Math.max(4, Math.min(48, Number(setting("graphPoints", graphMode === "days" ? 14 : 16)) || 16))
  readonly property real graphBarWidth: Math.max(1, Math.min(6, Number(setting("graphBarWidth", 2)) || 2))
  readonly property bool showDelta: setting("showDelta", true) !== false
  readonly property bool showNumber: setting("showNumber", true) !== false
  readonly property real goalMeters: Math.max(0, Number(setting("goalMeters", 0)) || 0)
  readonly property string icon: String(setting("icon", String.fromCodePoint(0xF037D)))
  // Installing a user service on first load is convenient but opinionated;
  // set autostart false and the panel's "Start tracker" button is the only
  // thing that will ever touch systemd.
  readonly property bool autostart: setting("autostart", true) !== false

  // ---- state, straight off the daemon's file
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/omarchy-mouse-odometer/state.json"

  property var stats: null
  property date now: new Date()

  readonly property var recent: Format.recentDays(stats, Math.max(14, graphMode === "days" ? graphPoints : 0), now)
  readonly property var today: recent.length > 0 ? recent[recent.length - 1] : null
  readonly property real todayMeters: today ? today.meters : 0
  readonly property real weekMeters: Format.sumMeters(recent.slice(-7))
  readonly property real totalMeters: stats && stats.total ? (Number(stats.total.meters) || 0) : 0
  // Yesterday back to day 7 — a baseline today can be judged against.
  readonly property real baselineMeters: Format.averageMeters(recent.slice(-8, -1), false)

  // ---- the graph
  readonly property var hourSeries: Format.hourlySeries(stats, graphPoints, now)
  readonly property var graphSeries: graphMode === "days" ? recent.slice(-graphPoints) : hourSeries
  readonly property var graphValues: graphMode === "off" ? [] : Format.seriesValues(graphSeries)

  // The daemon rewrites its file every 15s while you move. Nothing for a few
  // minutes means it is not running, and a frozen number is worse than a hint.
  readonly property bool stale: {
    if (!stats || !stats.updated) return true
    var updated = Date.parse(stats.updated)
    return isNaN(updated) ? true : (now.getTime() - updated) > 300000
  }
  readonly property bool overGoal: goalMeters > 0 && todayMeters > goalMeters
  readonly property bool improving: baselineMeters > 0 && todayMeters < baselineMeters

  readonly property real labelMeters: labelMode === "total" ? totalMeters
    : (labelMode === "week" ? weekMeters : todayMeters)
  readonly property string numberText: Format.compactDistance(labelMeters, units)
  readonly property string deltaText: labelMode === "today" ? Format.deltaArrow(todayMeters, baselineMeters) : ""

  readonly property string tooltip: {
    if (!stats) return "Mouse odometer: no data yet"
    if (stale) return "Mouse odometer: tracker not running"
    var parts = [Format.distance(todayMeters, units) + " today"]
    var delta = Format.deltaText(todayMeters, baselineMeters)
    if (delta !== "") parts.push(delta + " vs the last 7 days")
    parts.push(graphMode === "days" ? "graph: last " + graphPoints + " days"
                                    : "graph: last " + graphPoints + " hours")
    if (goalMeters > 0) parts.push("goal " + Format.distance(goalMeters, units))
    return parts.join(" · ")
  }

  // ---- actions
  function reload() {
    stateFile.reload()
    now = new Date()
  }

  function cycleLabel() {
    var ring = ["today", "week", "total"]
    persist({ show: ring[(ring.indexOf(labelMode) + 1) % ring.length] })
  }

  function cycleGraph() {
    var ring = ["hours", "days", "off"]
    persist({ graph: ring[(ring.indexOf(graphMode) + 1) % ring.length] })
  }

  function cycleUnits() {
    persist({ units: units === "metric" ? "imperial" : "metric" })
  }

  // Settings live in this widget's shell.json layout entry, so a choice made
  // by clicking is the choice that survives a restart.
  function persist(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // The tracker is a user service, so it outlives shell restarts and keeps
  // counting while the widget is not even loaded. Bootstrapping it from here
  // means installing the plugin is the only step a new user has to take.
  function ensureTracker() {
    if (!bar || bootstrapped || !autostart) return
    bootstrapped = true
    bar.run(bar.shellQuote(Qt.resolvedUrl("bin/omarchy-mouse-odometer").toString().replace("file://", ""))
            + " bootstrap >/dev/null 2>&1")
  }

  property bool bootstrapped: false

  // ---- panel plumbing (shape contract for shell summon/hide/toggle routing)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: root.stats = Format.parseState(text())
    onLoaded: root.stats = Format.parseState(text())
    onLoadFailed: {
      root.stats = null
      root.ensureTracker()
    }
  }

  // The file is replaced by rename on every write, which an inotify watch on
  // the old inode can miss; a slow poll makes the widget self-healing, and
  // also rolls the hour and the day over.
  Timer {
    interval: root.opened ? 5000 : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.reload()
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

  IpcHandler {
    target: "odin.mouse-odometer"

    function refresh(): void { root.broadcast("reload") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function cycleUnits(): void { root.cycleUnits() }
    function cycleGraph(): void { root.cycleGraph() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    labelVisible: root.vertical
    hasVisualContent: true
    active: root.overGoal
    dimmed: root.stale
    tooltipText: root.tooltip
    fixedWidth: root.vertical ? -1 : Math.ceil(content.implicitWidth + button.scaledHorizontalMargin * 2)

    onPressed: function(pressedButton) {
      if (pressedButton === Qt.RightButton) root.cycleLabel()
      else if (pressedButton === Qt.MiddleButton) root.cycleGraph()
      else root.togglePanel()
    }

    // Horizontal bars get the whole readout; a 28px vertical bar gets the
    // icon alone, with everything else in the tooltip and the panel.
    Row {
      id: content
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }

      Sparkline {
        id: spark
        visible: root.graphMode !== "off" && root.graphValues.length > 0
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? implicitWidth : 0
        height: Math.round(root.barSize * 0.46)
        values: root.graphValues
        barWidth: root.graphBarWidth
        barColor: button.foreground
        highlightColor: root.overGoal ? button.activeColor : Color.accent
      }

      Text {
        textFormat: Text.PlainText
        visible: root.showNumber
        anchors.verticalCenter: parent.verticalCenter
        text: root.numberText
        color: button.active ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Text {
        textFormat: Text.PlainText
        visible: root.showDelta && root.deltaText !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.deltaText
        color: root.improving ? Color.accent : Qt.darker(button.foreground, 1.4)
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
      }
    }
  }
}
