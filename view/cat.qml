import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "grading.js" as Grading
import "spin.js" as Spin

// Bromodachi v3 view: a persistent cat living along the bottoms of the screens.
// The daemon is the brain; this is only the face. It stays up for the whole
// session and the daemon supervises it (src/view.rs, CatHost).
//
// World: every monitor, in Hyprland's global layout coordinates. Each monitor's
// bottom edge is a floor; a side edge is open where another monitor continues
// it, a wall where nothing does. There is exactly one cat (`cat`, `win`), and
// each monitor gets a full-screen transparent Overlay layer that only draws
// it: whichever monitor the cat is over draws it, so it can be dragged,
// thrown, or walk across. Each layer's input mask is just the cat, so the
// rest of every screen is click-through; the cat never takes the keyboard.
//
// Travel: now and then (and when a question arrives on another monitor) the
// cat walks to the side edge facing where it is going and jumps off. If a
// monitor continues that edge, the arc carries it across; if not, it leaps
// into the destination from the side nearest where it left. Some switches
// are a substitution jutsu instead (hand seal, ドロン, a log left behind, and
// the cat pops out of a puff of smoke on the other monitor), and some a surf:
// a wave swells up under it and it rides along the bottoms of the monitors
// in an open aloha shirt until the wave breaks.
//
// Contract with the daemon (same files the old popup wrote):
//   in   qs -p view/cat.qml ipc call cat ask <question json> <out prefix> <drill 1|0> <monitor>
//          (<monitor> = the one the user is working on: the cat goes there)
//        qs -p view/cat.qml ipc call cat retract     (withdraw; nothing recorded)
//        env BUDDY_CAT_SCREEN at spawn: the monitor to wake up on
//        qs -p view/cat.qml ipc call cat hurry       (summoned: cut the trip short)
//   out  <out>.ready   {"input_x","input_y","window_*","focused"} once the bubble
//                      lands, rewritten whenever it moves, resizes or gains/loses keys
//        <out>.result  written the moment the first answer is graded
//        <out>.done    written when the bubble is dismissed (not on retract)
// Sprites: assets/cat/cat_sheet_3x.png from assets/make_cat.py.
ShellRoot {
    id: shell

    // -------------------------------------------------------------- world
    readonly property var rects: {
        const s = Quickshell.screens, r = []
        for (let i = 0; i < s.length; i++)
            r.push({ name: s[i].name, x: s[i].x, y: s[i].y, w: s[i].width, h: s[i].height, screen: s[i] })
        return r
    }

    // Any change to the monitor set or layout restarts the cat. A layer
    // bound to a screen that went away (dock re-plugged, outputs coming back
    // as new screens after sleep) stays unmapped while the process lives on:
    // the cat vanished for hours holding a question nobody could see
    // (2026-09-25). The daemon respawns it within 5 s, and the generation
    // bump ends any pop in flight, unrecorded.
    property bool booted: false
    property var bootRects: []
    onRectsChanged: {
        if (!booted) return
        const a = rects, b = bootRects
        const same = a.length === b.length && a.every(function (r, i) {
            return r.screen === b[i].screen && r.x === b[i].x && r.y === b[i].y
                && r.w === b[i].w && r.h === b[i].h
        })
        if (!same) Qt.quit()
    }

    function screenAt(px, py) {
        for (let i = 0; i < rects.length; i++) {
            const r = rects[i]
            if (px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h) return i
        }
        return -1
    }
    function indexOf(name) {
        for (let i = 0; i < rects.length; i++)
            if (rects[i].name === name) return i
        return -1
    }
    function floorY(i) { return rects[i].y + rects[i].h - win.catH }
    // the monitor continuing monitor i past its side (dir -1 left, +1 right)
    // with room for the whole cat at height y; -1 = a wall there
    function sideNeighbor(i, dir, y) {
        const a = rects[i]
        for (let j = 0; j < rects.length; j++) {
            const b = rects[j]
            if (j === i) continue
            const touching = dir < 0 ? Math.abs(b.x + b.w - a.x) <= 2 : Math.abs(b.x - (a.x + a.w)) <= 2
            if (touching && b.y <= y + 0.5 && y + win.catH <= b.y + b.h + 0.5) return j
        }
        return -1
    }
    // any monitor touching that side at all (for sizing a jump across)
    function touchingSide(i, dir) {
        const a = rects[i]
        for (let j = 0; j < rects.length; j++) {
            const b = rects[j]
            if (j === i) continue
            const touching = dir < 0 ? Math.abs(b.x + b.w - a.x) <= 2 : Math.abs(b.x - (a.x + a.w)) <= 2
            if (touching && b.y < a.y + a.h && b.y + b.h > a.y) return j
        }
        return -1
    }
    // the monitor directly above (dir -1) or below (+1) monitor i at column px
    function vertNeighbor(i, dir, px) {
        const a = rects[i]
        for (let j = 0; j < rects.length; j++) {
            const b = rects[j]
            if (j === i) continue
            const touching = dir < 0 ? Math.abs(b.y + b.h - a.y) <= 2 : Math.abs(b.y - (a.y + a.h)) <= 2
            if (touching && px >= b.x && px < b.x + b.w) return j
        }
        return -1
    }

    Component.onCompleted: {
        // wake up where the daemon says the user is, else on an external monitor
        let i = indexOf(Quickshell.env("BUDDY_CAT_SCREEN") || "")
        for (let j = 0; i < 0 && j < rects.length; j++)
            if (rects[j].name.indexOf("eDP") !== 0) i = j
        win.cur = Math.max(0, i)
        if (rects.length > 0) {
            const r = rects[win.cur]
            cat.x = r.x + r.w - win.catW - 160
            cat.y = floorY(win.cur)
        }
        bootRects = rects
        booted = true
        win.setMode("sleep")
        win.play(cat.anim)  // the first mode is set before anyone is listening
    }

    // ---------------------------------------------------------- the cat
    // position (global, top-left of the 96x72 cell) and pose; every monitor's
    // window draws from this
    Scope {
        id: cat
        property real x: 0
        property real y: 0
        readonly property real width: win.catW
        readonly property real height: win.catH
        property int facing: 1
        property real grabX: width / 2
        property real grabY: 0
        property real sway: 0
        property real spin: 0

        // mode -> row of assets/cat/cat_sheet_3x.png (make_cat.py). The
        // wallslide art hugs the right edge of its cell, so on the left
        // wall the facing flip puts it flush against that wall too
        readonly property var anim: {
            const m = { wake: "stretch", land: "stand", laptopopen: "laptop_open",
                        laptoplook: "laptop_look", laptopclose: "laptop_close",
                        jump: "leap", transit: "leap", seal: "ninja_seal",
                        crouch: "ninja_crouch", poofed: "ninja_seal", surfgone: "surf",
                        brace: "stand" }[win.mode] || win.mode
            return win.anims[m] || win.anims["sit"]
        }
        onAnimChanged: win.play(anim)
    }

    // ------------------------------------------------------ the brain
    Scope {
        id: win

        // ------------------------------------------------------ tunables
        readonly property real catW: 96      // 32 px sprite at 3x
        readonly property real catH: 72      // 24 px sprite at 3x
        readonly property real gravity: 2600 // px/s^2
        readonly property real walkSpeed: 70 // px/s
        readonly property real runSpeed: 420 // px/s, hurrying over for a question
        readonly property real stickSpeed: 450 // min wall-hit speed to cling, px/s
        readonly property real slideAccel: 260 // px/s^2 down the wall
        readonly property real slideMax: 420   // px/s
        // throwing it away takes a wind-up (spin.js: two circles, then the
        // throw, in one smooth motion) and then an upward fling this fast,
        // px/s. Without the wind-up even a hard fling just bounces
        readonly property real launchSpeed: 900
        // the jump in from a side edge: ~0.65 s arc, ~140 px high, landing ~225 px inside
        readonly property real leapVx: 490
        readonly property real leapVy: 850
        // jumping off a side edge on a trip: takes off this far from the
        // edge, this fast, this high above any ledge it has to clear
        // (simulated 2026-09-25: clears the ASUS's 152 px step with ~80 to spare)
        readonly property real edgeGap: 70
        readonly property real hopVx: 380
        readonly property real hopClear: 90
        // how a monitor switch goes ("only when it switches screens, not
        // every time"): a substitution jutsu this often, a surf this often,
        // otherwise a walk and a jump
        readonly property real jutsuChance: 0.3
        readonly property real surfChance: 0.3
        readonly property real surfSpeed: 360  // px/s along the bottoms of the monitors
        readonly property real surfRush: 560   // ...on the way to a question
        // the wave's cell, and where the board meets it (make_cat.py, 3x)
        readonly property var surfGeo: anims["_surf"]
        readonly property real waveW: surfGeo.wave[0] * 3
        readonly property real waveH: surfGeo.wave[1] * 3
        readonly property real rideX: surfGeo.ride[0] * 3
        readonly property real rideY: surfGeo.ride[1] * 3
        readonly property real boardX: surfGeo.board[0] * 3
        readonly property real boardY: surfGeo.board[1] * 3
        readonly property string assetsDir: {
            const u = Qt.resolvedUrl(".").toString().replace("file://", "")
            return u.replace(/\/view\/?$/, "") + "/assets"
        }
        // animation table written by assets/make_cat.py
        FileView { id: animFile; path: win.assetsDir + "/cat/cat_sheet.json"; blockLoading: true }
        readonly property var anims: JSON.parse(animFile.text())

        // --------------------------------------------------------- state
        // sleep | wake | walk | sit | held | fall | wallslide | land | alert
        // | launched (thrown off the top) | gone (hidden until the next ask)
        // | leap (jumping in from a side edge) | run (hurrying to a question)
        // | jump (off a side edge, on a trip) | transit (between monitors)
        // | seal / poofed / crouch (substitution jutsu: before, gone, after)
        // | surf (on the wave) / surfgone (rode off into open air)
        // | brace (standing still for the instant a jutsu or surf gets going)
        // | laptopopen / laptop / laptoplook / laptopclose (idle: typing away)
        property string mode: "sleep"
        property int cur: 0          // the monitor the cat is on
        property real vx: 0
        property real vy: 0
        property real walkTo: 0
        // a trip to another monitor: where to, how fast, and whether the
        // jump off the edge is in flight (that edge is open while it is)
        property int tripTo: -1
        property bool tripRun: false
        property int tripDir: 0
        property bool tripJumping: false
        property int tripHops: 0
        // lost after a few hops: the next jump goes straight to the destination
        property bool tripDirect: false
        property real exitX: 0       // where it left the desk, for the jump back in
        property int leapTo: 0       // the monitor a leap lands on
        // on its way to a question: the bubble waits for the landing
        property bool entering: false
        // when the current laptop session wraps up (ms since epoch)
        property real laptopUntil: 0
        // resting states a question interrupts: the cat drops them and looks up
        readonly property var idleModes: ["sleep", "sit", "wake", "walk", "land",
                                          "laptopopen", "laptop", "laptoplook", "laptopclose"]
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
            if (asking && !entering && m !== "land" && idleModes.indexOf(m) >= 0) m = "alert"
            mode = m
            // how long each resting state lasts before the next decision
            if (m === "sleep") idle.interval = 40000 + Math.random() * 80000
            else if (m === "sit") idle.interval = 4000 + Math.random() * 6000
            else if (m === "wake") idle.interval = 1200
            else if (m === "land") idle.interval = tripRun ? 250 : 700
            else if (m === "transit") idle.interval = 350
            else if (m === "laptopopen" || m === "laptopclose") idle.interval = 650
            else if (m === "laptop") idle.interval = 3000 + Math.random() * 4000
            else if (m === "laptoplook") idle.interval = 1500
            else return idle.stop()
            idle.restart()
        }

        // ------------------------------------------------------- travel
        function beginTrip(j, run) {
            tripTo = j
            tripRun = run
            tripHops = 0
            travel(j)
        }

        // how to get to monitor j this time: jutsu, surf, or walk and jump
        function travel(j) {
            const r = Math.random()
            if (r < jutsuChance) beginJutsu(j)
            else if (r < jutsuChance + surfChance) beginSurf(j)
            else tripStep()
        }

        // which side edge of monitor i leads to monitor j: one j continues;
        // else the one facing it; else, for a monitor above or below, the
        // one with open air past it (that leads straight there)
        function exitDir(i, j) {
            const s = shell.rects[i], t = shell.rects[j]
            const scx = s.x + s.w / 2, tcx = t.x + t.w / 2
            const nL = shell.touchingSide(i, -1), nR = shell.touchingSide(i, 1)
            if (nL === j) return -1
            if (nR === j) return 1
            if (Math.abs(tcx - scx) > s.w / 4) return Math.sign(tcx - scx)
            if ((nL < 0) !== (nR < 0)) return nL < 0 ? -1 : 1
            return cat.x + catW / 2 < scx ? -1 : 1
        }

        // ---------------------------------------------------- surfing
        property int surfTo: -1
        property int surfDir: 1
        property string wavePhase: ""  // swell | ride | break; "" = no wave
        property int waveFrame: 0
        property real waveX: 0         // where the board's middle is (global x)
        property real waveFloor: 0     // the floor the wave rolls on (global y)
        property real waveRise: 1      // 0 -> 1 while it swells up under the cat
        property real surfClock: 0
        property bool surfArrived: false
        property real surfStopX: 0
        function surfing() {
            // (surfEnd runs on a little after the hop-off; by then it's just a landing)
            return mode === "surf" || mode === "surfgone" || surfStart.running || (surfEnd.running && mode === "surf")
        }
        function beginSurf(j) {
            setMode("brace")
            surfTo = j
            tripTo = j
            tripJumping = false
            vx = 0; vy = 0
            surfDir = exitDir(cur, j)
            surfStart.restart()
        }
        function setWave(phase) {
            wavePhase = phase
            waveFrame = 0
            if (phase !== "") waveStepper.restart()
            else waveStepper.stop()
        }
        // the cat on its board, on the wave's face (or rising with the swell)
        function placeRider() {
            const standing = waveFloor - catH + boardY          // board height on the floor
            const riding = waveFloor - waveH + rideY + Math.sin(surfClock * 5) * 2
            cat.facing = surfDir
            cat.x = waveX - (surfDir > 0 ? boardX : catW - boardX)
            cat.y = standing + (riding - standing) * waveRise - boardY
        }
        function stepSurf(dt) {
            surfClock += dt
            if (wavePhase === "ride") {
                waveX += surfDir * (tripRun ? surfRush : surfSpeed) * dt
                const s = shell.rects[cur]
                const edge = surfDir > 0 ? s.x + s.w : s.x
                if (surfDir > 0 ? waveX >= edge : waveX <= edge) {
                    const n = shell.touchingSide(cur, surfDir)
                    const nb = n >= 0 ? shell.rects[n].y + shell.rects[n].h : 0
                    // a wave drops any distance, but only climbs so far
                    if (n >= 0 && (s.y + s.h) - nb < 400) {
                        // on into the next monitor: the wave surges up or drops to its floor
                        cur = n
                        floorShift.to = nb
                        floorShift.restart()
                    } else if (surfDir > 0 ? waveX - rideX > edge : waveX + rideX < edge) {
                        // rode off into open air, wave and all: come in on the destination
                        exitX = waveX
                        setWave("")
                        setMode("surfgone")
                        surfTransit.restart()
                        return
                    }
                }
                if (cur === surfTo && !surfArrived) {
                    surfArrived = true
                    surfStopX = surfStop()
                }
                if (surfArrived && (surfDir > 0 ? waveX >= surfStopX : waveX <= surfStopX)) {
                    setWave("break")
                    surfEnd.restart()
                }
            }
            placeRider()
        }
        // somewhere 30-70% across the destination, but a decent ride on it
        function surfStop() {
            const t = shell.rects[cur]
            const f = 0.3 + Math.random() * 0.4
            if (surfDir > 0)
                return Math.min(Math.max(t.x + t.w * f, waveX + 250), t.x + t.w - 150)
            return Math.max(Math.min(t.x + t.w * (1 - f), waveX - 250), t.x + 150)
        }
        // ride in on monitor j from a side edge (see entrySide)
        function surfEnter(j, fromX) {
            const t = shell.rects[j]
            const fromLeft = entrySide(j, fromX)
            surfDir = fromLeft ? 1 : -1
            cur = j
            floorShift.stop()
            waveFloor = t.y + t.h
            waveX = fromLeft ? t.x - 60 : t.x + t.w + 60
            waveRise = 1
            surfArrived = false
            setWave("ride")
            setMode("surf")
            placeRider()
        }
        SequentialAnimation {
            id: surfStart
            ScriptAction {
                script: {
                    const r = shell.rects[win.cur]
                    win.waveFloor = r.y + r.h
                    win.waveX = cat.x + (win.surfDir > 0 ? win.boardX : win.catW - win.boardX)
                    win.waveRise = 0
                    win.surfClock = 0
                    win.surfArrived = false
                    win.setWave("swell")
                    win.puff(puffA, cat.x, cat.y, false, "splash")
                }
            }
            PauseAnimation { duration: 120 }
            ScriptAction { script: win.setMode("surf") }  // shirt and board, under the splash
            NumberAnimation { target: win; property: "waveRise"; from: 0; to: 1; duration: 450; easing.type: Easing.OutQuad }
            ScriptAction { script: win.setWave("ride") }
        }
        SequentialAnimation {
            id: surfEnd
            PauseAnimation { duration: 160 }
            ScriptAction { script: win.puff(puffB, cat.x, cat.y, false, "splash") }
            PauseAnimation { duration: 110 }
            // hops off as its normal self; the landing finishes the trip
            ScriptAction { script: { win.surfTo = -1; win.vx = win.surfDir * 140; win.vy = -260; win.setMode("fall") } }
            PauseAnimation { duration: 350 }
            ScriptAction { script: win.setWave("") }
        }
        NumberAnimation { id: floorShift; target: win; property: "waveFloor"; duration: 300; easing.type: Easing.InOutQuad }
        Timer { id: surfTransit; interval: 300; onTriggered: win.surfEnter(win.surfTo, win.exitX) }
        Timer {
            id: waveStepper
            interval: win.wavePhase !== "" ? 1000 / win.anims["wave_" + win.wavePhase].fps : 1000
            repeat: true
            onTriggered: {
                const a = win.anims["wave_" + win.wavePhase]
                if (!a) return stop()
                if (a.loop) win.waveFrame = (win.waveFrame + 1) % a.frames
                else if (win.waveFrame < a.frames - 1) win.waveFrame++
                else stop()
            }
        }
        // grabbed off the board: the wave breaks on its own and is gone
        function dropWave() {
            surfStart.stop()
            surfEnd.stop()
            surfTransit.stop()
            surfTo = -1
            if (wavePhase !== "") {
                setWave("break")
                waveGone.restart()
            }
        }
        Timer { id: waveGone; interval: 450; onTriggered: win.setWave("") }

        // ------------------------------------------ substitution jutsu
        property int jutsuTo: -1
        property real jutsuX: 0   // where it pops out (global x)
        function beginJutsu(j) {
            setMode("brace")  // whatever it was doing stops now, not 110 ms in
            jutsuTo = j
            tripTo = j
            tripJumping = false
            vx = 0; vy = 0
            jutsuX = jutsuSpot(j)
            jutsu.restart()
        }
        // somewhere in the middle 60% of the monitor
        function jutsuSpot(j) {
            const t = shell.rects[j]
            return t.x + t.w * (0.2 + Math.random() * 0.6) - catW / 2
        }
        function jutsuAppear() {
            const t = shell.rects[jutsuTo]
            cur = jutsuTo
            cat.x = jutsuX
            cat.y = shell.floorY(jutsuTo)
            cat.facing = cat.x + catW / 2 < t.x + t.w / 2 ? 1 : -1  // face into the screen
            puff(puffB, cat.x, cat.y, true)
        }
        SequentialAnimation {
            id: jutsu
            // costume on
            ScriptAction { script: win.puff(puffA, cat.x, cat.y, false) }
            PauseAnimation { duration: 110 }
            ScriptAction { script: win.setMode("seal") }
            PauseAnimation { duration: 700 }
            // ドロン: behind the thickest frame of the cloud, the cat becomes a log
            ScriptAction { script: win.puff(puffA, cat.x, cat.y, true) }
            PauseAnimation { duration: 170 }
            ScriptAction {
                script: {
                    win.logX = cat.x
                    win.logY = cat.y
                    logLife.restart()
                    win.setMode("poofed")
                }
            }
            PauseAnimation { duration: 350 }
            // ...and pops out of another cloud over there
            ScriptAction { script: win.jutsuAppear() }
            PauseAnimation { duration: 170 }
            ScriptAction { script: win.setMode("crouch") }
            PauseAnimation { duration: 750 }
            // costume off
            ScriptAction { script: win.puff(puffB, cat.x, cat.y, false) }
            PauseAnimation { duration: 110 }
            ScriptAction { script: { win.jutsuTo = -1; win.land(0.2) } }
        }

        // smoke puffs: A where it leaves, B where it arrives. t runs 0 -> 1;
        // a big puff spends its first 40% on the smoke and the rest letting
        // the ドロン float away
        QtObject { id: puffA; property real x; property real y; property real t: 1; property bool big; property string kind: "smoke" }
        QtObject { id: puffB; property real x; property real y; property real t: 1; property bool big; property string kind: "smoke" }
        readonly property var puffs: [puffA, puffB]
        NumberAnimation { id: puffAAnim; target: puffA; property: "t"; from: 0; to: 1; duration: puffA.big ? 900 : 260 }
        NumberAnimation { id: puffBAnim; target: puffB; property: "t"; from: 0; to: 1; duration: puffB.big ? 900 : 260 }
        // kind: "smoke" (jutsu) or "splash" (surf)
        function puff(p, x, y, big, kind) {
            p.x = x
            p.y = y
            p.big = big
            p.kind = kind || "smoke"
            ;(p === puffA ? puffAAnim : puffBAnim).restart()
        }

        // the log left behind: rocks as it lands, sits a while, fades
        property real logX: 0
        property real logY: 0
        property int logFrame: 0
        property real logOpacity: 0
        SequentialAnimation {
            id: logLife
            PropertyAction { target: win; property: "logOpacity"; value: 1 }
            PropertyAction { target: win; property: "logFrame"; value: 1 }
            PauseAnimation { duration: 110 }
            PropertyAction { target: win; property: "logFrame"; value: 2 }
            PauseAnimation { duration: 110 }
            PropertyAction { target: win; property: "logFrame"; value: 1 }
            PauseAnimation { duration: 110 }
            PropertyAction { target: win; property: "logFrame"; value: 0 }
            PauseAnimation { duration: 3600 }
            NumberAnimation { target: win; property: "logOpacity"; to: 0; duration: 600 }
        }

        // set off toward monitor tripTo: walk (or run) to a side edge and
        // jump off it (tripJump, on arrival). Which edge: one the destination
        // continues; else the one facing it; else, for a monitor above or
        // below, the one with open air past it (that jump goes straight there)
        function tripStep() {
            const s = shell.rects[cur]
            tripDir = exitDir(cur, tripTo)
            tripDirect = ++tripHops > 3
            walkTo = tripDir < 0 ? s.x + edgeGap : s.x + s.w - catW - edgeGap
            setMode(tripRun ? "run" : "walk")
        }

        function tripJump() {
            const s = shell.rects[cur]
            // a monitor continuing this edge with a higher floor: jump high
            // enough to land on it; otherwise just hop off
            let rise = 0
            const n = shell.touchingSide(cur, tripDir)
            if (n >= 0) {
                const up = (s.y + s.h) - (shell.rects[n].y + shell.rects[n].h)
                if (up > 0 && up < 700) rise = up
            }
            tripJumping = true
            cat.facing = tripDir
            vy = -Math.sqrt(2 * gravity * (rise + hopClear))
            // a climb crosses the edge near the top of its arc, so a big one
            // goes slower (air drag in stepFall: vx *= 0.4 per second)
            const k = -Math.log(0.4), t = -vy / gravity * 0.85
            vx = tripDir * (rise > 0 ? (edgeGap + catW / 2 + 10) * k / (1 - Math.exp(-k * t)) : hopVx)
            setMode("jump")
        }

        // walked or jumped somewhere; true = it left for the destination
        function updateCur() {
            const i = shell.screenAt(cat.x + catW / 2, cat.y + catH / 2)
            // a jump off the edge into open air (or, after too many hops,
            // any jump off the edge) reappears on the destination
            if (tripJumping && (i < 0 || (tripDirect && i !== cur))) {
                exitX = cat.x + catW / 2
                tripJumping = false
                setMode("transit")
                return true
            }
            if (i >= 0 && i !== cur) {
                cur = i
                tripJumping = false   // made it across: that edge is solid again
            }
            return false
        }

        // The side to come in on monitor i from: the one nearer `fromX`,
        // unless starting there would hang the cat in mid-air over another
        // monitor (one whose floor is at a different height) and the far
        // side is clear. True = from the left.
        function entrySide(i, fromX) {
            const t = shell.rects[i]
            const near = Math.abs(fromX - t.x) <= Math.abs(fromX - (t.x + t.w))
            const clear = function (left) {
                const j = shell.screenAt(left ? t.x - catW / 2 : t.x + t.w + catW / 2, shell.floorY(i) + catH / 2)
                return j < 0 || Math.abs(shell.floorY(j) - shell.floorY(i)) < 20
            }
            return !clear(near) && clear(!near) ? !near : near
        }

        // jump in onto monitor i from a side edge (see entrySide)
        function leapInto(i, fromX) {
            const t = shell.rects[i]
            const fromLeft = entrySide(i, fromX)
            cur = i
            leapTo = i
            cat.spin = 0
            cat.facing = fromLeft ? 1 : -1
            cat.x = fromLeft ? t.x - catW : t.x + t.w
            cat.y = shell.floorY(i)
            vx = fromLeft ? leapVx : -leapVx
            vy = -leapVy
            setMode("leap")
        }

        // an edge the cat may pass right now (dir -1 left, +1 right)
        function passSide(dir) {
            if (asking && !entering) return false          // a question pins it to its monitor
            if (tripJumping && dir === tripDir) return true // jumping off on purpose
            return shell.sideNeighbor(cur, dir, cat.y) >= 0
        }

        function land(impact) {
            cat.y = shell.floorY(cur)
            squash.impact = impact
            squash.restart()
            vx = 0; vy = 0
            tripJumping = false
            setMode("land")
            if (entering && (tripTo < 0 || cur === tripTo)) arriveForQuestion()
        }

        Timer {
            id: idle
            onTriggered: {
                if (win.mode === "sleep") {
                    win.setMode("wake")
                } else if (win.mode === "wake") {
                    // now and then, go see another monitor
                    if (!win.asking && shell.rects.length > 1 && Math.random() < 0.25) {
                        let j = Math.floor(Math.random() * (shell.rects.length - 1))
                        if (j >= win.cur) j++
                        return win.beginTrip(j, false)
                    }
                    // wander somewhere 120..600 px away, staying on this monitor
                    const r = shell.rects[win.cur]
                    const d = (120 + Math.random() * 480) * (Math.random() < 0.5 ? -1 : 1)
                    win.walkTo = Math.max(r.x, Math.min(r.x + r.w - win.catW, cat.x + d))
                    win.setMode("walk")
                } else if (win.mode === "sit") {
                    const r = Math.random()
                    if (r < 0.25) {
                        // pull out the laptop for a 15-40 s work session
                        win.laptopUntil = Date.now() + 15000 + Math.random() * 25000
                        win.setMode("laptopopen")
                    } else {
                        win.setMode(r < 0.45 ? "wake" : "sleep")
                    }
                } else if (win.mode === "land") {
                    // a question that caught up with the landing itself
                    // (arriving in a surf's last moment, say) shows here
                    if (win.entering && (win.tripTo < 0 || win.tripTo === win.cur)) win.arriveForQuestion()
                    // mid-trip: on to the next edge
                    else if (win.tripTo >= 0 && win.tripTo !== win.cur) return win.tripStep()
                    win.tripTo = -1
                    win.tripRun = false
                    win.setMode("sit")
                } else if (win.mode === "transit") {
                    win.leapInto(win.tripTo >= 0 ? win.tripTo : win.cur, win.exitX)
                } else if (win.mode === "laptopopen" || win.mode === "laptoplook") {
                    win.setMode("laptop")
                } else if (win.mode === "laptop") {
                    // keep typing, now and then glance up at you, then pack up
                    if (Date.now() > win.laptopUntil) win.setMode("laptopclose")
                    else win.setMode(Math.random() < 0.35 ? "laptoplook" : "laptop")
                } else if (win.mode === "laptopclose") {
                    win.setMode("sit")
                }
            }
        }

        // physics + walking, one step per rendered frame
        FrameAnimation {
            running: ["fall", "jump", "walk", "run", "wallslide", "held", "launched", "leap", "surf"]
                     .indexOf(win.mode) >= 0
            onTriggered: {
                const dt = Math.min(frameTime, 0.05)
                if (win.mode === "held") return win.stepHeld(dt)
                if (win.mode === "walk" || win.mode === "run") return win.stepWalk(dt)
                if (win.mode === "launched") return win.stepLaunched(dt)
                if (win.mode === "leap") return win.stepLeap(dt)
                if (win.mode === "wallslide") return win.stepSlide(dt)
                if (win.mode === "surf") return win.stepSurf(dt)
                win.stepFall(dt)
            }
        }

        function stepHeld(dt) {
            // hand velocity/acceleration sampled once per frame: a still
            // mouse sends no events, and this still reads it as v = 0, so
            // the swing always settles
            const v = (handX - handPrevX) / Math.max(dt, 0.001)
            handPrevX = handX
            const vs = 0.5 * handV + 0.5 * v
            const a = Math.max(-30000, Math.min(30000, (vs - handV) / Math.max(dt, 0.001)))
            handV = vs
            // body lags the hand: accelerate right -> swing left
            const acc = (a / swayLen) * Math.cos(swayAng)
                      - (gravity / swayLen) * Math.sin(swayAng)
                      - swayDamp * swayVel
            swayVel += acc * dt
            swayAng += swayVel * dt
            if (Math.abs(swayAng) > 1.0) {
                swayAng = Math.sign(swayAng) * 1.0
                swayVel = 0
            }
            cat.sway = swayAng * 180 / Math.PI
            // throw speed is measured from events; forget it once the hand
            // has been still for a moment
            if (Date.now() - lastMouseT > 25) {
                const k = Math.pow(0.001, dt)
                vx *= k
                vy *= k
            }
        }

        function stepWalk(dt) {
            const s = shell.rects[cur]
            const speed = mode === "run" ? runSpeed : walkSpeed
            const dir = Math.sign(walkTo - cat.x)
            cat.facing = dir < 0 ? -1 : 1
            let nx = cat.x + dir * speed * dt
            let blocked = false
            if (nx < s.x && !passSide(-1)) { nx = s.x; blocked = true }
            if (nx > s.x + s.w - catW && !passSide(1)) { nx = s.x + s.w - catW; blocked = true }
            // don't overshoot the spot
            if ((dir > 0 && nx > walkTo) || (dir < 0 && nx < walkTo)) nx = walkTo
            cat.x = nx
            updateCur()
            if (cat.y < shell.floorY(cur) - 0.5) {
                // walked off a ledge onto a lower monitor
                vx = dir * speed
                vy = 0
                setMode("fall")
                return
            }
            if (Math.abs(walkTo - cat.x) < 1 || blocked) {
                if (tripTo >= 0 && tripTo !== cur) tripJump()
                else setMode("sit")
            }
        }

        function stepLaunched(dt) {
            // blasting off: no gravity, spinning, straight out the top of
            // the desk. Clipping a side wall on the way up spoils it: it
            // falls back into normal physics (bounce, or cling and slide)
            const s = shell.rects[cur]
            const nx = cat.x + vx * dt
            if ((nx < s.x && !passSide(-1)) || (nx > s.x + s.w - catW && !passSide(1))) {
                cat.x = Math.max(s.x, Math.min(s.x + s.w - catW, nx))
                cat.spin = 0
                setMode("fall")
                return
            }
            cat.x = nx
            cat.y += vy * dt
            cat.spin += 900 * dt
            updateCur()  // flying up into the monitor above, if there is one
            const top = shell.rects[cur]
            if (cat.y < top.y - catH - 20 && shell.vertNeighbor(cur, -1, cat.x + catW / 2) < 0) {
                twinkleX = cat.x + catW / 2
                twinkleY = top.y + 4
                twinkleAnim.restart()
                setMode("gone")
            }
        }

        function stepLeap(dt) {
            // a plain ballistic arc from beyond the side edge; no walls,
            // since it starts off-screen
            vy += gravity * dt
            cat.x += vx * dt
            cat.y += vy * dt
            if (vy > 0 && cat.y >= shell.floorY(leapTo)) {
                cur = leapTo
                land(0.45)
            }
        }

        function stepSlide(dt) {
            // claws dragging down the wall: slow start, gentle speed-up
            vy = Math.min(vy + slideAccel * dt, slideMax)
            cat.y += vy * dt
            if (cat.y >= shell.floorY(cur)) land(0.25)
        }

        function stepFall(dt) {
            const s = shell.rects[cur]
            const prevY = cat.y
            vy += gravity * dt
            vx *= Math.pow(0.4, dt) // air drag
            let nx = cat.x + vx * dt
            let hit = 0
            if (nx < s.x && !passSide(-1)) { nx = s.x; hit = -1 }
            else if (nx > s.x + s.w - catW && !passSide(1)) { nx = s.x + s.w - catW; hit = 1 }
            cat.x = nx
            let ny = cat.y + vy * dt
            // a question pins it to its monitor, up and down as well as sideways
            const pinned = asking && !entering
            // bonk the top edge, unless a monitor continues above
            if (ny < s.y && vy < 0 && (pinned || shell.vertNeighbor(cur, -1, cat.x + catW / 2) < 0)) {
                ny = s.y
                vy = -vy * 0.3
            }
            cat.y = ny
            if (hit !== 0) {
                // a hard hit high up the wall: grab on and slide down it.
                // anything softer (or near the floor) just bounces off
                if (Math.abs(vx) > stickSpeed && cat.y < shell.floorY(cur) - catH) {
                    cat.facing = hit
                    vx = 0
                    vy = Math.max(0, Math.min(vy, 60))
                    setMode("wallslide")
                    return
                }
                vx = -vx * 0.4
                faceTravel()
            }
            if (updateCur()) return
            // floors hold from above; coming up through one from the
            // monitor below passes, and there is no falling out of the desk
            const fy = shell.floorY(cur)
            if (cat.y >= fy && ((vy > 0 && prevY <= fy + 1) || pinned
                    || shell.vertNeighbor(cur, 1, cat.x + catW / 2) < 0))
                land(Math.min(Math.max(vy, 0) / 2500, 1))
        }

        // --------------------------------------------------- sprite clock
        // The sheet is ONE static texture; a frame is just the sheet shifted
        // under a clip. (AnimatedSprite rebuilt its texture on every change
        // and drew nothing while it did: a blank-frame flicker on each mode
        // change, worst after a throw, which changes mode several times in a
        // second.) One clock here; every monitor's copy reads it.
        property int frame: 0
        property var shown: null
        function play(a) {
            if (a === shown) return  // same animation: keep its rhythm
            shown = a
            frame = 0
            if (a.frames > 1) stepper.restart()
            else stepper.stop()
        }
        Timer {
            id: stepper
            interval: 1000 / cat.anim.fps
            repeat: true
            onTriggered: {
                const a = cat.anim
                if (a.loop) win.frame = (win.frame + 1) % a.frames
                else if (win.frame < a.frames - 1) win.frame++
                else stop()  // one-shot (stretch, leap, lid): hold the last frame
            }
        }

        // zzz drifting up while asleep
        property real zzz: 0
        NumberAnimation on zzz {
            from: 0; to: 1; duration: 2400
            loops: Animation.Infinite
            running: win.mode === "sleep"
        }

        // the little star left at the top of the desk on a blast-off
        property real twinkleX: 0
        property real twinkleY: 0
        property real twinkle: 0
        NumberAnimation on twinkle { id: twinkleAnim; running: false; from: 0; to: 1; duration: 650 }

        // landing squash: amount goes impact -> 0 with a little bounce
        SequentialAnimation {
            id: squash
            property real impact: 0.5
            property real amount: 0
            NumberAnimation { target: squash; property: "amount"; to: squash.impact * 0.35; duration: 60 }
            NumberAnimation { target: squash; property: "amount"; to: -0.08 * squash.impact; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: squash; property: "amount"; to: 0; duration: 180; easing.type: Easing.OutBounce }
        }

        // ------------------------------------------------------- dragging
        // (called by whichever monitor's copy was grabbed; points are global)
        function grab(px, py) {
            // picked up by the scruff: the cat hops so the nape of the held
            // (face-on) sprite is right under the cursor
            if (!entering) tripTo = -1
            tripJumping = false
            if (jutsu.running) { jutsu.stop(); jutsuTo = -1 }
            if (surfing()) dropWave()
            cat.grabX = catW / 2
            cat.grabY = 6
            moveHeld(px, py)
            vx = 0; vy = 0
            lastMouseT = Date.now()
            lastMouseX = px
            lastMouseY = py
            handX = px; handPrevX = px; handV = 0
            swayAng = 0; swayVel = 0; cat.sway = 0
            squash.stop(); squash.amount = 0
            spin = Spin.fresh(px, py, lastMouseT)
            setMode("held")
        }
        property var spin: Spin.fresh(0, 0, 0)
        function drag(px, py) {
            if (mode !== "held") return
            const now = Date.now()
            const dt = Math.max((now - lastMouseT) / 1000, 0.008)
            // keep a smoothed throw velocity; sway opposite to the motion
            vx = 0.6 * vx + 0.4 * (px - lastMouseX) / dt
            vy = 0.6 * vy + 0.4 * (py - lastMouseY) / dt
            lastMouseX = px
            lastMouseY = py
            lastMouseT = now
            handX = px
            Spin.track(spin, px, py, now, Math.sqrt(vx * vx + vy * vy))
            moveHeld(px, py)
        }
        function moveHeld(px, py) {
            // follow the hand across monitors; the cat stays on whichever
            // one the hand is over (a question pins it to its own)
            let i = asking && !entering ? cur : shell.screenAt(px, py)
            if (i < 0) i = cur
            const r = shell.rects[i]
            cur = i
            if (asking && !entering) {
                cat.x = Math.max(r.x, Math.min(r.x + r.w - catW, px - cat.grabX))
                cat.y = Math.max(r.y, Math.min(shell.floorY(i), py - cat.grabY))
            } else {
                cat.x = Math.max(r.x - catW / 2, Math.min(r.x + r.w - catW / 2, px - cat.grabX))
                cat.y = Math.max(r.y - catH / 2, Math.min(shell.floorY(i), py - cat.grabY))
            }
        }
        function release() {
            if (mode !== "held") return
            // a hand that stopped before letting go throws nothing
            if (Date.now() - lastMouseT > 80) { vx = 0; vy = 0 }
            // cap throws so a flick cannot launch it into orbit
            vx = Math.max(-3000, Math.min(3000, vx))
            vy = Math.max(-2600, Math.min(2600, vy))
            faceTravel()
            // put down on its way to a question: ask from wherever it lands
            if (entering) tripTo = -1
            // wound up with two circles and flung upward in the same
            // motion, no question up: off it goes until the next one
            if (Spin.charged(spin, Date.now()) && vy < -launchSpeed && !asking) {
                cat.spin = 0
                setMode("launched")
                return
            }
            setMode("fall")
        }

        // -------------------------------------------------------- question
        property bool asking: false
        property var q: ({ prompt: "", answers: [""], hint: null, ja: true })
        property bool drill: false
        property string outPrefix: ""
        // "ask" -> waiting for an answer; "right"/"wrong"/"drilled" ->
        // feedback shown, dismissal allowed; "drill" -> wrong answer must
        // be typed out before leaving
        property string qmode: "ask"
        // the monitor the bubble is on; only changes while it is hidden
        property int askIdx: 0
        readonly property var askRect: shell.rects[askIdx] || shell.rects[0]
        // where the bubble window sits (monitor coords): above the cat's
        // head, clamped inside the monitor; the tail hangs below it
        readonly property real tailH: 26
        readonly property real catLX: cat.x - askRect.x
        readonly property real catLY: cat.y - askRect.y
        readonly property real bubbleX: Math.max(8, Math.min(askRect.w - 448 - 8, catLX + catW / 2 - 224))
        readonly property real bubbleY: Math.max(8, catLY - bubble.height - tailH)
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

        function startAsk(question, out, drillOn, screenName) {
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
            readySent = false
            readyPing.stop()  // one still pending from the last question would write its box
            closing.stop()
            // go to the monitor the user is working on
            const t = shell.indexOf(screenName)
            const target = t >= 0 ? t : cur
            if (surfing()) {
                // mid-ride: the wave runs its course (faster now), and the
                // landing carries on to the question's monitor if it isn't there
                entering = true
                asking = true
                tripTo = target
                tripRun = true
                tripHops = 0
                return
            }
            if (jutsu.running) {
                // mid-jutsu: still in the smoke, it just comes out over
                // there instead; already out, it goes on from where it is
                entering = true
                asking = true
                tripTo = target
                tripRun = true
                tripHops = 0
                if (mode !== "crouch") {
                    jutsuTo = target
                    jutsuX = jutsuSpot(target)
                }
                return
            }
            const away = mode === "gone" || mode === "launched" || mode === "transit"
            const willEnter = away || (mode !== "held" && target !== cur)
            // the bubble's monitor is settled before it can become visible
            if (!willEnter) askIdx = cur
            entering = willEnter
            asking = true
            // a jump already off the edge keeps its exit open and lands first
            if (mode !== "jump") tripJumping = false
            if (away) {
                // jump back in from the side nearer to where it left
                tripTo = target
                leapInto(target, cat.x + catW / 2)
                return
            }
            if (entering) {
                // hurry over: run to the edge and jump across. Mid-air it
                // lands first and the landing carries on with the trip
                tripTo = target
                tripRun = true
                tripHops = 0
                if (idleModes.indexOf(mode) >= 0 || mode === "alert" || mode === "run") travel(target)
                return
            }
            tripTo = -1
            if (idleModes.indexOf(mode) >= 0) setMode("alert")
            showBubble()
        }

        // Super+B while it is still on its way: drop the walk / jutsu / surf
        // and jump straight in on the question's monitor
        function hurry() {
            if (!asking) return "idle"
            if (!entering) return "here"
            if (mode === "held") return "held"
            const target = tripTo >= 0 ? tripTo : cur
            if (jutsu.running) { jutsu.stop(); jutsuTo = -1 }
            if (surfing()) dropWave()
            tripJumping = false
            tripTo = target
            leapInto(target, cat.x + catW / 2)
            return "ok"
        }

        // made it to the question's monitor: the bubble comes out here
        function arriveForQuestion() {
            askIdx = cur
            entering = false
            tripTo = -1
            tripRun = false
            showBubble()
        }

        function showBubble() {
            // shown now, not when the question arrived: the trip over isn't
            // time spent on it
            shownAtMs = Date.now()
            lastActiveTick = shownAtMs
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
            // written aside and renamed in: the daemon polls these files and
            // must never read one half-written
            Quickshell.execDetached(["python3", "-c",
                "import os, sys; t = sys.argv[1] + '.tmp'; open(t, 'w').write(sys.argv[2]); os.replace(t, sys.argv[1])",
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
                    win.tripRun = false
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
        // the daemon polls for this before warping the cursor (summon).
        // Kept current afterwards: a hint line or a wrong answer grows the
        // bubble upward and a drag moves it, and a stale position made
        // Super+B miss the box (2026-09-29). `focused` lets the daemon tell
        // "already in the box" from "cursor merely near the cat"
        property bool readySent: false
        function refreshReady() {
            if (asking && !entering && readySent) readyPing.restart()
        }
        onBubbleXChanged: refreshReady()
        onBubbleYChanged: refreshReady()
        Timer {
            id: readyPing
            interval: win.readySent ? 120 : 400
            onTriggered: {
                if (!win.asking || win.entering) return
                const local = input.mapToItem(null, input.width / 2, input.height / 2)
                const ip = { x: local.x + win.bubbleX, y: local.y + win.bubbleY }
                const x0 = Math.min(win.bubbleX, win.catLX), y0 = Math.min(win.bubbleY, win.catLY)
                const x1 = Math.max(win.bubbleX + bubble.width, win.catLX + win.catW)
                const y1 = Math.max(win.bubbleY + bubble.height, win.catLY + win.catH)
                const sx = win.askRect.x, sy = win.askRect.y
                win.writeJson(win.outPrefix + ".ready", {
                    input_x: Math.round(sx + ip.x),
                    input_y: Math.round(sy + ip.y),
                    window_x: Math.round(sx + x0),
                    window_y: Math.round(sy + y0),
                    window_w: Math.round(x1 - x0),
                    window_h: Math.round(y1 - y0),
                    focused: input.activeFocus,
                })
                win.readySent = true
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
            function ask(question: string, out: string, drill: string, screen: string): string {
                win.startAsk(JSON.parse(question), out, drill === "1", screen)
                return "ok"
            }
            function retract(): void {
                win.dismiss(false)
            }
            function hurry(): string {
                return win.hurry()
            }
            // start a laptop session now (idle only), for testing / fun
            function laptop(): string {
                if (win.asking || win.idleModes.indexOf(win.mode) < 0) return "busy: " + win.mode
                win.laptopUntil = Date.now() + 15000 + Math.random() * 25000
                win.setMode("laptopopen")
                return "ok"
            }
            // walk over to another monitor now (idle only), for testing / fun
            function visit(screen: string): string {
                const j = shell.indexOf(screen)
                if (j < 0) return "no monitor " + screen
                if (win.asking || win.idleModes.indexOf(win.mode) < 0) return "busy: " + win.mode
                if (j === win.cur) return "already there"
                win.beginTrip(j, false)
                return "ok"
            }
            // surf over to another monitor now (idle only)
            function surf(screen: string): string {
                const j = shell.indexOf(screen)
                if (j < 0) return "no monitor " + screen
                if (win.asking || win.idleModes.indexOf(win.mode) < 0) return "busy: " + win.mode
                if (j === win.cur) return "already there"
                win.tripTo = j
                win.tripRun = false
                win.tripHops = 0
                win.beginSurf(j)
                return "ok"
            }
            // substitution jutsu to another monitor now (idle only)
            function jutsu(screen: string): string {
                const j = shell.indexOf(screen)
                if (j < 0) return "no monitor " + screen
                if (win.asking || win.idleModes.indexOf(win.mode) < 0) return "busy: " + win.mode
                win.beginJutsu(j)
                return "ok"
            }
            function where(): string {
                const r = shell.rects[win.cur]
                return (r ? r.name : "none") + " " + win.mode
                     + " " + Math.round(cat.x) + "," + Math.round(cat.y)
                     + (win.tripTo >= 0 ? " trip:" + shell.rects[win.tripTo].name : "")
                     + (win.wavePhase !== "" ? " wave:" + win.wavePhase : "")
                     + (win.asking ? " asking:" + win.qmode + (win.entering ? "(on the way)" : "")
                        + " focus:" + (input.focus ? "set" : "none") + (input.activeFocus ? "+active" : "") : "")
            }
        }
    }

    // ------------------------------------------ one window per monitor
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: pane
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bromodachi-cat"
            // never takes the keyboard: hovering or grabbing the cat must not
            // steal typing. The bubble lives in its own window (bubbleWin below)
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // only the cat takes input; the rest of the screen is click-through.
            // When the cat is on another monitor this region lies outside the
            // window, so nothing here is clickable
            mask: Region { item: view }

            readonly property real ox: modelData.x
            readonly property real oy: modelData.y
            readonly property bool here: win.mode !== "gone" && win.mode !== "transit" && win.mode !== "poofed"
                && win.mode !== "surfgone"
                && cat.x < ox + modelData.width && cat.x + win.catW > ox
                && cat.y < oy + modelData.height && cat.y + win.catH > oy

            // the log left behind by a jutsu (drawn behind the cat)
            Item {
                x: win.logX - pane.ox
                y: win.logY - pane.oy
                width: win.catW
                height: win.catH
                clip: true
                opacity: win.logOpacity
                visible: win.logOpacity > 0 && x > -width && x < pane.width && y > -height && y < pane.height
                Image {
                    source: "file://" + win.assetsDir + "/cat/cat_sheet_3x.png"
                    smooth: false
                    x: -win.logFrame * win.catW
                    y: -win.anims["log"].row * win.catH
                }
            }

            // the surf wave (behind the cat riding it); mirrored going left
            Item {
                readonly property var wa: win.wavePhase !== "" ? win.anims["wave_" + win.wavePhase] : null
                x: win.waveX - (win.surfDir > 0 ? win.rideX : win.waveW - win.rideX) - pane.ox
                y: win.waveFloor - win.waveH - pane.oy
                width: win.waveW
                height: win.waveH
                clip: true
                visible: wa !== null && x > -width && x < pane.width && y > -height && y < pane.height
                transform: Scale { origin.x: win.waveW / 2; xScale: win.surfDir }
                Image {
                    source: "file://" + win.assetsDir + "/cat/wave_sheet_3x.png"
                    smooth: false
                    x: -win.waveFrame * win.waveW
                    y: -(parent.wa ? parent.wa.row : 0) * win.waveH
                }
            }

            Item {
                id: view
                x: cat.x - pane.ox
                y: cat.y - pane.oy
                width: win.catW
                height: win.catH
                // the copy that was grabbed stays live while the hand drags
                // the cat onto another monitor: hiding it would drop the grab
                visible: pane.here || grabber.pressed

                Item {
                    id: body
                    anchors.fill: parent
                    transform: [
                        Scale {  // face the way we are walking (held is face-on)
                            origin.x: body.width / 2
                            // held and the laptop poses are face-on: never mirrored
                            xScale: win.mode === "held" || win.mode === "seal"
                                    || win.mode.indexOf("laptop") === 0 ? 1 : cat.facing
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
                    Item {
                        anchors.fill: parent
                        clip: true
                        Image {
                            source: "file://" + win.assetsDir + "/cat/cat_sheet_3x.png"
                            smooth: false  // nearest-neighbour: crisp pixels at any sub-pixel position
                            x: -win.frame * win.catW
                            y: -cat.anim.row * win.catH
                        }
                    }
                }

                Text {
                    visible: win.mode === "sleep"
                    text: "z"
                    color: "#8a8fa8"
                    font.pixelSize: 16 + win.zzz * 8
                    font.bold: true
                    opacity: 1 - win.zzz
                    x: (cat.facing > 0 ? cat.width * 0.62 : cat.width * 0.25) + win.zzz * 14 * cat.facing
                    y: cat.height * 0.25 - win.zzz * 40
                }

                MouseArea {
                    id: grabber
                    anchors.fill: parent
                    cursorShape: win.mode === "held" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    function toGlobal(mouse) {
                        const p = mapToItem(null, mouse.x, mouse.y)
                        return { x: pane.ox + p.x, y: pane.oy + p.y }
                    }
                    onPressed: mouse => { const g = toGlobal(mouse); win.grab(g.x, g.y) }
                    onPositionChanged: mouse => { const g = toGlobal(mouse); win.drag(g.x, g.y) }
                    onReleased: win.release()
                    // the compositor can cancel a grab (focus change, another
                    // client grabbing); that must not leave the cat "held"
                    onCanceled: win.release()
                }
            }

            // jutsu smoke, in front of the cat, and the ドロン floating off it
            Repeater {
                model: win.puffs
                Item {
                    required property var modelData
                    readonly property var p: modelData
                    readonly property var pa: win.anims[p.kind]
                    readonly property int k: Math.floor((p.big ? p.t / 0.4 : p.t) * pa.frames)
                    x: p.x - pane.ox
                    y: p.y - pane.oy
                    width: win.catW
                    height: win.catH
                    visible: p.t < 1 && x > -width - 60 && x < pane.width + 60 && y > -height - 60 && y < pane.height
                    Item {
                        anchors.fill: parent
                        clip: true
                        visible: parent.k < parent.pa.frames
                        Image {
                            source: "file://" + win.assetsDir + "/cat/cat_sheet_3x.png"
                            smooth: false
                            x: -Math.min(parent.parent.k, parent.parent.pa.frames - 1) * win.catW
                            y: -parent.parent.pa.row * win.catH
                        }
                    }
                    Text {
                        visible: parent.p.big
                        text: "ドロン"
                        font.family: "Noto Sans CJK JP"
                        font.pixelSize: 22
                        font.bold: true
                        color: "#f0c419"
                        style: Text.Outline
                        styleColor: "#2b211b"
                        x: (parent.width - width) / 2
                        y: -12 - parent.p.t * 34
                        opacity: parent.p.t < 0.6 ? 1 : 1 - (parent.p.t - 0.6) / 0.4
                        scale: parent.p.t < 0.12 ? 0.4 + parent.p.t / 0.12 * 0.8 : 1.2 - Math.min(parent.p.t, 0.3) * 0.67
                    }
                }
            }

            // the little star at the top of the desk where it blasted off
            Text {
                x: win.twinkleX - pane.ox - width / 2
                y: win.twinkleY - pane.oy
                text: "✦"
                color: "#f0c419"
                font.pixelSize: 26
                visible: win.twinkle > 0 && win.twinkle < 1
                         && win.twinkleX >= pane.ox && win.twinkleX < pane.ox + pane.modelData.width
                         && win.twinkleY >= pane.oy && win.twinkleY < pane.oy + pane.modelData.height
                scale: win.twinkle < 0.4 ? win.twinkle / 0.4 * 1.4 : 1.4 * (1 - (win.twinkle - 0.4) / 0.6)
                rotation: win.twinkle * 180
            }
        }
    }

    // The question bubble gets its own layer, mapped on ask and unmapped on
    // dismiss. Hyprland does not honour a keyboard-interactivity change on an
    // already-mapped layer, so a surface that is born OnDemand (like the old
    // popup) is what lets the summon cursor-warp actually focus the answer box.
    PanelWindow {
        id: bubbleWin
        visible: win.asking && !win.entering
        // askIdx only changes while the bubble is hidden: moving a mapped
        // layer to another monitor is the kind of change that lost the cat
        screen: win.askRect.screen
        // sized to the bubble (+ shadow and tail), not full-screen: Hyprland
        // only hover-focuses a layer when the pointer enters the surface
        // itself, and entering a masked region of a full-screen layer does
        // not count, so a full-screen bubble needed a click to take keys
        anchors { left: true; bottom: true }
        margins.left: win.bubbleX
        margins.bottom: win.askRect.h - win.bubbleY - implicitHeight
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
                    x: Math.max(12, Math.min(bubble.width - 42, win.catLX + cat.width / 2 - win.bubbleX - 15))
                    y: bubble.height - 2
                    width: 30; height: 12; color: "#1a1a2e"; border.color: "#ffffff"; border.width: 3
                    visible: bubble.scale > 0.9 && win.bubbleY + bubble.height < win.catLY
                }
                Rectangle {
                    x: Math.max(19, Math.min(bubble.width - 35, win.catLX + cat.width / 2 - win.bubbleX - 8))
                    y: bubble.height + 9
                    width: 16; height: 12; color: "#1a1a2e"; border.color: "#ffffff"; border.width: 3
                    visible: bubble.scale > 0.9 && win.bubbleY + bubble.height + 21 < win.catLY
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
                                    win.refreshReady()
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
