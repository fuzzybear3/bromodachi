import Quickshell
import Quickshell.Wayland
import QtQuick

// Visual prototype: the bromodachi buddy sits in the bottom-right corner,
// blinks occasionally, and slides away when clicked.
ShellRoot {
    PanelWindow {
        id: win
        anchors {
            right: true
            bottom: true
        }
        margins.right: 48
        implicitWidth: 160
        implicitHeight: 176
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bromodachi"

        Image {
            id: sprite
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 160    // 20 px * 8
            height: 176   // 22 px * 8
            smooth: false // nearest-neighbor: keep pixels crisp
            source: Qt.resolvedUrl("assets/buddy.png")

            transform: Translate { id: slide; y: sprite.height }

            // slide up from the screen edge on start
            NumberAnimation {
                id: slideIn
                target: slide
                property: "y"
                from: sprite.height
                to: 0
                duration: 500
                easing.type: Easing.OutBack
                easing.overshoot: 0.8
            }
            Component.onCompleted: slideIn.start()

            // blink every few seconds
            Timer {
                interval: 3400
                running: true
                repeat: true
                onTriggered: {
                    sprite.source = Qt.resolvedUrl("assets/buddy_blink.png")
                    unblink.start()
                }
            }
            Timer {
                id: unblink
                interval: 150
                onTriggered: sprite.source = Qt.resolvedUrl("assets/buddy.png")
            }
        }

        // click the buddy to dismiss it
        MouseArea {
            anchors.fill: sprite
            onClicked: slideOut.start()
        }
        NumberAnimation {
            id: slideOut
            target: slide
            property: "y"
            to: sprite.height + 8
            duration: 300
            easing.type: Easing.InQuad
            onFinished: Qt.quit()
        }
    }
}
