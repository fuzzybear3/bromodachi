import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "grading.js" as Grading

// Bromodachi pop-up view: one short-lived process per question.
// The daemon is the brain; this is only the face. Contract:
//   env  BUDDY_QUESTION   the question as JSON {id,type,prompt,answers,hint,ja}
//        BUDDY_CHARACTER  shiba|robot|ninja
//        BUDDY_DRILL      "1" -> wrong answers enter drill mode
//        BUDDY_OUT        path prefix for the two files this view writes
//   out  BUDDY_OUT.ready  {"input_x","input_y"} global answer-box coords,
//                         written once the surface has landed (cursor warp)
//        BUDDY_OUT.result {"correct","mode","typed",...} written the moment
//                         the first answer is graded — NOT at dismissal, so
//                         a suspend during the feedback state loses nothing
// Killed by the daemon before a result exists = retracted, nothing recorded.
ShellRoot {
    id: shell

    PanelWindow {
        id: win
        visible: true
        anchors {
            right: true
            bottom: true
        }
        margins.right: 32
        implicitWidth: 480
        // tall enough that a wrapped prompt plus the hint / correct-answer
        // line still clears the sprite; the bubble grows upward from it
        implicitHeight: 560
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "bromodachi"

        // live on the external monitor when one is connected
        screen: {
            var scr = Quickshell.screens
            for (var i = 0; i < scr.length; i++)
                if (scr[i].name.indexOf("eDP") !== 0)
                    return scr[i]
            return scr.length > 0 ? scr[0] : null
        }

        readonly property var q: JSON.parse(Quickshell.env("BUDDY_QUESTION"))
        readonly property bool drill: Quickshell.env("BUDDY_DRILL") === "1"
        readonly property string outPrefix: Quickshell.env("BUDDY_OUT")
        // absolute path handed over by the daemon: quickshell blackholes any
        // relative path that escapes the shell root, so ../assets cannot work
        readonly property string assetsDir: Quickshell.env("BUDDY_ASSETS")
        property string character: {
            var pick = Quickshell.env("BUDDY_CHARACTER")
            return ["shiba", "robot", "ninja"].indexOf(pick) >= 0 ? pick : "shiba"
        }

        // "ask" -> waiting for an answer; "right"/"wrong"/"drilled" ->
        // feedback shown, dismissal allowed; "drill" -> wrong answer must
        // be typed out before leaving
        property string mode: "ask"
        property bool hintShown: false
        property real shownAtMs: 0

        // result files go through a tiny python writer: QML itself has no
        // synchronous file API, and a detached writer survives Qt.quit()
        function writeJson(path, obj) {
            Quickshell.execDetached(["python3", "-c",
                "import sys; open(sys.argv[1], 'w').write(sys.argv[2])",
                path, JSON.stringify(obj)])
        }

        // the one moment an attempt is recorded: the first grading
        function grade(text) {
            var ok = Grading.isCorrect(q, text)
            win.writeJson(outPrefix + ".result", {
                correct: ok,
                mode: ok ? "right" : (drill ? "drill" : "wrong"),
                typed: text,
                shown_at_ms: shownAtMs,
                answered_at_ms: Date.now(),
                hint_used: hintShown,
            })
            return ok
        }

        // closing is only allowed once the current question was answered
        // (and, in drill mode, the correct answer typed out)
        function tryClose() {
            if (mode === "ask" || mode === "drill")
                shake.restart()
            else
                slideOut.start()
        }

        Component.onCompleted: {
            shownAtMs = Date.now()
            slideIn.restart()
            readyPing.start()
        }
        // report the answer box's global coords once layout has settled;
        // the daemon polls for this file before warping the cursor
        Timer {
            id: readyPing
            interval: 120
            onTriggered: {
                var p = input.mapToItem(content, input.width / 2, input.height / 2)
                var wx = win.screen.x + win.screen.width - win.implicitWidth - 32
                var wy = win.screen.y + win.screen.height - win.implicitHeight
                win.writeJson(win.outPrefix + ".ready", {
                    input_x: Math.round(wx + p.x),
                    input_y: Math.round(wy + p.y),
                    // window rect: "is the cursor on the buddy?" is how the
                    // daemon decides between focus and un-focus on summon
                    window_x: Math.round(wx),
                    window_y: Math.round(wy),
                    window_w: win.implicitWidth,
                    window_h: win.implicitHeight,
                })
            }
        }

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

                    // While answering, F1 reveals the hint. Once the answer
                    // is already on screen (wrong / drill) the meaning is
                    // shown unprompted: nothing is left to give away, and
                    // the meaning is what has to stick. Column skips
                    // invisible children, so this costs no height when empty.
                    Text {
                        width: parent.width
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 15
                        color: win.mode === "ask" ? "#f0c419" : "#9ecbff"
                        text: {
                            if (win.mode === "ask")
                                return win.hintShown
                                       ? "ヒント: " + Grading.hintFor(win.q)
                                       : ""
                            if (win.mode === "wrong" || win.mode === "drill") {
                                var m = Grading.meaningFor(win.q)
                                return m === "" ? "" : "いみ: " + m
                            }
                            return ""
                        }
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
                                    // re-typing the revealed answer; never recorded
                                    if (Grading.isCorrect(win.q, text))
                                        win.mode = "drilled"
                                    else
                                        shake.restart()
                                    return
                                }
                                if (win.grade(text)) {
                                    win.mode = "right"
                                } else if (win.drill) {
                                    win.mode = "drill"
                                    text = ""
                                } else {
                                    win.mode = "wrong"
                                }
                            }
                            Keys.onEscapePressed: win.tryClose()
                            // F1 toggles the hint. Chosen over Ctrl+H or Tab
                            // because mozc claims both while composing.
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_F1) {
                                    win.hintShown = !win.hintShown
                                    event.accepted = true
                                }
                            }
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
                        text: win.mode === "ask"   ? "Enter でこたえる ・ F1 でヒント"
                            : win.mode === "drill" ? "こたえを うちこんで Enter"
                                                   : "Enter か Esc でとじる"

                        // same toggle by mouse, for when the keyboard is
                        // busy with the IME
                        MouseArea {
                            anchors.fill: parent
                            enabled: win.mode === "ask"
                            onClicked: win.hintShown = !win.hintShown
                        }
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
                        ? "file://" + win.assetsDir + "/" + win.character + "_blink.png"  // closed eyes = happy
                        : "file://" + win.assetsDir + "/" + win.character + ".png"

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
                Qt.quit()
            }
        }
    }
}
