import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "questions.js" as Questions

// Bromodachi: pixel buddy that quizzes you on Japanese.
// - Random question from questions.js; answer with kana, kanji, or romaji.
// - You cannot close him until you answer: Esc / clicking him just shakes.
//   After feedback, Enter = next question, Esc or click = dismiss.
// - SUPER+B (via `bromodachi summon`) toggles exclusive keyboard focus on the
//   answer box through the "buddy" IPC target.
ShellRoot {
    id: shell

    PanelWindow {
        id: win
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
        WlrLayershell.keyboardFocus: kbMode === 2 ? WlrKeyboardFocus.Exclusive
                                   : kbMode === 1 ? WlrKeyboardFocus.OnDemand
                                                  : WlrKeyboardFocus.None
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

        // "ask" -> waiting for an answer, "right"/"wrong" -> feedback shown
        property string mode: "ask"
        // Keyboard focus model (friendly to focus-follows-mouse):
        // baseline is OnDemand (1) — click the input to type, and moving to
        // another window takes focus away like anywhere else. SUPER+B (or
        // autofocus on summon) holds an Exclusive grab (2) so follow-mouse
        // can't instantly snatch it back — but the grab breaks as soon as
        // you actually move the mouse, press SUPER+B again, or close him.
        property int kbMode: 1
        property real cursorBaseX: -1
        property real cursorBaseY: -1

        function grabFocus() {
            cursorBaseX = -1
            kbMode = 2
            input.forceActiveFocus()
            cursorWatch.start()
        }
        function releaseFocus() {
            cursorWatch.stop()
            kbMode = 0          // push focus back to the apps...
            focusSettle.restart()
        }
        function checkCursor(pos) {
            if (cursorBaseX < 0) {
                cursorBaseX = pos.x
                cursorBaseY = pos.y
            } else if (Math.hypot(pos.x - cursorBaseX, pos.y - cursorBaseY) > 60) {
                releaseFocus()  // real mouse movement: let focus follow it again
            }
        }

        Timer {
            id: focusSettle
            interval: 250
            onTriggered: win.kbMode = 1   // ...then settle at OnDemand
        }
        Timer {
            id: cursorWatch
            interval: 150
            repeat: true
            onTriggered: if (!cursorProc.running) cursorProc.running = true
        }
        Process {
            id: cursorProc
            command: ["hyprctl", "cursorpos", "-j"]
            stdout: StdioCollector {
                onStreamFinished: win.checkCursor(JSON.parse(text))
            }
        }

        // IME: fcitx5 input state is per-window, so we only ever activate
        // mozc for our own input context — other windows keep their own
        // state and ours dies with the window. Fired twice with a delay:
        // the activation must land after fcitx registers our context, and
        // one early shot can lose that race.
        Timer {
            id: imeActivate
            property int shots: 0
            interval: 350
            repeat: true
            onTriggered: {
                Quickshell.execDetached(["fcitx5-remote", "-o"])
                if (++shots >= 2)
                    stop()
            }
        }

        // grab after the surface is mapped; doing it in onCompleted is too
        // early and the compositor never delivers the focus
        Timer {
            id: autofocusDelay
            interval: 450
            onTriggered: win.grabFocus()
        }
        Component.onCompleted: {
            if (Quickshell.env("BUDDY_AUTOFOCUS") === "1")
                autofocusDelay.start()
        }

        // one question per summon
        property int qIndex: Questions.randomIndex(-1)
        readonly property var q: Questions.BANK[qIndex]

        // closing is only allowed once the current question was answered
        function tryClose() {
            if (mode === "ask")
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
            Component.onCompleted: slideIn.start()

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
                        color: win.mode === "right" ? "#7ce38b"
                             : win.mode === "wrong" ? "#f28b82" : "#ffffff"
                        text: win.mode === "right" ? "せいかい！！すごい！"
                            : win.mode === "wrong" ? "ざんねん…こたえは「" + win.q.answers[0] + "」！"
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
                                    imeActivate.shots = 0
                                    imeActivate.restart()
                                } else {
                                    imeActivate.stop()
                                }
                            }

                            onAccepted: {
                                if (win.mode !== "ask") {          // second Enter: dismiss
                                    slideOut.start()
                                    return
                                }
                                if (text.trim() === "")
                                    return
                                win.mode = Questions.isCorrect(win.q, text) ? "right" : "wrong"
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
                        text: win.mode === "ask" ? "Enter でこたえる"
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
                source: win.mode === "right" || blink.closed
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
            onFinished: Qt.quit()
        }
    }

    IpcHandler {
        target: "buddy"

        // SUPER+B while running: pull keyboard focus into the input, or hand
        // it back to your apps if the input already has it
        function focus(): void {
            if (input.activeFocus)
                win.releaseFocus()
            else
                win.grabFocus()
        }

        // debug probe: does the input currently have keyboard focus?
        function focused(): bool {
            return input.activeFocus
        }

        // debug probe: focus/cursor-watch internals
        function dbg(): string {
            return "kbMode=" + win.kbMode
                 + " base=" + win.cursorBaseX + "," + win.cursorBaseY
                 + " watch=" + cursorWatch.running
                 + " proc=" + cursorProc.running
        }

        function setCharacter(name: string): void {
            if (win.roster.indexOf(name) >= 0)
                win.character = name
        }
    }
}
