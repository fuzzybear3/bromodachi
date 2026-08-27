import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "questions.js" as Questions

// Bromodachi: pixel buddy that quizzes you on Japanese.
// - Random question from questions.js; answer with kana, kanji, or romaji.
// - You cannot close him until you answer: Esc / clicking him just shakes.
//   Wrong answers can enter drill mode (BUDDY_DRILL=1): type the correct
//   answer before you may leave.
// - Focus is plain OnDemand and plays nice with focus-follows-mouse: the
//   launcher warps the cursor onto the answer box (SUPER+B) and back, and
//   the compositor's own rules do the focusing. No grabs, ever.
// - fcitx5/mozc activates while the input is focused and deactivates when
//   focus leaves, so you're back to English in your own windows.
ShellRoot {
    id: shell

    PanelWindow {
        id: win
        visible: false   // daemon: hidden until the timer fires or a summon
        anchors {
            right: true
            bottom: true
        }
        margins.right: 32
        implicitWidth: 480
        implicitHeight: 400
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "bromodachi"

        // live on the external monitor when one is connected (reactive:
        // the window moves if screens come and go while it's up)
        screen: {
            var scr = Quickshell.screens
            for (var i = 0; i < scr.length; i++)
                if (scr[i].name.indexOf("eDP") !== 0)
                    return scr[i]
            return scr.length > 0 ? scr[0] : null
        }

        // "ask" -> waiting for an answer; "right"/"wrong"/"drilled" ->
        // feedback shown, dismissal allowed; "drill" -> wrong answer must
        // be typed out before leaving
        property string mode: "ask"
        // drill mode: a wrong answer must be typed out correctly before
        // the buddy can be dismissed
        readonly property bool drill: Quickshell.env("BUDDY_DRILL") === "1"

        // IME: fcitx5 input state is per-window. Activate mozc for our own
        // input context while the input is focused, and deactivate whatever
        // context focus lands on afterwards so you're back to English.
        // Each fires twice with a delay: the command must land after fcitx
        // finishes switching contexts, and one early shot can lose that race.
        Timer {
            id: imeActivate
            property int shots: 0
            interval: 350
            repeat: true
            onTriggered: {
                if (input.activeFocus)
                    Quickshell.execDetached(["fcitx5-remote", "-o"])
                if (++shots >= 2)
                    stop()
            }
        }
        Timer {
            id: imeDeactivate
            property int shots: 0
            interval: 350
            repeat: true
            onTriggered: {
                if (!input.activeFocus)
                    Quickshell.execDetached(["fcitx5-remote", "-c"])
                if (++shots >= 2)
                    stop()
            }
        }

        // one question per summon
        property int qIndex: Questions.randomIndex(-1)
        readonly property var q: Questions.BANK[qIndex]

        // Pop-up scheduling: intervalMinutes from config, jittered +/-30%,
        // counted in ACTIVE time only. A 5s heartbeat accumulates elapsed
        // time, but skips ticks whose gap is implausibly large (suspend/
        // hibernate) and ticks while the screen is locked (hyprlock, which
        // Omarchy's idle timeout raises, so long AFK stops the clock too).
        readonly property real intervalMin: {
            var v = parseFloat(Quickshell.env("BUDDY_INTERVAL_MIN"))
            return isNaN(v) || v <= 0 ? 10 : v
        }
        property real targetMs: 0
        property real accumMs: 0
        property real lastTick: 0
        property bool sysLocked: false

        function scheduleNext() {
            targetMs = Math.round(
                intervalMin * 60000 * (0.7 + Math.random() * 0.6))
            accumMs = 0
            lastTick = Date.now()
            tickTimer.restart()
        }
        Timer {
            id: tickTimer
            interval: 5000
            repeat: true
            onTriggered: {
                var now = Date.now()
                var dt = now - win.lastTick
                win.lastTick = now
                if (dt < 15000 && !win.sysLocked && !win.visible)
                    win.accumMs += dt
                if (!lockProc.running)
                    lockProc.running = true
                if (win.accumMs >= win.targetMs)
                    win.show()
            }
        }
        Process {
            id: lockProc
            command: ["pgrep", "-x", "hyprlock"]
            onExited: (code, status) => win.sysLocked = (code === 0)
        }
        Component.onCompleted: scheduleNext()

        function show() {
            if (win.visible)
                return
            tickTimer.stop()
            qIndex = Questions.randomIndex(qIndex)
            mode = "ask"
            input.text = ""
            win.visible = true
            slideIn.restart()
        }

        // closing is only allowed once the current question was answered
        // (and, in drill mode, the correct answer typed out)
        function tryClose() {
            if (mode === "ask" || mode === "drill")
                shake.restart()
            else
                slideOut.start()
        }

        // pick a character: BUDDY=shiba|robot|ninja overrides, otherwise random
        readonly property var roster: ["shiba", "robot", "ninja"]
        property string character: {
            var pick = Quickshell.env("BUDDY")
            return roster.indexOf(pick) >= 0
                   ? pick
                   : roster[Math.floor(Math.random() * roster.length)]
        }

        Item {
            id: content
            anchors.fill: parent
            transform: Translate { id: slide; y: win.implicitHeight }

            NumberAnimation {
                id: slideIn
                target: slide
                property: "y"
                from: win.implicitHeight
                to: 0
                duration: 550
                easing.type: Easing.OutBack
                easing.overshoot: 0.7
            }

            // refused-to-close head shake
            SequentialAnimation {
                id: shake
                NumberAnimation { target: slide; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: slide; property: "x"; to: 12; duration: 90 }
                NumberAnimation { target: slide; property: "x"; to: -6; duration: 70 }
                NumberAnimation { target: slide; property: "x"; to: 0; duration: 50 }
            }

            // ---- dialog bubble (JRPG style: navy box, white pixel border) ----
            Rectangle {  // drop shadow
                x: bubble.x + 6
                y: bubble.y + 6
                width: bubble.width
                height: bubble.height
                color: "#000000"
                opacity: 0.35
            }
            Rectangle {
                id: bubble
                x: 0
                y: parent.height - sprite.height - height - 22
                width: parent.width - 12
                height: bubbleCol.implicitHeight + 36
                color: "#1a1a2e"
                border.color: "#ffffff"
                border.width: 3

                Column {
                    id: bubbleCol
                    x: 18
                    y: 18
                    width: parent.width - 36
                    spacing: 14

                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 20
                        textFormat: Text.StyledText
                        color: win.mode === "right" || win.mode === "drilled"
                               ? "#7ce38b" : "#ffffff"
                        text: win.mode === "right"   ? "せいかい！！すごい！"
                            : win.mode === "drilled" ? "よくできました！じゃあまた！"
                            : win.mode === "wrong"   ? win.q.prompt + "<br><font color=\"#f28b82\">ざんねん…こたえは「" + win.q.answers[0] + "」！</font>"
                            : win.mode === "drill"   ? win.q.prompt + "<br><font color=\"#f0c419\">こたえは「" + win.q.answers[0] + "」— タイプしてね！</font>"
                            : win.q.prompt
                    }

                    Rectangle {
                        width: parent.width
                        height: 46
                        color: "#10101f"
                        border.color: input.activeFocus ? "#e8964a" : "#8888aa"
                        border.width: 2

                        TextInput {
                            id: input
                            anchors.fill: parent
                            anchors.margins: 10
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: "Noto Sans CJK JP"
                            font.pixelSize: 18
                            color: "#ffffff"
                            clip: true
                            focus: true
                            onActiveFocusChanged: {
                                if (activeFocus && win.q.ja !== false) {
                                    imeDeactivate.stop()
                                    imeActivate.shots = 0
                                    imeActivate.restart()
                                } else {
                                    imeActivate.stop()
                                    imeDeactivate.shots = 0
                                    imeDeactivate.restart()
                                }
                            }

                            onAccepted: {
                                if (win.mode === "right" || win.mode === "wrong"
                                        || win.mode === "drilled") {
                                    slideOut.start()               // second Enter: dismiss
                                    return
                                }
                                if (text.trim() === "")
                                    return
                                if (win.mode === "drill") {
                                    if (Questions.isCorrect(win.q, text))
                                        win.mode = "drilled"
                                    else
                                        shake.restart()
                                    return
                                }
                                if (Questions.isCorrect(win.q, text)) {
                                    win.mode = "right"
                                } else if (win.drill) {
                                    win.mode = "drill"
                                    text = ""
                                } else {
                                    win.mode = "wrong"
                                }
                            }
                            Keys.onEscapePressed: win.tryClose()
                        }
                        Text {  // placeholder
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            visible: input.text.length === 0 && !input.inputMethodComposing
                            font.family: "Noto Sans CJK JP"
                            font.pixelSize: 18
                            color: "#666688"
                            text: "ここにこたえてね…"
                        }
                    }

                    Text {
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 12
                        color: "#8888aa"
                        text: win.mode === "ask"   ? "Enter でこたえる"
                            : win.mode === "drill" ? "こたえを うちこんで Enter"
                                                   : "Enter か Esc でとじる"
                    }
                }
            }

            // ---- bubble tail, stepping down onto the buddy's head ----
            Rectangle { x: parent.width - 110; y: bubble.y + bubble.height - 2; width: 30; height: 12; color: "#1a1a2e"; border.color: "#ffffff"; border.width: 3 }
            Rectangle { x: parent.width - 96;  y: bubble.y + bubble.height + 9; width: 16; height: 12; color: "#1a1a2e"; border.color: "#ffffff"; border.width: 3 }

            // ---- the buddy ----
            Image {
                id: sprite
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 160    // 20 px * 8
                height: 176   // 22 px * 8
                smooth: false // nearest-neighbor: keep pixels crisp
                source: win.mode === "right" || win.mode === "drilled" || blink.closed
                        ? Qt.resolvedUrl("assets/" + win.character + "_blink.png")  // closed eyes = happy
                        : Qt.resolvedUrl("assets/" + win.character + ".png")

                Timer {
                    id: blink
                    property bool closed: false
                    interval: closed ? 150 : 3400
                    running: true
                    repeat: true
                    onTriggered: closed = !closed
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: win.tryClose()
                }
            }
        }

        NumberAnimation {
            id: slideOut
            target: slide
            property: "y"
            to: win.implicitHeight + 8
            duration: 300
            easing.type: Easing.InQuad
            onFinished: {
                // back to English wherever focus lands after we're gone
                Quickshell.execDetached(["sh", "-c", "sleep 0.4; fcitx5-remote -c"])
                win.visible = false
                win.scheduleNext()
            }
        }
    }

    IpcHandler {
        target: "buddy"

        // does the input currently have keyboard focus?
        function focused(): bool {
            return input.activeFocus
        }

        // named "reveal" because `show` is a reserved word in `qs ipc call`
        function reveal(): void {
            win.show()
        }

        function isShown(): bool {
            return win.visible
        }

        // dev hook: active-ms remaining until next pop-up (plus lock state),
        // or -1 when visible/not scheduled
        function nextPop(): string {
            return tickTimer.running
                   ? Math.max(0, Math.round(win.targetMs - win.accumMs)) + " locked=" + win.sysLocked
                   : "-1"
        }

        // dev hook: force a UI state to preview it
        function setMode(m: string): void {
            if (["ask", "right", "wrong", "drill", "drilled"].indexOf(m) >= 0)
                win.mode = m
        }

        // global screen coordinates of the answer box center, for the
        // launcher's cursor warp
        function inputPos(): string {
            var p = input.mapToItem(null, input.width / 2, input.height / 2)
            var wx = win.screen.x + win.screen.width - win.implicitWidth - 32
            var wy = win.screen.y + win.screen.height - win.implicitHeight
            return Math.round(wx + p.x) + " " + Math.round(wy + p.y)
        }

        function setCharacter(name: string): void {
            if (win.roster.indexOf(name) >= 0)
                win.character = name
        }
    }
}
