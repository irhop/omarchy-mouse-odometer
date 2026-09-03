import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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

  // This panel is the only place in the plugin that can install anything, and
  // what it installs is a persistent user service. So the CLI is launched as
  // an argv vector rather than a shell string, and in an environment built
  // from scratch rather than whatever the compositor was started with: a
  // service installer has no business inheriting an ambient PATH. The daemon
  // rebuilds the same minimal environment again on its own side.
  readonly property string trackerBin:
    Qt.resolvedUrl("bin/omarchy-mouse-odometer").toString().replace("file://", "")

  function trackerEnvironment() {
    var env = { "PATH": "/usr/local/bin:/usr/bin:/bin" }
    // XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS are how `systemctl --user`
    // reaches the session manager; the rest keep the child's idea of where
    // config and state live identical to this widget's.
    var keep = ["HOME", "USER", "LOGNAME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS",
                "XDG_CONFIG_HOME", "XDG_STATE_HOME", "WAYLAND_DISPLAY"]
    for (var i = 0; i < keep.length; i++) {
      var value = Quickshell.env(keep[i])
      if (value) env[keep[i]] = value
    }
    return env
  }

  function splitLines(text) {
    var lines = []
    var raw = String(text || "").split("\n")
    for (var i = 0; i < raw.length; i++) if (raw[i].trim() !== "") lines.push(raw[i].trim())
    return lines
  }

  // ---- setup: idle -> probing -> review -> running -> done | failed
  property string setupStage: "idle"
  property var setupScope: []
  property string setupReport: ""
  property string probeOutput: ""
  property string runOutput: ""
  property string runError: ""

  // Set the moment we stop caring about a child, so its late `exited` cannot
  // reach back and rewrite a card the user has already moved on from.
  property bool setupAbandoned: false

  // One deadline covers both steps. A child that never returns must not leave
  // this card reading "Setting up…" for the rest of the session.
  readonly property int setupTimeout: 30000

  // The collectors buffer whatever they are handed. The child is this
  // plugin's own CLI, which prints a few lines and is killed at the deadline,
  // but keep only as much as the card could ever render.
  readonly property int outputLimit: 16384

  function clamp(text) {
    var value = String(text || "")
    return value.length > outputLimit ? value.slice(0, outputLimit) + "\n…(truncated)" : value
  }

  Timer {
    id: setupWatchdog
    interval: root.setupTimeout
    repeat: false
    onTriggered: root.abandonSetup("did not finish within "
                                   + Math.round(root.setupTimeout / 1000) + " seconds")
  }

  // Ask both children to stop and stop listening to them. Safe to call when
  // nothing is running, which is what makes it usable from teardown.
  function stopSetup() {
    setupWatchdog.stop()
    setupAbandoned = true
    if (scopeProbe.running) { scopeProbe.signal(15); scopeProbe.running = false }
    if (setupProcess.running) { setupProcess.signal(15); setupProcess.running = false }
  }

  function abandonSetup(why) {
    stopSetup()
    setupStage = "failed"
    setupReport = "Setup " + why + " and was stopped. Nothing further was changed."
  }

  function reviewSetup() {
    if (setupStage === "probing" || setupStage === "running") return
    setupScope = []
    setupReport = ""
    probeOutput = ""
    setupAbandoned = false
    setupStage = "probing"
    setupWatchdog.restart()
    scopeProbe.running = true
  }

  function confirmSetup() {
    if (setupStage !== "review") return
    runOutput = ""
    runError = ""
    setupAbandoned = false
    setupStage = "running"
    setupWatchdog.restart()
    setupProcess.running = true
  }

  // A tracker that starts writing again is the card's job done; reset so that
  // a later stall offers setup rather than last week's success message.
  onStaleChanged: if (!stale) { stopSetup(); setupStage = "idle"; setupReport = ""; setupScope = [] }

  // A panel that goes away takes its children with it.
  Component.onDestruction: stopSetup()

  // Asking the installer what it would do, rather than describing it here,
  // is what keeps the consent screen and the installer from drifting apart.
  Process {
    id: scopeProbe
    clearEnvironment: true
    environment: root.trackerEnvironment()
    command: [root.trackerBin, "bootstrap", "--dry-run"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.probeOutput = root.clamp(text) }
    onExited: function(exitCode) {
      setupWatchdog.stop()
      if (root.setupAbandoned) return
      var lines = root.splitLines(root.probeOutput)
      root.probeOutput = ""
      if (exitCode !== 0 || lines.length === 0) {
        root.setupStage = "failed"
        root.setupReport = "Could not read the setup plan from the tracker CLI (exit "
                           + exitCode + "). Nothing has been changed."
        return
      }
      root.setupScope = lines
      root.setupStage = "review"
    }
  }

  // The only call in the plugin that changes service state, and its output is
  // reported rather than discarded: an installer whose result nobody reads is
  // indistinguishable from one that silently did nothing.
  Process {
    id: setupProcess
    clearEnvironment: true
    environment: root.trackerEnvironment()
    command: [root.trackerBin, "bootstrap"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.runOutput = root.clamp(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.runError = root.clamp(text) }
    onExited: function(exitCode) {
      setupWatchdog.stop()
      if (root.setupAbandoned) return
      var report = root.clamp((root.runOutput + "\n" + root.runError).trim())
      root.runOutput = ""
      root.runError = ""
      if (exitCode === 0) {
        root.setupStage = "done"
        root.setupReport = report !== "" ? report : "Tracker installed and running."
      } else {
        root.setupStage = "failed"
        root.setupReport = (report !== "" ? report + "\n" : "")
                           + "Setup failed (exit " + exitCode + ")."
      }
      if (root.hostWidget) Qt.callLater(root.hostWidget.reload)
    }
  }
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

  readonly property bool gamify: hostWidget ? hostWidget.gamify : false
  readonly property bool introSeen: hostWidget ? hostWidget.introSeen : true
  readonly property real todayScore: hostWidget ? hostWidget.todayScore : 0
  readonly property real baselineScore: hostWidget ? hostWidget.baselineScore : 0
  readonly property int streakDays: hostWidget ? hostWidget.streakDays : 0
  readonly property var best: hostWidget ? hostWidget.best : null
  readonly property var weekly: Format.weekOverWeek(days)
  readonly property string scoreDelta: Format.deltaArrow(todayScore, baselineScore)

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
    if (panelFlick) panelFlick.contentY = 0
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

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentY + dy * Style.space(56),
                                                     Math.max(0, panelFlick.contentHeight - panelFlick.height)))
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.hostWidget) root.hostWidget.reload()
      onTextKey: function(key) {
        if (key === "u" || key === "U") { if (root.hostWidget) root.hostWidget.cycleUnits() }
        else if (key === "r" || key === "R") { if (root.hostWidget) root.hostWidget.reload() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        // ---------- Setup, which only ever happens on purpose ----------
        //
        // Enabling a plugin must not install a service. Nothing in this
        // plugin touches systemd, writes a symlink or enables a unit until
        // someone has read the list below and pressed the button under it.
        Column {
          id: setupCard
          width: parent.width
          spacing: Style.space(8)
          visible: root.stale

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasData
              ? "The tracker has not written anything for a while — the numbers below are frozen."
              : "Nothing is being measured yet."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: !root.hasData
            text: "This widget only reads a file. The measuring is done by a small "
                  + "user service, which is not installed until you ask for it here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            visible: root.setupStage === "idle"
            text: root.hasData ? "Start tracker…" : "Set up tracker…"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.reviewSetup()
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.setupStage === "probing"
            text: "Working out what it would change…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---- what it would do, asked of the installer itself
          Column {
            id: scopeList
            width: parent.width
            spacing: Style.space(6)
            visible: root.setupStage === "review"

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Setting up will:"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.setupScope

              Text {
                width: scopeList.width
                textFormat: Text.PlainText
                text: "•  " + modelData
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "No root, no sudo, no network. Reading the mouse also needs your "
                    + "account to be in the 'input' group — that is yours to grant, "
                    + "and nothing here changes it for you."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              spacing: Style.space(8)

              Button {
                text: "Cancel"
                bordered: true
                foreground: root.dim
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.setupStage = "idle"
              }

              Button {
                text: "Install and start"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.confirmSetup()
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.setupStage === "running"
            text: "Setting up…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---- and what actually happened
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.setupStage === "done" || root.setupStage === "failed"

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.setupReport
              color: root.setupStage === "failed" ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              visible: root.setupStage === "failed"
              text: "Try again"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.reviewSetup()
            }
          }
        }

        // ---------- First run: what this is actually for ----------
        Column {
          id: intro
          width: parent.width
          spacing: Style.space(8)
          visible: !root.introSeen

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "The number is supposed to go down"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Omarchy is built to be driven from the keyboard, and this widget "
                + "exists to show you how much you still reach for the mouse. Give it "
                + "a week to learn what a normal day looks like for you, then aim under it."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "These are estimates, not measurements — see the note at the bottom."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            spacing: Style.spacing.md

            Button {
              text: "Track my progress"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: if (root.hostWidget) root.hostWidget.enableGamify()
            }

            Button {
              text: "Just the numbers"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: if (root.hostWidget) root.hostWidget.dismissIntro()
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
          visible: intro.visible
        }

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

        // ---------- Progress ----------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.gamify

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "Progress"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            visible: root.baselineScore <= 0
            text: "Still learning your normal. A couple of full days at the machine "
                + "and there will be a baseline to beat."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Today against your own median, which is the only comparison that
          // means anything — nobody else's desk is your desk.
          Item {
            width: parent.width
            height: Style.space(26)
            visible: root.baselineScore > 0

            Text {
              id: scoreValue
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: Format.distance(root.todayScore, root.units) + " / desk hour"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.scoreDelta === "" ? "" : root.scoreDelta + " vs normal"
              color: root.todayScore < root.baselineScore ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          Rectangle {
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            visible: root.baselineScore > 0
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

            // The baseline is the full bar; today fills it and turns urgent
            // once it runs past.
            Rectangle {
              width: Math.min(1, root.baselineScore > 0 ? root.todayScore / root.baselineScore : 0) * parent.width
              height: parent.height
              radius: parent.radius
              color: root.todayScore > root.baselineScore
                ? (root.bar ? root.bar.urgent : Color.urgent)
                : root.accent
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.baselineScore > 0

            Repeater {
              model: [
                { label: "Your normal", value: Format.distance(root.baselineScore, root.units) + " / desk hour" },
                { label: "Streak under it", value: root.streakDays > 0
                    ? root.streakDays + (root.streakDays === 1 ? " day" : " days") : "not yet" },
                { label: "Best day", value: root.best
                    ? Format.distance(root.best.score, root.units) + " on " + Format.shortDate(root.best.day.date)
                    : "—" },
                { label: "This week vs last", value: root.weekly
                    ? (root.weekly.delta <= 0 ? "↓" : "↑") + Math.abs(Math.round(root.weekly.delta)) + "%"
                    : "needs two weeks" }
              ]

              Row {
                required property var modelData
                width: parent.width

                Text {
                  id: progressLabel
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Item {
                  width: Math.max(Style.space(8), parent.width - progressLabel.implicitWidth - progressValue.implicitWidth)
                  height: 1
                }

                Text {
                  id: progressValue
                  textFormat: Text.PlainText
                  text: modelData.value
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
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
            { label: "Daily average", value: root.fortnightAverage > 0
                ? Format.distance(root.fortnightAverage, root.units) : "needs a few days" },
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

        // A standing caveat, not just a first-run one: these are estimates and
        // the panel should never let anyone forget it.
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Estimated from sensor counts, not measured. Calibration, surface and "
              + "hand speed all move the number — good for comparing your own days, "
              + "not for quoting to three decimals."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
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

      }
      }
    }
  }
}
