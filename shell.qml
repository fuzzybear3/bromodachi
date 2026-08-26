import Quickshell
import Quickshell.Wayland
import QtQuick

// Visual prototype: pixel shiba buddy + JRPG dialog bubble with a typeable answer.
// Click the input to focus it, Enter to answer, Esc (in the input) or click the
// shiba to dismiss.
ShellRoot {
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

        // "ask" -> waiting for an answer, "right"/"wrong" -> feedback shown
        property string mode: "ask"
        readonly property var accepted: ["いぬ", "犬", "inu"]

        // pick a character: BUDDY=shiba|robot|ninja overrides, otherwise random
        readonly property var roster: ["shiba", "robot", "ninja"]
        readonly property string character: {
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
                            : win.mode === "wrong" ? "ざんねん…こたえは「いぬ」！"
                            : "「犬」はなんと読みますか？"
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

                            onAccepted: {
                                if (win.mode !== "ask") {          // second Enter: next round
                                    win.mode = "ask"
                                    text = ""
                                    return
                                }
                                var a = text.trim().toLowerCase()
                                win.mode = win.accepted.indexOf(a) >= 0 ? "right" : "wrong"
                            }
                            Keys.onEscapePressed: slideOut.start()
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
                        text: win.mode === "ask" ? "Enter でこたえる ・ Esc でとじる"
                                                 : "Enter でつぎへ"
                    }
                }
            }

            // ---- bubble tail, stepping down onto the shiba's head ----
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
                    onClicked: slideOut.start()
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
}
