import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "grading.js" as Grading

// Bromodachi v3 view: a persistent cat living along the bottom of the screen.
// The daemon is the brain; this is only the face. It stays up for the whole
// session and the daemon supervises it (src/view.rs, CatHost).
//
// Window: one full-screen transparent Overlay layer on HDMI-A-1 when it is
// connected (else the first screen). The input mask is only the cat, plus the
// bubble while a question is up, so the rest of the screen is click-through.
// Keyboard focus is None unless a question is up.
//
// Contract with the daemon (same files the old popup wrote):
//   in   qs -p view/cat.qml ipc call cat ask <question json> <out prefix> <drill 1|0>
//        qs -p view/cat.qml ipc call cat retract     (withdraw; nothing recorded)
//   out  <out>.ready   {"input_x","input_y","window_*"} once the bubble lands
//        <out>.result  written the moment the first answer is graded
//        <out>.done    written when the bubble is dismissed (not on retract)
// Sprites: assets/cat/cat_sheet_3x.png from assets/make_cat.py.
ShellRoot {
    id: shell

    readonly property var home: {
        const s = Quickshell.screens
        for (let i = 0; i < s.length; i++)
            if (s[i].name === "HDMI-A-1") return s[i]
        return s.length > 0 ? s[0] : null
    }

    PanelWindow {
        id: win
        screen: shell.home
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bromodachi-cat"
        // never takes the keyboard: hovering or grabbing the cat must not
        // steal typing. The bubble lives in its own window (bubbleWin below)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // only the cat takes input; the rest of the screen is click-through
        mask: Region { item: cat }

        // ---------------------------------------------------------- tunables
        readonly property real catW: 96      // 32 px sprite at 3x
        readonly property real catH: 72      // 24 px sprite at 3x
        readonly property real gravity: 2600 // px/s^2
        readonly property real walkSpeed: 70 // px/s
        readonly property real stickSpeed: 450 // min wall-hit speed to cling, px/s
        readonly property real slideAccel: 260 // px/s^2 down the wall
        readonly property real slideMax: 420   // px/s
        readonly property real launchSpeed: 1800 // upward throw that sends it off-screen, px/s
        readonly property real floorY: height - catH
        readonly property string assetsDir: {
            const u = Qt.resolvedUrl(".").toString().replace("file://", "")
            return u.replace(/\/view\/?$/, "") + "/assets"
        }
        // animation table written by assets/make_cat.py
        FileView { id: animFile; path: win.assetsDir + "/cat/cat_sheet.json"; blockLoading: true }
        readonly property var anims: JSON.parse(animFile.text())

        // ------------------------------------------------------------- state
        // sleep | wake | walk | sit | held | fall | wallslide | land | alert
        // | launched (thrown off the top) | gone (hidden until the next ask)
        property string mode: "sleep"
        property real vx: 0
        property real vy: 0
        property real walkTo: 0
        // back from "gone" for a question: the bubble waits for the landing
        property bool entering: false
        property real lastMouseX: 0
        property real lastMouseY: 0
        property real lastMouseT: 0
        // dangling pendulum, integrated per frame (not per mouse event), so
        // a hand that stops always lets the cat swing back to vertical
        property real handX: 0
        property real handPrevX: 0
        property real handV: 0
        property real swayAng: 0   // rad, + = body swung left (clockwise)
        property real swayVel: 0   // rad/s
        readonly property real swayLen: 50   // pendulum length, px
        readonly property real swayDamp: 4   // 1/s

        // thrown or bounced: look where we are flying (a gentle drop keeps
        // whichever way the cat was already facing)
        function faceTravel() {
            if (Math.abs(vx) > 60) cat.facing = vx < 0 ? -1 : 1
        }

        function setMode(m) {
            // a question is up: whenever the cat would idle, it looks alert
            if (asking && ["sleep", "sit", "wake", "walk"].indexOf(m) >= 0) m = "alert"
            mode = m
            // how long each resting state lasts before the next decision
            if (m === "sleep") idle.interval = 40000 + Math.random() * 80000
            else if (m === "sit") idle.interval = 4000 + Math.random() * 6000
            else if (m === "wake") idle.interval = 1200
            else if (m === "land") idle.interval = 700
            else return idle.stop()
            idle.restart()
        }

        Timer {
            id: idle
            onTriggered: {
                if (win.mode === "sleep") {
                    win.setMode("wake")
                } else if (win.mode === "wake") {
                    // wander somewhere 120..600 px away, staying on screen
                    const d = (120 + Math.random() * 480) * (Math.random() < 0.5 ? -1 : 1)
                    win.walkTo = Math.max(0, Math.min(win.width - win.catW, cat.x + d))
                    win.setMode("walk")
                } else if (win.mode === "sit") {
                    win.setMode(Math.random() < 0.8 ? "sleep" : "wake")
                } else if (win.mode === "land") {
                    win.setMode("sit")
                }
            }
        }

        // physics + walking, one step per rendered frame
        FrameAnimation {
            running: win.mode === "fall" || win.mode === "walk" || win.mode === "wallslide"
                     || win.mode === "held" || win.mode === "launched"
            onTriggered: {
                const dt = Math.min(frameTime, 0.05)
                if (win.mode === "held") {
                    // hand velocity/acceleration sampled once per frame: a
                    // still mouse sends no events, and this still reads it
                    // as v = 0, so the swing always settles
                    const v = (win.handX - win.handPrevX) / Math.max(dt, 0.001)
                    win.handPrevX = win.handX
                    const vs = 0.5 * win.handV + 0.5 * v
                    const a = Math.max(-30000, Math.min(30000, (vs - win.handV) / Math.max(dt, 0.001)))
                    win.handV = vs
                    // body lags the hand: accelerate right -> swing left
                    const acc = (a / win.swayLen) * Math.cos(win.swayAng)
                              - (win.gravity / win.swayLen) * Math.sin(win.swayAng)
                              - win.swayDamp * win.swayVel
                    win.swayVel += acc * dt
                    win.swayAng += win.swayVel * dt
                    if (Math.abs(win.swayAng) > 1.0) {
                        win.swayAng = Math.sign(win.swayAng) * 1.0
                        win.swayVel = 0
                    }
                    cat.sway = win.swayAng * 180 / Math.PI
                    // throw speed is measured from events; forget it once
                    // the hand has been still for a moment
                    if (Date.now() - win.lastMouseT > 25) {
                        const k = Math.pow(0.001, dt)
                        win.vx *= k
                        win.vy *= k
                    }
                    return
                }
                if (win.mode === "walk") {
                    const dir = Math.sign(win.walkTo - cat.x)
                    cat.facing = dir < 0 ? -1 : 1
                    cat.x += dir * win.walkSpeed * dt
                    if (Math.abs(win.walkTo - cat.x) < 2) win.setMode("sit")
                    return
                }
                if (win.mode === "launched") {
                    // blasting off: no gravity, spinning, straight out the top
                    cat.x = Math.max(0, Math.min(win.width - win.catW, cat.x + win.vx * dt))
                    cat.y += win.vy * dt
                    cat.spin += 900 * dt
                    if (cat.y < -win.catH - 20) {
                        twinkle.x = cat.x + cat.width / 2 - twinkle.width / 2
                        twinkle.restart()
                        win.setMode("gone")
                    }
                    return
                }
                if (win.mode === "wallslide") {
                    // claws dragging down the wall: slow start, gentle speed-up
                    win.vy = Math.min(win.vy + win.slideAccel * dt, win.slideMax)
                    cat.y += win.vy * dt
                    if (cat.y >= win.floorY) {
                        cat.y = win.floorY
                        squash.impact = 0.25
                        squash.restart()
                        win.vy = 0
                        win.setMode("land")
                    }
                    return
                }
                win.vy += win.gravity * dt
                win.vx *= Math.pow(0.4, dt) // air drag
                cat.x = Math.max(0, Math.min(win.width - win.catW, cat.x + win.vx * dt))
                cat.y += win.vy * dt
                if (cat.y < 0) { cat.y = 0; win.vy = -win.vy * 0.3 } // bonk the top edge
                if (cat.x <= 0 || cat.x >= win.width - win.catW) {
                    // a hard hit high up the wall: grab on and slide down it.
                    // anything softer (or near the floor) just bounces off
                    if (Math.abs(win.vx) > win.stickSpeed && cat.y < win.floorY - win.catH) {
                        cat.facing = cat.x <= 0 ? -1 : 1 // belly to the wall
                        win.vx = 0
                        win.vy = Math.max(0, Math.min(win.vy, 60))
                        win.setMode("wallslide")
                        return
                    }
                    win.vx = -win.vx * 0.4
                    win.faceTravel()
                }
                if (cat.y >= win.floorY) {
                    cat.y = win.floorY
                    squash.impact = Math.min(win.vy / 2500, 1)
                    squash.restart()
                    win.vx = 0; win.vy = 0
                    win.setMode("land")
                    if (win.entering) {
                        win.entering = false
                        win.showBubble()
                    }
                }
            }
        }

        // ---------------------------------------------------------- the cat
        Item {
            id: cat
            width: win.catW
            height: win.catH
            x: win.width - win.catW - 160
            y: win.floorY
            property int facing: 1
            property real grabX: width / 2
            property real grabY: 0
            property real sway: 0
            property real spin: 0
            visible: win.mode !== "gone"

            // mode -> row of assets/cat/cat_sheet_3x.png (make_cat.py). The
            // wallslide art hugs the right edge of its cell, so on the left
            // wall the facing flip below puts it flush against that wall too
            readonly property var anim: {
                const m = { wake: "stretch", land: "stand" }[win.mode] || win.mode
                return win.anims[m] || win.anims["sit"]
            }
            onAnimChanged: sprite.restart()

            Item {
                id: body
                anchors.fill: parent
                transform: [
                    Scale {  // face the way we are walking (held is face-on)
                        origin.x: body.width / 2
                        xScale: win.mode === "held" ? 1 : cat.facing
                    },
                    Scale {
                        origin.x: body.width / 2
                        origin.y: body.height
                        yScale: 1 - squash.amount
                        xScale: 1 + squash.amount * 0.6
                    },
                    Rotation {
                        origin.x: win.mode === "launched" ? cat.width / 2 : cat.grabX
                        origin.y: win.mode === "launched" ? cat.height / 2 : cat.grabY
                        angle: win.mode === "held" ? cat.sway
                             : win.mode === "launched" ? cat.spin : 0
                    }
                ]
                AnimatedSprite {
                    id: sprite
                    anchors.fill: parent
                    source: "file://" + win.assetsDir + "/cat/cat_sheet_3x.png"
                    frameWidth: win.catW
                    frameHeight: win.catH
                    frameY: cat.anim.row * win.catH
                    frameCount: cat.anim.frames
                    frameRate: cat.anim.fps
                    loops: cat.anim.loop ? AnimatedSprite.Infinite : 1
                    interpolate: false
                }
            }

            // zzz drifting up while asleep
            Text {
                id: zzz
                visible: win.mode === "sleep"
                text: "z"
                color: "#8a8fa8"
                font.pixelSize: 16 + zzzRise.progress * 8
                font.bold: true
                opacity: 1 - zzzRise.progress
                x: (cat.facing > 0 ? cat.width * 0.62 : cat.width * 0.25) + zzzRise.progress * 14 * cat.facing
                y: cat.height * 0.25 - zzzRise.progress * 40
            }
            NumberAnimation {
                id: zzzRise
                property real progress: 0
                target: zzzRise; property: "progress"
                from: 0; to: 1; duration: 2400
                loops: Animation.Infinite
                running: win.mode === "sleep"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: win.mode === "held" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onPressed: mouse => {
                    // picked up by the scruff: the cat hops so the nape of the
                    // held (face-on) sprite is right under the cursor
                    const p = mapToItem(null, mouse.x, mouse.y)
                    cat.grabX = win.catW / 2
                    cat.grabY = 6
                    cat.x = Math.max(0, Math.min(win.width - win.catW, p.x - cat.grabX))
                    cat.y = Math.max(0, Math.min(win.floorY, p.y - cat.grabY))
                    win.vx = 0; win.vy = 0
                    win.lastMouseT = Date.now()
                    win.lastMouseX = p.x
                    win.lastMouseY = p.y
                    win.handX = p.x; win.handPrevX = p.x; win.handV = 0
                    win.swayAng = 0; win.swayVel = 0; cat.sway = 0
                    squash.stop(); squash.amount = 0
                    win.setMode("held")
                }
                onPositionChanged: mouse => {
                    if (win.mode !== "held") return
                    const p = mapToItem(null, mouse.x, mouse.y)
                    const now = Date.now()
                    const dt = Math.max((now - win.lastMouseT) / 1000, 0.008)
                    // keep a smoothed throw velocity; sway opposite to the motion
                    win.vx = 0.6 * win.vx + 0.4 * (p.x - win.lastMouseX) / dt
                    win.vy = 0.6 * win.vy + 0.4 * (p.y - win.lastMouseY) / dt
                    win.lastMouseX = p.x
                    win.lastMouseY = p.y
                    win.lastMouseT = now
                    win.handX = p.x
                    cat.x = Math.max(0, Math.min(win.width - win.catW, p.x - cat.grabX))
                    cat.y = Math.max(0, Math.min(win.floorY, p.y - cat.grabY))
                }
                onReleased: drop()
                // the compositor can cancel a grab (focus change, another
                // client grabbing); that must not leave the cat "held"
                onCanceled: drop()
                function drop() {
                    if (win.mode !== "held") return
                    // a hand that stopped before letting go throws nothing
                    if (Date.now() - win.lastMouseT > 80) { win.vx = 0; win.vy = 0 }
                    // cap throws so a flick cannot launch it into orbit
                    win.vx = Math.max(-3000, Math.min(3000, win.vx))
                    win.vy = Math.max(-2600, Math.min(2600, win.vy))
                    win.faceTravel()
                    // a hard upward fling with no question up: off it goes
                    // until the next one (while asking it just bonks the top)
                    if (win.vy < -win.launchSpeed && !win.asking) {
                        cat.spin = 0
                        win.setMode("launched")
                        return
                    }
                    win.setMode("fall")
                }
            }

        }

        // the little star left behind at the top edge when it blasts off
        Text {
            id: twinkle
            property real t: 0
            y: 4
            text: "✦"
            color: "#f0c419"
            font.pixelSize: 26
            visible: t > 0 && t < 1
            scale: t < 0.4 ? t / 0.4 * 1.4 : 1.4 * (1 - (t - 0.4) / 0.6)
            rotation: t * 180
            function restart() { twinkleAnim.restart() }
            NumberAnimation on t { id: twinkleAnim; running: false; from: 0; to: 1; duration: 650 }
        }

        // landing squash: amount goes impact -> 0 with a little bounce
        SequentialAnimation {
            id: squash
            property real impact: 0.5
            property real amount: 0
            NumberAnimation { target: squash; property: "amount"; to: squash.impact * 0.35; duration: 60 }
            NumberAnimation { target: squash; property: "amount"; to: -0.08 * squash.impact; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: squash; property: "amount"; to: 0; duration: 180; easing.type: Easing.OutBounce }
        }

        // ------------------------------------------------------------ question
        property bool asking: false
        property var q: ({ prompt: "", answers: [""], hint: null, ja: true })
        property bool drill: false
        property string outPrefix: ""
        // "ask" -> waiting for an answer; "right"/"wrong"/"drilled" ->
        // feedback shown, dismissal allowed; "drill" -> wrong answer must
        // be typed out before leaving
        property string qmode: "ask"
        // where the bubble window sits (screen coords): above the cat's head,
        // clamped inside the screen; the tail hangs below it
        readonly property real tailH: 26
        readonly property real bubbleX: Math.max(8, Math.min(width - 448 - 8, cat.x + cat.width / 2 - 224))
        readonly property real bubbleY: Math.max(8, cat.y - bubble.height - tailH)
        property bool hintShown: false
        // latched: once revealed, the attempt counts as hint-assisted
        property bool hintEverShown: false
        property real shownAtMs: 0
        // active solve time: accumulates only while the answer box has
        // focus and the question is unanswered; a gap guard drops suspends
        property real activeMs: 0
        property real lastActiveTick: 0
        // recall latency on the ACTIVE clock at the first keystroke; -1 = never
        property real firstInputActiveMs: -1
        property real lastInputActiveMs: 0
        // a stall (>3s tick gap) or >30s without input while focused makes
        // this pop's timings untrustworthy; the web excludes them
        property bool timingUnreliable: false
        // committed (non-composing) values seen while asking, for self-correction
        property var committedValues: []

        function startAsk(question, out, drillOn) {
            q = question
            outPrefix = out
            drill = drillOn
            qmode = "ask"
            hintShown = false
            hintEverShown = false
            activeMs = 0
            firstInputActiveMs = -1
            lastInputActiveMs = 0
            timingUnreliable = false
            committedValues = []
            input.text = ""
            shownAtMs = Date.now()
            lastActiveTick = shownAtMs
            asking = true
            closing.stop()
            if (mode === "gone" || mode === "launched") {
                // drop back in from the top, above where it left
                entering = true
                cat.spin = 0
                cat.y = -catH
                vx = 0; vy = 0
                setMode("fall")
                return
            }
            if (["sleep", "sit", "wake", "walk", "land"].indexOf(mode) >= 0) setMode("alert")
            showBubble()
        }

        function showBubble() {
            // an item that goes invisible drops its focus flag, so after the
            // first bubble closes the box would never take keys again; claim
            // it for every ask (it becomes active once the layer is focused)
            input.forceActiveFocus()
            bubbleIn.restart()
            // the daemon's summon warp waits for this file
            readyPing.restart()
        }

        function noteInput() {
            if (qmode !== "ask") return
            if (firstInputActiveMs < 0) firstInputActiveMs = activeMs
            lastInputActiveMs = activeMs
        }

        // QML has no synchronous file API; a detached writer is the one the
        // old popup used and it survives this process restarting
        function writeJson(path, obj) {
            Quickshell.execDetached(["python3", "-c",
                "import sys; open(sys.argv[1], 'w').write(sys.argv[2])",
                path, JSON.stringify(obj)])
        }

        // the one moment an attempt is recorded: the first grading
        function grade(text) {
            const ok = Grading.isCorrect(q, text)
            // self-corrected: the box once held a complete-looking wrong
            // value that is not merely a prefix of what was submitted
            const fin = Grading.normalize(text)
            const selfCorrected = committedValues.some(function (v) {
                const n = Grading.normalize(v)
                return n.length > 0 && n !== fin && fin.indexOf(n) !== 0
                       && !Grading.isCorrect(q, v)
            })
            writeJson(outPrefix + ".result", {
                correct: ok,
                mode: ok ? "right" : (drill ? "drill" : "wrong"),
                typed: text,
                shown_at_ms: shownAtMs,
                answered_at_ms: Date.now(),
                hint_used: hintEverShown,
                active_ms: Math.round(activeMs),
                ms_to_first_input: firstInputActiveMs < 0 ? null : Math.round(firstInputActiveMs),
                self_corrected: selfCorrected,
                timing_unreliable: timingUnreliable,
                expected_text: q.answers[0],
            })
            return ok
        }

        // closing is only allowed once answered (and, in drill mode, the
        // correct answer typed out)
        function tryClose() {
            if (qmode === "ask" || qmode === "drill") shake.restart()
            else dismiss(true)
        }

        // done=true: the user closed it (daemon records + reschedules);
        // done=false: the daemon withdrew it (retract), write nothing
        function dismiss(done) {
            if (!asking) return
            closing.done = done
            closing.restart()
        }
        SequentialAnimation {
            id: closing
            property bool done: false
            NumberAnimation { target: bubble; property: "scale"; to: 0.2; duration: 180; easing.type: Easing.InBack }
            ScriptAction {
                script: {
                    win.asking = false
                    win.entering = false
                    if (closing.done) win.writeJson(win.outPrefix + ".done", {})
                    // back to English wherever focus lands next
                    Quickshell.execDetached(["sh", "-c", "sleep 0.4; fcitx5-remote -c"])
                    if (win.mode === "alert") win.setMode("sit")
                }
            }
        }

        Timer {
            interval: 500
            repeat: true
            running: win.asking && win.qmode === "ask"
            onTriggered: {
                const now = Date.now()
                const dt = now - win.lastActiveTick
                win.lastActiveTick = now
                if (dt > 0 && dt < 3000 && input.activeFocus)
                    win.activeMs += dt
                if (input.activeFocus && (dt >= 3000
                        || win.activeMs - win.lastInputActiveMs > 30000))
                    win.timingUnreliable = true
            }
        }

        // report the answer box's global coords once the bubble has landed;
        // the daemon polls for this before warping the cursor (summon)
        Timer {
            id: readyPing
            interval: 400
            onTriggered: {
                const local = input.mapToItem(null, input.width / 2, input.height / 2)
                const ip = { x: local.x + win.bubbleX, y: local.y + win.bubbleY }
                const x0 = Math.min(win.bubbleX, cat.x), y0 = Math.min(win.bubbleY, cat.y)
                const x1 = Math.max(win.bubbleX + bubble.width, cat.x + cat.width)
                const y1 = Math.max(win.bubbleY + bubble.height, cat.y + cat.height)
                const sx = win.screen ? win.screen.x : 0, sy = win.screen ? win.screen.y : 0
                win.writeJson(win.outPrefix + ".ready", {
                    input_x: Math.round(sx + ip.x),
                    input_y: Math.round(sy + ip.y),
                    window_x: Math.round(sx + x0),
                    window_y: Math.round(sy + y0),
                    window_w: Math.round(x1 - x0),
                    window_h: Math.round(y1 - y0),
                })
            }
        }

        // IME: fcitx5 state is per input context. Turn mozc on for our box
        // while it is focused and off for whatever gets focus afterwards.
        // Each fires twice: one early shot can lose the context-switch race.
        Timer {
            id: imeActivate
            property int shots: 0
            interval: 350
            repeat: true
            onTriggered: {
                if (input.activeFocus) Quickshell.execDetached(["fcitx5-remote", "-o"])
                if (++shots >= 2) stop()
            }
        }
        Timer {
            id: imeDeactivate
            property int shots: 0
            interval: 350
            repeat: true
            onTriggered: {
                if (!input.activeFocus) Quickshell.execDetached(["fcitx5-remote", "-c"])
                if (++shots >= 2) stop()
            }
        }

        IpcHandler {
            target: "cat"
            // a new ask replaces whatever is up (e.g. the daemon restarted
            // mid-question and has already forgotten the old one)
            function ask(question: string, out: string, drill: string): string {
                win.startAsk(JSON.parse(question), out, drill === "1")
                return "ok"
            }
            function retract(): void {
                win.dismiss(false)
            }
            function where(): string {
                return (shell.home ? shell.home.name : "none") + " " + win.mode
                     + " " + Math.round(cat.x) + "," + Math.round(cat.y)
                     + (win.asking ? " asking:" + win.qmode
                        + " focus:" + (input.focus ? "set" : "none") + (input.activeFocus ? "+active" : "") : "")
            }
        }

        Component.onCompleted: setMode("sleep")
    }

    // The question bubble gets its own layer, created on ask and destroyed on
    // dismiss. Hyprland does not honour a keyboard-interactivity change on an
    // already-mapped layer, so a surface that is born OnDemand (like the old
    // popup) is what lets the summon cursor-warp actually focus the answer box.
    PanelWindow {
        id: bubbleWin
        visible: win.asking && !win.entering
        screen: shell.home
        // sized to the bubble (+ shadow and tail), not full-screen: Hyprland
        // only hover-focuses a layer when the pointer enters the surface
        // itself, and entering a masked region of a full-screen layer does
        // not count, so a full-screen bubble needed a click to take keys
        anchors { left: true; bottom: true }
        margins.left: win.bubbleX
        margins.bottom: win.height - win.bubbleY - implicitHeight
        implicitWidth: bubble.width + 8
        implicitHeight: bubble.height + win.tailH
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bromodachi-bubble"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            // ---- dialog bubble (JRPG style: navy box, white pixel border), grown
            // out of the cat's head and clamped inside the screen
            Item {
                id: bubbleWrap
                anchors.fill: parent

                Rectangle {  // drop shadow
                    x: bubble.x + 6; y: bubble.y + 6
                    width: bubble.width; height: bubble.height
                    scale: bubble.scale
                    transformOrigin: bubble.transformOrigin
                    color: "#000000"; opacity: 0.35
                }
                // two-step pixel tail down to the cat's head
                Rectangle {
                    x: Math.max(12, Math.min(bubble.width - 42, cat.x + cat.width / 2 - win.bubbleX - 15))
                    y: bubble.height - 2
                    width: 30; height: 12; color: "#1a1a2e"; border.color: "#ffffff"; border.width: 3
                    visible: bubble.scale > 0.9 && win.bubbleY + bubble.height < cat.y
                }
                Rectangle {
                    x: Math.max(19, Math.min(bubble.width - 35, cat.x + cat.width / 2 - win.bubbleX - 8))
                    y: bubble.height + 9
                    width: 16; height: 12; color: "#1a1a2e"; border.color: "#ffffff"; border.width: 3
                    visible: bubble.scale > 0.9 && win.bubbleY + bubble.height + 21 < cat.y
                }

                Rectangle {
                    id: bubble
                    width: 440
                    height: bubbleCol.implicitHeight + 36
                    x: shakeX
                    y: 0
                    property real shakeX: 0
                    transformOrigin: Item.Bottom
                    color: "#1a1a2e"
                    border.color: "#ffffff"
                    border.width: 3

                    NumberAnimation on scale {
                        id: bubbleIn
                        running: false
                        from: 0.2; to: 1; duration: 420
                        easing.type: Easing.OutBack; easing.overshoot: 1.2
                    }
                    // refused-to-close head shake
                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: bubble; property: "shakeX"; to: -12; duration: 50 }
                        NumberAnimation { target: bubble; property: "shakeX"; to: 12; duration: 90 }
                        NumberAnimation { target: bubble; property: "shakeX"; to: -6; duration: 70 }
                        NumberAnimation { target: bubble; property: "shakeX"; to: 0; duration: 50 }
                    }

                    Column {
                        id: bubbleCol
                        x: 18; y: 18
                        width: parent.width - 36
                        spacing: 14

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            font.family: "Noto Sans CJK JP"
                            font.pixelSize: 20
                            textFormat: Text.StyledText
                            color: win.qmode === "right" || win.qmode === "drilled" ? "#7ce38b" : "#ffffff"
                            text: win.qmode === "right"   ? "せいかい！！すごい！"
                                : win.qmode === "drilled" ? "よくできました！じゃあまた！"
                                : win.qmode === "wrong"   ? win.q.prompt + "<br><font color=\"#f28b82\">ざんねん…こたえは「" + win.q.answers[0] + "」！</font>"
                                : win.qmode === "drill"   ? win.q.prompt + "<br><font color=\"#f0c419\">こたえは「" + win.q.answers[0] + "」— タイプしてね！</font>"
                                : win.q.prompt
                        }

                        // F1 reveals the hint while answering; once the answer is
                        // on screen (wrong / drill) the meaning shows unprompted
                        Text {
                            width: parent.width
                            visible: text.length > 0
                            wrapMode: Text.Wrap
                            font.family: "Noto Sans CJK JP"
                            font.pixelSize: 15
                            color: win.qmode === "ask" ? "#f0c419" : "#9ecbff"
                            text: {
                                if (win.qmode === "ask")
                                    return win.hintShown ? "ヒント: " + Grading.hintFor(win.q) : ""
                                if (win.qmode === "wrong" || win.qmode === "drill") {
                                    const m = Grading.meaningFor(win.q)
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
                                    if (win.qmode === "right" || win.qmode === "wrong"
                                            || win.qmode === "drilled") {
                                        win.dismiss(true)        // second Enter: dismiss
                                        return
                                    }
                                    if (text.trim() === "") return
                                    if (win.qmode === "drill") {
                                        // re-typing the revealed answer; never recorded
                                        if (Grading.isCorrect(win.q, text)) win.qmode = "drilled"
                                        else shake.restart()
                                        return
                                    }
                                    if (win.grade(text)) {
                                        win.qmode = "right"
                                    } else if (win.drill) {
                                        win.qmode = "drill"
                                        text = ""
                                    } else {
                                        win.qmode = "wrong"
                                    }
                                }
                                // programmatic clears (drill) don't fire textEdited
                                onTextEdited: {
                                    win.noteInput()
                                    if (!inputMethodComposing && win.qmode === "ask"
                                            && win.committedValues.length < 200)
                                        win.committedValues.push(text)
                                }
                                onPreeditTextChanged: if (preeditText.length > 0) win.noteInput()
                                Keys.onEscapePressed: win.tryClose()
                                // F1 toggles the hint (mozc claims Ctrl+H and Tab)
                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_F1) {
                                        win.hintShown = !win.hintShown
                                        if (win.hintShown) win.hintEverShown = true
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
                            text: win.qmode === "ask"   ? "Enter でこたえる ・ F1 でヒント"
                                : win.qmode === "drill" ? "こたえを うちこんで Enter"
                                                        : "Enter か Esc でとじる"
                            // same hint toggle by mouse, for when the IME has the keyboard
                            MouseArea {
                                anchors.fill: parent
                                enabled: win.qmode === "ask"
                                onClicked: {
                                    win.hintShown = !win.hintShown
                                    if (win.hintShown) win.hintEverShown = true
                                }
                            }
                        }
                    }
                }
            }
    }
}
