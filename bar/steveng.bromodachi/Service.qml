import QtQuick
import Quickshell
import Quickshell.Io

// The one-per-shell half of steveng.bromodachi (kind "service" — the gitea
// tracker's shape). The bar makes one BarWidget per monitor; they all bind to
// this single instance through bar.shell.serviceFor("steveng.bromodachi"), so
// every face shows the same numbers and the daemon is asked once per tick.
//
// This file owns the polling, the clock and the commands. It owns no numbers:
// what counts as due, learning or new is decided by the daemon (src/srs.rs),
// which also holds the Supabase key. Everything here goes through the
// `bromodachi` CLI and its control socket.
Item {
  id: service
  visible: false

  // Injected by shell.qml when the service is mounted.
  property var shell: null

  // The launcher the Hyprland bindings use; it execs the release binary.
  readonly property string cli: Quickshell.env("HOME") + "/lab/bromodachi/bromodachi"

  // The last good `stats` reply, and whether the daemon answered the last poll.
  property var snap: null
  property bool reachable: true

  // The local clock when `snap` landed, and a clock that moves between polls
  // (every poll, and every second while a panel is open) so countdowns and
  // the waiting time tick without asking the daemon again.
  property real snapMs: 0
  property real nowMs: Date.now()

  property int openPanels: 0
  // A command is in flight; the panel's buttons wait for it.
  property bool busy: false
  // The last command's complaint, shown in the panel until the next command.
  property string notice: ""
  property string lastCommand: ""

  readonly property var stats: snap && snap.stats ? snap.stats : null
  readonly property real sinceSnap: Math.max(0, nowMs - snapMs)
  // Up and not yet answered; a graded answer still on screen is not waiting.
  readonly property bool questionUp: snap !== null && snap.popped !== null && snap.answered !== true
  readonly property real waitingMs: questionUp ? snap.waiting_ms + sinceSnap : 0
  // Ten minutes unanswered: the face's dot turns urgent.
  readonly property bool overdue: waitingMs >= 600000
  readonly property real pausedMs: snap ? Math.max(0, snap.paused_ms - sinceSnap) : 0
  readonly property bool paused: pausedMs > 0

  Component.onCompleted: console.log("steveng.bromodachi: service mounted (single instance)")

  // ------------------------------------------------------------ lifecycle

  function panelOpened() {
    nowMs = Date.now()
    refresh()
    openPanels++
  }

  function panelClosed() {
    openPanels = Math.max(0, openPanels - 1)
  }

  function refresh() {
    if (!statsProc.running) statsProc.running = true
  }

  // ------------------------------------------------------------- commands

  // One at a time: false means a command is still in flight.
  function run(args) {
    if (busy) return false
    busy = true
    notice = ""
    lastCommand = args[0]
    cmdProc.command = [cli].concat(args)
    cmdProc.running = true
    return true
  }

  // Super+B from the bar: a new question, or the cursor into the one that is up.
  function askNow() { return run(["summon"]) }
  // The next unseen card of the newest lesson, learning slot free or not.
  function newWord() { return run(["ask", "new"]) }
  function skip() { return run(["skip"]) }
  function pause(minutes) { return run(["pause", String(minutes)]) }
  function resume() { return run(["resume"]) }
  function setEvery(minutes) { return run(["set", "interval", String(minutes)]) }
  function setNaruto(on) { return run(["set", "naruto", on ? "on" : "off"]) }

  // Minutes from now to the next 05:00: "until tomorrow", also at 1 a.m.
  function minutesToMorning() {
    var now = new Date()
    var at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 5, 0, 0)
    if (at <= now) at.setDate(at.getDate() + 1)
    return Math.max(1, Math.round((at - now) / 60000))
  }

  // ------------------------------------------- shared data/format helpers

  // 45s, 12m, 1h05m
  function dur(ms) {
    var s = Math.max(0, Math.round(ms / 1000))
    if (s < 60) return s + "s"
    var m = Math.round(s / 60)
    if (m < 60) return m + "m"
    return Math.floor(m / 60) + "h" + ((m % 60) < 10 ? "0" : "") + (m % 60) + "m"
  }

  function faceText() {
    if (!reachable || !snap) return "あ"
    if (paused) return "あ  " + dur(pausedMs)
    return stats ? "あ " + stats.today.answers : "あ"
  }

  function heroMeta() {
    if (!reachable) return "Daemon not running"
    if (!snap) return "Asking the daemon…"
    if (paused) return "Paused · " + dur(pausedMs) + " left"
    if (questionUp) return "Question waiting · " + dur(waitingMs)
    if (snap.popped !== null) return "Answer graded"
    if (snap.inactive) return "Screen idle"
    // Counted in active time: it stands still while the screen is locked.
    return "Next question in about " + dur(Math.max(0, snap.next_pop_active_ms - sinceSnap))
  }

  function rightPercent() {
    if (!stats || stats.today.answers === 0) return -1
    return Math.round(stats.today.right * 100 / stats.today.answers)
  }

  // "2026-10-05" → "10/5"
  function lessonLabel() {
    if (!stats || !stats.queue.lesson) return ""
    var p = String(stats.queue.lesson).split("-")
    return p.length === 3 ? Number(p[1]) + "/" + Number(p[2]) : stats.queue.lesson
  }

  // The chart's days, oldest first: one letter for the weekday and the count.
  function week() {
    var out = []
    var counts = stats ? stats.week : []
    var letters = ["S", "M", "T", "W", "T", "F", "S"]
    for (var i = 0; i < counts.length; i++) {
      var d = new Date()
      d.setDate(d.getDate() - (counts.length - 1 - i))
      out.push({ letter: letters[d.getDay()], count: counts[i], today: i === counts.length - 1 })
    }
    return out
  }

  // ------------------------------------------------------------ processes

  Process {
    id: statsProc
    command: [service.cli, "stats"]
    stdout: StdioCollector { id: statsOut }
    onExited: function(exitCode) {
      var reply = null
      if (exitCode === 0) {
        try { reply = JSON.parse(statsOut.text) } catch (e) {}
      }
      // A daemon that is down (or one from before `stats` existed) keeps the
      // last numbers on the panel; the faces dim.
      service.reachable = reply !== null && reply.ok === true
      if (service.reachable) {
        service.snap = reply
        service.snapMs = Date.now()
      }
      service.nowMs = Date.now()
    }
  }

  Process {
    id: cmdProc
    stdout: StdioCollector { id: cmdOut }
    onExited: function(exitCode) {
      service.busy = false
      var reply = null
      try { reply = JSON.parse(cmdOut.text) } catch (e) {}
      var asked = service.lastCommand === "ask" || service.lastCommand === "summon"
      if (exitCode !== 0 || reply === null) service.notice = "The daemon did not answer"
      else if (reply.ok === false) service.notice = reply.error ? String(reply.error) : "That did not work"
      // `ask` replies with the status: no question up means it failed, and
      // last_error says why (offline, or no new cards left).
      else if (asked && reply.popped === null) service.notice = reply.last_error ? String(reply.last_error) : "No question came up"
      service.refresh()
    }
  }

  // --------------------------------------------------------------- timers

  // The reply comes from the daemon's cache, so a poll is one local socket
  // round trip; the daemon decides when its numbers need rebuilding.
  Timer {
    interval: service.openPanels > 0 ? 5000 : 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refresh()
  }

  Timer {
    interval: 1000
    running: service.openPanels > 0
    repeat: true
    onTriggered: service.nowMs = Date.now()
  }
}
