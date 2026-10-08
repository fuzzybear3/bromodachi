import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui

// The per-monitor half of steveng.bromodachi: a thin view over the plugin's
// service instance (Service.qml, mounted once by the shell regardless of
// monitor count) reached through bar.shell.serviceFor. Polling, the clock and
// the commands live in the service; this file only renders and forwards
// input, so N monitors mean N faces of the same buddy.
//
// The bar face: あ and today's answer count, plus a dot while a question is
// up. The dot turns urgent once the question has waited ten minutes. Paused
// shows the time left instead; a daemon that is not running dims the glyph.
// Clicking opens an anchored panel (the gitea tracker's dialect): today, the
// queue, the newest lesson, a week of answers, then the quick commands.
// (qs.Ui is imported under a namespace because this file is itself named
// BarWidget.qml — the japanquake plugin's convention.)
Ui.Panel {
  id: root
  moduleName: "steveng.bromodachi"
  ipcTarget: "steveng.bromodachi"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("steveng.bromodachi") : null

  // Null-safe proxies: the service mounts at shell startup, but bindings
  // evaluate before it lands, and a broken mount must degrade to a dimmed
  // glyph rather than a wall of TypeErrors.
  readonly property bool reachable: svc ? svc.reachable : false
  readonly property var snap: svc ? svc.snap : null
  readonly property var stats: svc ? svc.stats : null
  readonly property bool questionUp: svc ? svc.questionUp : false
  readonly property bool overdue: svc ? svc.overdue : false
  readonly property bool paused: svc ? svc.paused : false
  readonly property bool busy: svc ? svc.busy : false
  readonly property string notice: svc ? svc.notice : ""
  // Commands need a daemon to talk to.
  readonly property bool ready: reachable && snap !== null && !busy

  // The gitea panel's color recipe, so side-by-side panels match.
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color trackColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The dot sits in the button's own right margin and adds this much width.
  readonly property int dotSize: Style.space(6)
  readonly property int dotRoom: Style.space(8)

  visible: true
  implicitWidth: button.implicitWidth + (dot.visible ? dotRoom : 0)
  implicitHeight: button.implicitHeight

  // Forwarders to the service. The ones that put a question on screen close
  // the panel, so the keyboard is free for the answer box.
  function askNow() { if (svc && svc.askNow()) close() }
  function newWord() { if (svc && svc.newWord()) close() }
  function skip() { if (svc) svc.skip() }
  function pause(minutes) { if (svc && svc.pause(minutes)) close() }
  function resume() { if (svc) svc.resume() }

  onOpenedChanged: {
    if (!svc) return
    if (opened) svc.panelOpened()
    else svc.panelClosed()
  }

  // A widget destroyed with its panel open (monitor unplugged) must not
  // strand the service's open-panel count.
  Component.onDestruction: if (opened && svc) svc.panelClosed()

  // The dot's strip of the face is not the button's: clicks there count too.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
  }

  Ui.WidgetButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: implicitWidth
    bar: root.bar
    dimmed: !root.reachable
    text: root.svc ? root.svc.faceText() : "あ"
    tooltipText: {
      if (!root.svc) return "Bromodachi — service not mounted"
      if (!root.reachable) return "Bromodachi — the daemon is not running"
      let lines = [root.svc.heroMeta()]
      if (root.stats) lines.push(root.stats.today.answers + " answered today")
      lines.push("Click for stats and commands")
      return lines.join("\n")
    }
    onPressed: root.toggle()
  }

  Rectangle {
    id: dot
    visible: root.reachable && root.questionUp && !root.paused
    width: root.dotSize
    height: width
    radius: width / 2
    color: root.overdue ? root.urgent : root.foreground
    x: button.width - Style.space(4)
    anchors.verticalCenter: parent.verticalCenter

    Behavior on color { ColorAnimation { duration: 160 } }
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      // The panel holds the keyboard while it is open, so a key meant for
      // another window lands here: keys only close and refresh, and every
      // command takes a click.
      onTextKey: function(text) {
        if ((text === "r" || text === "R") && root.svc) root.svc.refresh()
      }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(9)

        Ui.PanelHero {
          width: parent.width
          title: "Bromodachi"
          meta: root.svc ? root.svc.heroMeta() : "Service not mounted"
          foreground: root.foreground
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: "あ"
              color: root.overdue ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          trailingControl: Component {
            Ui.PanelActionButton {
              iconText: ""
              tooltipText: "Refresh (R)"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              onClicked: if (root.svc) root.svc.refresh()
            }
          }
        }

        Ui.PanelSeparator { foreground: root.foreground }

        // ---------- Headline tiles: today, and the queue ----------
        Row {
          id: tiles
          width: parent.width
          spacing: Style.space(8)

          readonly property real tileWidth: (width - spacing * 3) / 4

          StatTile {
            width: tiles.tileWidth
            title: "TODAY"
            value: root.stats ? String(root.stats.today.answers) : "—"
            detail: !root.stats ? ""
              : root.stats.today.answers === 0 ? "none yet"
              : root.svc.rightPercent() + "% right"
            meter: root.svc ? root.svc.rightPercent() : -1
          }

          StatTile {
            width: tiles.tileWidth
            title: "NEW"
            value: root.stats ? String(root.stats.today.new) : "—"
            detail: root.stats ? "started" : ""
          }

          StatTile {
            width: tiles.tileWidth
            title: "LEARNING"
            value: root.stats ? root.stats.queue.learning + "/" + root.stats.queue.slots : "—"
            detail: !root.stats ? ""
              : root.stats.queue.due > 0 ? root.stats.queue.due + " due now" : "none due"
            meter: root.stats
              ? Math.min(100, root.stats.queue.learning * 100 / root.stats.queue.slots)
              : -1
          }

          StatTile {
            width: tiles.tileWidth
            title: "LATE"
            value: root.stats ? String(root.stats.queue.late) : "—"
            detail: !root.stats ? ""
              : root.stats.queue.late > 0 ? "reviews" : "none"
          }
        }

        Ui.PanelSeparator { foreground: root.foreground }

        // ---------- The newest lesson: started and graduated ----------
        Column {
          width: parent.width
          spacing: Style.space(5)
          visible: root.stats !== null && root.stats.queue.lesson_total > 0

          SectionHeading {
            title: "LESSON " + (root.svc ? root.svc.lessonLabel() : "")
            value: root.stats
              ? root.stats.queue.lesson_started + " of " + root.stats.queue.lesson_total + " started"
              : ""
          }

          // One track, two fills: started over it, graduated over that.
          Rectangle {
            id: lessonBar
            width: parent.width
            height: Style.space(5)
            radius: height / 2
            color: root.trackColor

            readonly property real total: root.stats ? Math.max(1, root.stats.queue.lesson_total) : 1

            Rectangle {
              width: parent.width * (root.stats ? root.stats.queue.lesson_started / lessonBar.total : 0)
              height: parent.height
              radius: parent.radius
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
              Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            Rectangle {
              width: parent.width * (root.stats ? root.stats.queue.lesson_graduated / lessonBar.total : 0)
              height: parent.height
              radius: parent.radius
              color: root.accent
              Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
          }

          Text {
            width: parent.width
            text: root.stats
              ? root.stats.queue.lesson_graduated + " graduated · "
                + (root.stats.queue.lesson_total - root.stats.queue.lesson_started) + " not started"
              : ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        // ---------- A week of answers ----------
        Column {
          id: weekSection
          width: parent.width
          spacing: Style.space(5)
          visible: root.stats !== null

          readonly property var days: root.svc && root.stats ? root.svc.week() : []
          readonly property int peak: {
            var m = 1
            for (var i = 0; i < days.length; i++) m = Math.max(m, days[i].count)
            return m
          }
          readonly property int total: {
            var n = 0
            for (var i = 0; i < days.length; i++) n += days[i].count
            return n
          }

          SectionHeading {
            title: "LAST 7 DAYS"
            value: weekSection.total + " answers"
          }

          Row {
            id: chart
            width: parent.width
            spacing: Style.space(6)

            readonly property int barHeight: Style.space(34)

            Repeater {
              model: weekSection.days

              Column {
                id: day
                required property var modelData
                width: (chart.width - chart.spacing * 6) / 7
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: String(day.modelData.count)
                  color: day.modelData.today ? root.foreground : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                }

                Item {
                  width: parent.width
                  height: chart.barHeight

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    // an empty day keeps a sliver, so the row reads as seven days
                    height: Math.max(Style.space(2), chart.barHeight * day.modelData.count / weekSection.peak)
                    radius: Math.min(Style.cornerRadius, Style.space(2))
                    color: day.modelData.count === 0 ? root.trackColor
                      : day.modelData.today ? root.accent
                      : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
                  }
                }

                Text {
                  width: parent.width
                  text: day.modelData.letter
                  color: day.modelData.today ? root.foreground : root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: day.modelData.today
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }
          }
        }

        Ui.PanelSeparator { foreground: root.foreground; visible: root.stats !== null }

        // ---------- Quick commands ----------
        Column {
          width: parent.width
          spacing: Style.space(5)

          SectionHeading { title: "QUESTION" }

          Row {
            width: parent.width
            spacing: Style.space(8)

            CommandButton {
              text: root.questionUp ? "Go to it" : "Ask now"
              tooltipText: root.questionUp ? "Jump into the answer box" : "Ask the next question now"
              onClicked: root.askNow()
            }

            CommandButton {
              text: "New word"
              tooltipText: "Ask the next unseen card, learning slot free or not"
              onClicked: root.newWord()
            }

            CommandButton {
              text: "Skip"
              tooltipText: "Take this question down ungraded"
              enabled: root.ready && root.questionUp
              onClicked: root.skip()
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(5)

          SectionHeading {
            title: "PAUSE"
            value: root.paused && root.svc ? root.svc.dur(root.svc.pausedMs) + " left" : ""
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.paused

            CommandButton {
              text: "30 min"
              tooltipText: "No questions for 30 minutes"
              onClicked: root.pause(30)
            }

            CommandButton {
              text: "1 hour"
              tooltipText: "No questions for an hour"
              onClicked: root.pause(60)
            }

            CommandButton {
              text: "Tomorrow"
              tooltipText: "No questions until 5 a.m."
              onClicked: if (root.svc) root.pause(root.svc.minutesToMorning())
            }
          }

          CommandButton {
            width: parent.width
            visible: root.paused
            text: "Resume"
            tooltipText: "Start asking again"
            onClicked: root.resume()
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(5)

          SectionHeading { title: "SETTINGS" }

          Item {
            width: parent.width
            implicitHeight: Math.max(everyLabel.implicitHeight, everyGroup.implicitHeight)

            Text {
              id: everyLabel
              text: "Minutes between questions"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              anchors.left: parent.left
              anchors.right: everyGroup.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }

            Ui.ButtonGroup {
              id: everyGroup
              options: ["5", "8", "15"]
              // 8.0 from the daemon prints as "8"; any other interval set by
              // hand in config.json simply selects none of the three
              value: root.snap ? String(root.snap.interval_minutes) : ""
              foreground: root.foreground
              background: "transparent"
              accent: root.accent
              fontFamily: root.fontFamily
              focusable: false
              enabled: root.ready
              opacity: enabled ? 1 : 0.45
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onChanged: function(value) {
                if (root.svc && value !== everyGroup.value) root.svc.setEvery(Number(value))
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(narutoLabel.implicitHeight, narutoSwitch.implicitHeight) + Style.space(6)

            Text {
              id: narutoLabel
              text: "Naruto, the Gitea buddy"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              anchors.left: parent.left
              anchors.right: narutoSwitch.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }

            Ui.ToggleSwitch {
              id: narutoSwitch
              checked: root.snap !== null && root.snap.naruto === true
              busy: !root.ready
              foreground: root.foreground
              accent: root.accent
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onToggled: if (root.svc) root.svc.setNaruto(!checked)
            }
          }
        }

        Text {
          width: parent.width
          visible: root.notice !== ""
          text: root.notice
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }

  // ---------- Local components, in the gitea panel's dialect ----------

  component SectionHeading: Item {
    property string title: ""
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(headingText.implicitHeight, valueText.implicitHeight) + Style.space(4)

    Ui.PanelSectionHeader {
      id: headingText
      text: title
      textFormat: Text.PlainText
      foreground: root.foreground
      fontFamily: root.fontFamily
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: valueText.visible ? valueText.left : parent.right
      anchors.rightMargin: valueText.visible ? Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueText
      text: value
      visible: text !== ""
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      width: Math.min(implicitWidth, parent.width * 0.62)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
    }
  }

  component Meter: Rectangle {
    id: meterItem
    property real value: -1
    property color fillColor: root.accent

    visible: value >= 0
    height: Style.space(3)
    radius: height / 2
    color: root.trackColor

    Rectangle {
      width: meterItem.width * Math.max(0, Math.min(1, meterItem.value / 100))
      height: meterItem.height
      radius: meterItem.radius
      color: meterItem.fillColor

      Behavior on width {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
    }
  }

  component StatTile: Ui.BorderSurface {
    id: tile
    property string title: ""
    property string value: "—"
    property string detail: ""
    property real meter: -1
    property color meterColor: root.accent

    height: Style.space(78)
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(9)
      spacing: Style.space(2)

      Text {
        text: tile.title
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Text {
        text: tile.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        text: tile.detail
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Meter {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(9)
      value: tile.meter
      fillColor: tile.meterColor
    }
  }

  // A command: one of three across the panel, waiting while another runs.
  component CommandButton: Ui.Button {
    width: parent ? (parent.width - Style.space(8) * 2) / 3 : implicitWidth
    bordered: true
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    enabled: root.ready
    opacity: enabled ? 1 : 0.45
  }
}
