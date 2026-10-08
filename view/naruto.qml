import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "spin.js" as Spin

// The Gitea buddy: a chibi Naruto who lives along the bottoms of the monitors
// like the cat does, and acts out what the shop Gitea's Actions are doing.
//
//   a run in flight      charges a Rasengan that grows with the steps done
//   it passes            a cheer and a thumbs-up
//   a workflow fails     knocked flat, then worried for as long as anything is red
//   a PR merges          shadow clones pop out and cheer
//   server unreachable   scratches his head
// Thrown hard at a wall he doesn't cling to it: he plants his feet and runs
// up it, then kicks off into a flip.
//
// He knows nothing about the server. `omarchy-gitea` (the tracker the bar
// widget also uses) owns the address, the token, the repo list and what
// "failing" means; this view only runs its two pure-read commands and
// compares one poll with the next:
//   omarchy-gitea report     {url, primary, repos[{repo, running, latest}], merges[]}
//   omarchy-gitea run REPO   {run, jobs[{steps[]}]}  (only while a run is going)
//   exit 0 ok · 2 unreachable · 3 no token
// It never notifies (the widget's `check` does) and never writes the
// tracker's state. NARUTO_MONITOR_CMD swaps the command for a stub in tests.
//
// Movement (world of monitors, physics, drag and throw, the two-circle
// wind-up, trips between monitors, the substitution jutsu) is the cat's,
// forked from cat.qml; the ids `cat` (the character) and `win` (its brain)
// are kept from there so the two files stay easy to compare. The daemon only
// starts and respawns this process (src/view.rs); env BUDDY_CAT_SCREEN is
// the monitor to wake up on. A click (no drag) opens whatever he is on about.
ShellRoot {
    id: shell

    // -------------------------------------------------------------- world
    readonly property var rects: {
        const s = Quickshell.screens, r = []
        for (let i = 0; i < s.length; i++)
            r.push({ name: s[i].name, x: s[i].x, y: s[i].y, w: s[i].width, h: s[i].height, screen: s[i] })
        return r
    }

    // any change to the monitor set or layout restarts the view (see cat.qml)
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
        let i = indexOf(Quickshell.env("BUDDY_CAT_SCREEN") || "")
        for (let j = 0; i < 0 && j < rects.length; j++)
            if (rects[j].name.indexOf("eDP") !== 0) i = j
        win.cur = Math.max(0, i)
        if (rects.length > 0) {
            const r = rects[win.cur]
            // the cat wakes up near the right end; he takes the left
            cat.x = r.x + 220
            cat.y = floorY(win.cur)
        }
        bootRects = rects
        booted = true
        win.rest()
        win.play(cat.anim)
    }

    // ------------------------------------------------------ the character
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

        // mode -> row of assets/naruto/naruto_sheet_3x.png (make_naruto.py)
        readonly property var anim: {
            const m = { land: "stand", brace: "stand", jump: "leap", transit: "leap", poofed: "seal",
                        gone: "stand", launched: "fall", wallrun: "run",
                        rasengan: "rasengan" + win.orb }[win.mode] || win.mode
            return win.anims[m] || win.anims["stand"]
        }
        onAnimChanged: win.play(anim)
    }

    // ------------------------------------------------------------ the brain
    Scope {
        id: win

        // ------------------------------------------------------ tunables
        readonly property real catW: 96      // 32 px sprite at 3x
        readonly property real catH: 96
        readonly property real gravity: 2600 // px/s^2
        readonly property real walkSpeed: 80 // px/s
        readonly property real runSpeed: 460 // px/s, the ninja run to an event
        readonly property real stickSpeed: 450
        // running up a wall: what he hit it with carries him up (between
        // these speeds), this wears it down, and he kicks off when it's spent
        readonly property real wallRunMin: 420
        readonly property real wallRunMax: 1100
        readonly property real wallDecel: 1100
        readonly property real kickVx: 380
        readonly property real kickVy: 420
        readonly property real launchSpeed: 900 // upward fling after the two-circle wind-up
        readonly property real leapVx: 490
        readonly property real leapVy: 850
        readonly property real edgeGap: 70
        readonly property real hopVx: 380
        readonly property real hopClear: 90
        // how often a monitor switch is the substitution jutsu, not a run and a jump
        readonly property real jutsuChance: 0.4
        // polling the tracker: relaxed normally, brisk while a run is going
        readonly property int pollIdleMs: 60000
        readonly property int pollBusyMs: 10000
        readonly property string monitorCmd: Quickshell.env("NARUTO_MONITOR_CMD") || "omarchy-gitea"
        readonly property string assetsDir: {
            const u = Qt.resolvedUrl(".").toString().replace("file://", "")
            return u.replace(/\/view\/?$/, "") + "/assets"
        }
        FileView { id: animFile; path: win.assetsDir + "/naruto/naruto_sheet.json"; blockLoading: true }
        readonly property var anims: JSON.parse(animFile.text())
        // the smoke and the log are the cat's props (96x72 cells)
        FileView { id: propFile; path: win.assetsDir + "/cat/cat_sheet.json"; blockLoading: true }
        readonly property var props: JSON.parse(propFile.text())
        readonly property real propH: 72

        // --------------------------------------------------------- state
        // resting: stand | ramen | sleep | rasengan | worried | confused
        // acting:  knocked | cheer | thumbs | seal
        // moving:  walk | run | jump | fall | wallrun | land | leap | held
        //          | launched | gone | transit | brace | poofed
        property string mode: "stand"
        property int cur: 0
        property real vx: 0
        property real vy: 0
        property real walkTo: 0
        property int tripTo: -1
        property bool tripRun: false
        property int tripDir: 0
        property bool tripJumping: false
        property int tripHops: 0
        property bool tripDirect: false
        property real exitX: 0
        property int leapTo: 0
        // on his way to the monitor you're on, to act out `pending`
        property bool arriving: false
        property var pending: null
        readonly property var restModes: ["stand", "ramen", "sleep", "rasengan", "worried", "confused", "walk", "land"]
        property real lastMouseX: 0
        property real lastMouseY: 0
        property real lastMouseT: 0
        property real handX: 0
        property real handPrevX: 0
        property real handV: 0
        property real swayAng: 0
        property real swayVel: 0
        readonly property real swayLen: 50
        readonly property real swayDamp: 4

        function faceTravel() {
            if (Math.abs(vx) > 60) cat.facing = vx < 0 ? -1 : 1
        }

        function setMode(m) {
            mode = m
            // how long each resting state lasts before the next decision
            if (m === "stand") idle.interval = 3000 + Math.random() * 4000
            else if (m === "ramen") idle.interval = 20000 + Math.random() * 20000
            else if (m === "sleep") idle.interval = 40000 + Math.random() * 50000
            else if (m === "worried") idle.interval = 8000 + Math.random() * 8000
            else if (m === "confused") idle.interval = 15000 + Math.random() * 10000
            else if (m === "land") idle.interval = tripRun ? 250 : 700
            else if (m === "transit") idle.interval = 350
            else return idle.stop()
            idle.restart()
        }

        // what he does when nothing is happening: it depends on the monitor
        function rest() {
            if (mood === "running") setMode("rasengan")
            else if (mood === "red") setMode("worried")
            else if (mood === "down") setMode("confused")
            else setMode("stand")
        }

        // ------------------------------------------------------- travel
        function beginTrip(j, run) {
            tripTo = j
            tripRun = run
            tripHops = 0
            if (Math.random() < jutsuChance) beginJutsu(j)
            else tripStep()
        }
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
        function tripStep() {
            const s = shell.rects[cur]
            tripDir = exitDir(cur, tripTo)
            tripDirect = ++tripHops > 3
            walkTo = tripDir < 0 ? s.x + edgeGap : s.x + s.w - catW - edgeGap
            setMode(tripRun ? "run" : "walk")
        }
        function tripJump() {
            const s = shell.rects[cur]
            let rise = 0
            const n = shell.touchingSide(cur, tripDir)
            if (n >= 0) {
                const up = (s.y + s.h) - (shell.rects[n].y + shell.rects[n].h)
                if (up > 0 && up < 700) rise = up
            }
            tripJumping = true
            cat.facing = tripDir
            vy = -Math.sqrt(2 * gravity * (rise + hopClear))
            const k = -Math.log(0.4), t = -vy / gravity * 0.85
            vx = tripDir * (rise > 0 ? (edgeGap + catW / 2 + 10) * k / (1 - Math.exp(-k * t)) : hopVx)
            setMode("jump")
        }
        function updateCur() {
            const i = shell.screenAt(cat.x + catW / 2, cat.y + catH / 2)
            if (tripJumping && (i < 0 || (tripDirect && i !== cur))) {
                exitX = cat.x + catW / 2
                tripJumping = false
                setMode("transit")
                return true
            }
            if (i >= 0 && i !== cur) {
                cur = i
                tripJumping = false
            }
            return false
        }
        function entrySide(i, fromX) {
            const t = shell.rects[i]
            const near = Math.abs(fromX - t.x) <= Math.abs(fromX - (t.x + t.w))
            const clear = function (left) {
                const j = shell.screenAt(left ? t.x - catW / 2 : t.x + t.w + catW / 2, shell.floorY(i) + catH / 2)
                return j < 0 || Math.abs(shell.floorY(j) - shell.floorY(i)) < 20
            }
            return !clear(near) && clear(!near) ? !near : near
        }
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
        function passSide(dir) {
            if (tripJumping && dir === tripDir) return true
            return shell.sideNeighbor(cur, dir, cat.y) >= 0
        }
        function land(impact) {
            cat.y = shell.floorY(cur)
            squash.impact = impact
            squash.restart()
            vx = 0; vy = 0
            tripJumping = false
            flipAnim.stop()
            flip = 0
            setMode("land")
            if (arriving && (tripTo < 0 || cur === tripTo)) arrived()
        }

        // ------------------------------------------ substitution jutsu
        // the cat borrowed this from him: hand seal, ドロン, a log left behind
        property int jutsuTo: -1
        property real jutsuX: 0
        function beginJutsu(j) {
            setMode("brace")
            jutsuTo = j
            tripTo = j
            tripJumping = false
            vx = 0; vy = 0
            const t = shell.rects[j]
            jutsuX = t.x + t.w * (0.2 + Math.random() * 0.6) - catW / 2
            jutsu.restart()
        }
        SequentialAnimation {
            id: jutsu
            ScriptAction { script: win.setMode("seal") }
            PauseAnimation { duration: 450 }
            ScriptAction { script: win.puff(0, cat.x, cat.y, true) }
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
            ScriptAction {
                script: {
                    const t = shell.rects[win.jutsuTo]
                    win.cur = win.jutsuTo
                    cat.x = win.jutsuX
                    cat.y = shell.floorY(win.jutsuTo)
                    cat.facing = cat.x + win.catW / 2 < t.x + t.w / 2 ? 1 : -1
                    win.puff(1, cat.x, cat.y, true)
                }
            }
            PauseAnimation { duration: 170 }
            ScriptAction { script: win.setMode("seal") }
            PauseAnimation { duration: 350 }
            ScriptAction { script: { win.jutsuTo = -1; win.land(0.2) } }
        }

        // smoke puffs (t runs 0 -> 1; a big one spends its first 40% on the
        // smoke and the rest letting the ドロン float away)
        QtObject { id: puff0; property real x; property real y; property real t: 1; property bool big }
        QtObject { id: puff1; property real x; property real y; property real t: 1; property bool big }
        QtObject { id: puff2; property real x; property real y; property real t: 1; property bool big }
        QtObject { id: puff3; property real x; property real y; property real t: 1; property bool big }
        readonly property var puffs: [puff0, puff1, puff2, puff3]
        NumberAnimation { id: puffAnim0; target: puff0; property: "t"; from: 0; to: 1; duration: puff0.big ? 900 : 260 }
        NumberAnimation { id: puffAnim1; target: puff1; property: "t"; from: 0; to: 1; duration: puff1.big ? 900 : 260 }
        NumberAnimation { id: puffAnim2; target: puff2; property: "t"; from: 0; to: 1; duration: puff2.big ? 900 : 260 }
        NumberAnimation { id: puffAnim3; target: puff3; property: "t"; from: 0; to: 1; duration: puff3.big ? 900 : 260 }
        function puff(i, x, y, big) {
            const p = puffs[i]
            p.x = x
            p.y = y
            p.big = big
            ;[puffAnim0, puffAnim1, puffAnim2, puffAnim3][i].restart()
        }

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

        // ------------------------------------------------- the idle brain
        Timer {
            id: idle
            onTriggered: {
                if (win.mode === "land") {
                    if (win.tripTo >= 0 && win.tripTo !== win.cur) return win.tripStep()
                    win.tripTo = -1
                    win.tripRun = false
                    if (win.arriving) return win.arrived()
                    win.rest()
                    win.nextEvent()
                } else if (win.mode === "transit") {
                    win.leapInto(win.tripTo >= 0 ? win.tripTo : win.cur, win.exitX)
                } else if (win.mode === "stand") {
                    if (win.nextEvent()) return
                    if (win.mood !== "ok") return win.rest()
                    const r = Math.random()
                    if (r < 0.10 && shell.rects.length > 1) {
                        // go and see another monitor
                        let j = Math.floor(Math.random() * (shell.rects.length - 1))
                        if (j >= win.cur) j++
                        win.beginTrip(j, false)
                    } else if (r < 0.40) {
                        const s = shell.rects[win.cur]
                        const d = (120 + Math.random() * 480) * (Math.random() < 0.5 ? -1 : 1)
                        win.walkTo = Math.max(s.x, Math.min(s.x + s.w - win.catW, cat.x + d))
                        win.setMode("walk")
                    } else if (r < 0.65) {
                        win.setMode("ramen")
                    } else if (r < 0.80) {
                        win.setMode("sleep")
                    } else {
                        win.setMode("stand")
                    }
                } else if (win.mode === "worried") {
                    // something is red: he paces
                    const s = shell.rects[win.cur]
                    const d = (80 + Math.random() * 160) * (cat.facing > 0 ? -1 : 1)
                    win.walkTo = Math.max(s.x, Math.min(s.x + s.w - win.catW, cat.x + d))
                    win.setMode("walk")
                } else {
                    // ramen finished, nap over, done scratching his head
                    win.setMode("stand")
                    if (win.mood !== "ok") win.rest()
                }
            }
        }

        // physics + walking, one step per rendered frame
        FrameAnimation {
            running: ["fall", "jump", "walk", "run", "wallrun", "held", "launched", "leap"]
                     .indexOf(win.mode) >= 0
            onTriggered: {
                const dt = Math.min(frameTime, 0.05)
                if (win.mode === "held") return win.stepHeld(dt)
                if (win.mode === "walk" || win.mode === "run") return win.stepWalk(dt)
                if (win.mode === "launched") return win.stepLaunched(dt)
                if (win.mode === "leap") return win.stepLeap(dt)
                if (win.mode === "wallrun") return win.stepWallRun(dt)
                win.stepFall(dt)
            }
        }

        function stepHeld(dt) {
            const v = (handX - handPrevX) / Math.max(dt, 0.001)
            handPrevX = handX
            const vs = 0.5 * handV + 0.5 * v
            const a = Math.max(-30000, Math.min(30000, (vs - handV) / Math.max(dt, 0.001)))
            handV = vs
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
            if ((dir > 0 && nx > walkTo) || (dir < 0 && nx < walkTo)) nx = walkTo
            cat.x = nx
            updateCur()
            if (cat.y < shell.floorY(cur) - 0.5) {
                vx = dir * speed
                vy = 0
                setMode("fall")
                return
            }
            if (Math.abs(walkTo - cat.x) < 1 || blocked) {
                if (tripTo >= 0 && tripTo !== cur) return tripJump()
                rest()
                nextEvent()
            }
        }

        function stepLaunched(dt) {
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
            updateCur()
            const top = shell.rects[cur]
            if (cat.y < top.y - catH - 20 && shell.vertNeighbor(cur, -1, cat.x + catW / 2) < 0) {
                twinkleX = cat.x + catW / 2
                twinkleY = top.y + 4
                twinkleAnim.restart()
                setMode("gone")
            }
        }

        function stepLeap(dt) {
            vy += gravity * dt
            cat.x += vx * dt
            cat.y += vy * dt
            if (vy > 0 && cat.y >= shell.floorY(leapTo)) {
                cur = leapTo
                land(0.45)
            }
        }

        function stepWallRun(dt) {
            // feet on the wall, running up it; gravity wears the run down
            vy = Math.min(vy + wallDecel * dt, 0)
            cat.y += vy * dt
            const top = shell.rects[cur].y + 4
            if (vy > -40 || cat.y <= top) {
                // out of steam (or out of wall): kick off into a flip
                cat.y = Math.max(cat.y, top)
                cat.facing = -cat.facing
                vx = cat.facing * kickVx
                vy = -kickVy
                flipAnim.to = 360 * cat.facing
                flipAnim.restart()
                setMode("jump")
            }
        }

        function stepFall(dt) {
            const s = shell.rects[cur]
            const prevY = cat.y
            vy += gravity * dt
            vx *= Math.pow(0.4, dt)
            let nx = cat.x + vx * dt
            let hit = 0
            if (nx < s.x && !passSide(-1)) { nx = s.x; hit = -1 }
            else if (nx > s.x + s.w - catW && !passSide(1)) { nx = s.x + s.w - catW; hit = 1 }
            cat.x = nx
            let ny = cat.y + vy * dt
            if (ny < s.y && vy < 0 && shell.vertNeighbor(cur, -1, cat.x + catW / 2) < 0) {
                ny = s.y
                vy = -vy * 0.3
            }
            cat.y = ny
            if (hit !== 0) {
                if (Math.abs(vx) > stickSpeed) {
                    // a hard hit: he plants his feet and runs up the wall
                    cat.facing = hit
                    vy = -Math.min(wallRunMax, Math.max(wallRunMin, Math.abs(vx) * 0.7 + Math.max(0, -vy) * 0.5))
                    vx = 0
                    setMode("wallrun")
                    return
                }
                vx = -vx * 0.4
                faceTravel()
            }
            if (updateCur()) return
            const fy = shell.floorY(cur)
            if (cat.y >= fy && ((vy > 0 && prevY <= fy + 1)
                    || shell.vertNeighbor(cur, 1, cat.x + catW / 2) < 0))
                land(Math.min(Math.max(vy, 0) / 2500, 1))
        }

        // --------------------------------------------------- sprite clock
        property int frame: 0
        property var shown: null
        function play(a) {
            if (a === shown) return
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
                else stop()
            }
        }

        // the flip off a wall: one turn in the air
        property real flip: 0
        NumberAnimation { id: flipAnim; target: win; property: "flip"; from: 0; duration: 450 }

        property real twinkleX: 0
        property real twinkleY: 0
        property real twinkle: 0
        NumberAnimation on twinkle { id: twinkleAnim; running: false; from: 0; to: 1; duration: 650 }

        SequentialAnimation {
            id: squash
            property real impact: 0.5
            property real amount: 0
            NumberAnimation { target: squash; property: "amount"; to: squash.impact * 0.35; duration: 60 }
            NumberAnimation { target: squash; property: "amount"; to: -0.08 * squash.impact; duration: 140; easing.type: Easing.OutQuad }
            NumberAnimation { target: squash; property: "amount"; to: 0; duration: 180; easing.type: Easing.OutBounce }
        }

        // ------------------------------------------------------- dragging
        property var spin: Spin.fresh(0, 0, 0)
        property real grabT: 0
        property real grabPX: 0
        property real grabPY: 0
        property real grabFar: 0   // how far the hand strayed: a click doesn't
        function grab(px, py) {
            // picked up by the collar
            grabT = Date.now()
            grabPX = px; grabPY = py; grabFar = 0
            if (!arriving) tripTo = -1
            tripJumping = false
            if (jutsu.running) { jutsu.stop(); jutsuTo = -1 }
            flipAnim.stop()
            flip = 0
            // caught mid-performance: that event has been seen, it's done
            if (act.running) { act.stop(); pending = null }
            clones = 0
            cat.grabX = catW / 2
            cat.grabY = 46
            moveHeld(px, py)
            vx = 0; vy = 0
            lastMouseT = grabT
            lastMouseX = px
            lastMouseY = py
            handX = px; handPrevX = px; handV = 0
            swayAng = 0; swayVel = 0; cat.sway = 0
            squash.stop(); squash.amount = 0
            spin = Spin.fresh(px, py, lastMouseT)
            setMode("held")
        }
        function drag(px, py) {
            if (mode !== "held") return
            const now = Date.now()
            const dt = Math.max((now - lastMouseT) / 1000, 0.008)
            vx = 0.6 * vx + 0.4 * (px - lastMouseX) / dt
            vy = 0.6 * vy + 0.4 * (py - lastMouseY) / dt
            lastMouseX = px
            lastMouseY = py
            lastMouseT = now
            handX = px
            grabFar = Math.max(grabFar, Math.abs(px - grabPX) + Math.abs(py - grabPY))
            Spin.track(spin, px, py, now, Math.sqrt(vx * vx + vy * vy))
            moveHeld(px, py)
        }
        function moveHeld(px, py) {
            let i = shell.screenAt(px, py)
            if (i < 0) i = cur
            const r = shell.rects[i]
            cur = i
            cat.x = Math.max(r.x - catW / 2, Math.min(r.x + r.w - catW / 2, px - cat.grabX))
            cat.y = Math.max(r.y - catH / 2, Math.min(shell.floorY(i), py - cat.grabY))
        }
        function release() {
            if (mode !== "held") return
            // a click, not a carry: open what he is on about
            if (grabFar < 8 && Date.now() - grabT < 350) openLink()
            if (Date.now() - lastMouseT > 80) { vx = 0; vy = 0 }
            vx = Math.max(-3000, Math.min(3000, vx))
            vy = Math.max(-2600, Math.min(2600, vy))
            faceTravel()
            if (arriving) tripTo = -1
            if (Spin.charged(spin, Date.now()) && vy < -launchSpeed) {
                cat.spin = 0
                setMode("launched")
                return
            }
            setMode("fall")
        }
        function openLink() {
            const url = sayUrl !== "" ? sayUrl : moodUrl
            if (url !== "") Quickshell.execDetached(["xdg-open", url])
        }

        // ----------------------------------------------- the Gitea monitor
        // mood: ok | running | red | down. The resting pose follows it.
        property string mood: "ok"
        property var report: null
        property var seen: null          // last poll, for diffing; null until the first good one
        property var mergesSeen: ({})
        property var failing: []         // [{repo, latest}] currently red
        property string watchRepo: ""    // the repo whose run is in flight
        property var watchRun: null      // its `run` detail
        property real progress: 0        // steps done / steps, of that run
        readonly property int orb: progress < 0.34 ? 1 : progress < 0.67 ? 2 : 3
        property string downWhy: ""
        property var events: []          // waiting to be acted out

        function setMood(m) {
            if (m === mood) return
            mood = m
            if (mode === "gone") {
                // thrown away, but something changed: come back and look
                arriving = false
                return leapInto(cur, cat.x + catW / 2)
            }
            // resting (and not on a trip or about to act): take up the new pose
            if (["stand", "ramen", "sleep", "rasengan", "worried", "confused"].indexOf(mode) >= 0) rest()
        }

        function gotReport(code, text) {
            let r = null
            if (code === 0) {
                try { r = JSON.parse(text) } catch (e) { r = null }
            }
            if (!r || !r.repos) {
                downWhy = code === 3 ? "no token" : "unreachable"
                watchRepo = ""
                setMood("down")
                return
            }
            report = r
            const now = {}
            const red = []
            let going = ""
            for (let i = 0; i < r.repos.length; i++) {
                const p = r.repos[i]
                const l = p.latest
                const key = l ? l.workflow + "#" + l.run_number + ":" + l.conclusion : ""
                now[p.repo] = { running: p.running, key: key }
                if (p.running > 0 && (going === "" || p.repo === r.primary)) going = p.repo
                if (l && l.conclusion === "failure") red.push(p)
                // the repo's badge run changed since the last poll: one finished
                const was = seen ? seen[p.repo] : null
                if (was && l && was.key !== key) {
                    const link = r.url + "/" + p.repo + "/actions"
                    if (l.conclusion === "failure")
                        events.push({ kind: "fail", url: link,
                                      text: "しまった！ " + p.repo + ": " + l.workflow + " failed #" + l.run_number })
                    else if (l.conclusion === "success")
                        events.push({ kind: "pass", url: link,
                                      text: "やったってばよ！ " + p.repo + " #" + l.run_number + " passed" })
                }
            }
            const merges = r.merges || []
            for (let i = merges.length - 1; i >= 0; i--) {
                const m = merges[i], k = m.repo + "#" + m.number
                if (seen && !mergesSeen[k])
                    events.push({ kind: "merge", url: r.url + "/" + m.repo + "/pulls/" + m.number,
                                  text: "影分身の術！ merged: " + m.repo + " #" + m.number + " — " + m.title })
                mergesSeen[k] = true
            }
            seen = now
            failing = red
            if (going !== watchRepo) { watchRepo = going; watchRun = null; progress = 0 }
            setMood(going !== "" ? "running" : red.length > 0 ? "red" : "ok")
            if (going !== "" && !runProc.running) startRun()
            nextEvent()
        }

        function gotRun(code, text) {
            if (code !== 0) return
            let d = null
            try { d = JSON.parse(text) } catch (e) { return }
            if (!d || d.repo !== watchRepo || !d.run) return
            watchRun = d
            let done = 0, total = 0
            for (let i = 0; i < d.jobs.length; i++)
                for (let j = 0; j < d.jobs[i].steps.length; j++) {
                    total++
                    if (d.jobs[i].steps[j].status === "completed") done++
                }
            progress = total > 0 ? done / total : 0
        }

        // The tracker's commands, run as subprocesses. Each result is used
        // once both its output stream has closed and it has exited.
        QtObject { id: rep; property int code: -1; property bool closed: false }
        Process {
            id: reportProc
            command: [win.monitorCmd, "report"]
            stdout: StdioCollector {
                id: reportOut
                onStreamFinished: { rep.closed = true; if (rep.code >= 0) win.gotReport(rep.code, reportOut.text) }
            }
            onExited: (exitCode, exitStatus) => { rep.code = exitCode; if (rep.closed) win.gotReport(exitCode, reportOut.text) }
        }
        QtObject { id: rn; property int code: -1; property bool closed: false }
        Process {
            id: runProc
            stdout: StdioCollector {
                id: runOut
                onStreamFinished: { rn.closed = true; if (rn.code >= 0) win.gotRun(rn.code, runOut.text) }
            }
            onExited: (exitCode, exitStatus) => { rn.code = exitCode; if (rn.closed) win.gotRun(exitCode, runOut.text) }
        }
        function startRun() {
            rn.code = -1; rn.closed = false
            runProc.command = [monitorCmd, "run", watchRepo]
            runProc.running = true
        }
        Timer {
            interval: win.mood === "running" ? win.pollBusyMs : win.pollIdleMs
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                if (reportProc.running) return
                rep.code = -1; rep.closed = false
                reportProc.running = true
            }
        }

        // ------------------------------------------------ acting it out
        // An event is acted on the monitor you are working on: he asks
        // Hyprland which that is, goes there, then performs.
        QtObject { id: foc; property int code: -1; property bool closed: false }
        Process {
            id: focusProc
            command: ["hyprctl", "monitors", "-j"]
            stdout: StdioCollector {
                id: focusOut
                onStreamFinished: { foc.closed = true; if (foc.code >= 0) win.gotFocus(focusOut.text) }
            }
            onExited: (exitCode, exitStatus) => { foc.code = exitCode; if (foc.closed) win.gotFocus(focusOut.text) }
        }
        function gotFocus(text) {
            let target = cur
            try {
                const ms = JSON.parse(text)
                for (let i = 0; i < ms.length; i++)
                    if (ms[i].focused && shell.indexOf(ms[i].name) >= 0) target = shell.indexOf(ms[i].name)
            } catch (e) {}
            if (!pending) return
            if (mode === "gone") {
                arriving = true
                tripTo = target
                return leapInto(target, cat.x + catW / 2)
            }
            if (!free()) {
                // picked up (or set off somewhere) in the meantime: the
                // event goes back in the queue for his next free moment
                events.unshift(pending)
                pending = null
                return
            }
            if (target !== cur) {
                arriving = true
                beginTrip(target, true)
            } else {
                perform()
            }
        }
        // free to start something: resting (or thrown away), not mid-anything
        function free() {
            return !arriving && !act.running && !jutsu.running && tripTo < 0
                && (["stand", "ramen", "sleep", "rasengan", "worried", "confused", "gone"].indexOf(mode) >= 0)
        }
        // take the next event, if he is free to; true = one was started
        function nextEvent() {
            if (pending || events.length === 0 || !free() || focusProc.running) return false
            pending = events.shift()
            foc.code = -1; foc.closed = false
            focusProc.running = true
            return true
        }
        function arrived() {
            arriving = false
            tripTo = -1
            tripRun = false
            perform()
        }
        property int clones: 0
        function perform() {
            const ev = pending
            if (!ev) return rest()
            say(ev.text, ev.kind, ev.url, 9000)
            act.kind = ev.kind
            act.restart()
        }
        SequentialAnimation {
            id: act
            property string kind: ""
            // fail: knocked flat · pass: a cheer, then thumbs-up · merge: the
            // seal, then clones popping out of smoke to cheer with him
            ScriptAction {
                script: win.setMode(act.kind === "fail" ? "knocked" : act.kind === "merge" ? "seal" : "cheer")
            }
            PauseAnimation { duration: act.kind === "merge" ? 700 : 1 }
            ScriptAction {
                script: {
                    if (act.kind !== "merge") return
                    win.clones = 3
                    for (let i = 0; i < 3; i++)
                        win.puff(i + 1, cat.x + win.cloneDx(i), cat.y, false)
                    win.setMode("cheer")
                }
            }
            PauseAnimation { duration: act.kind === "fail" ? 2600 : 2200 }
            ScriptAction {
                script: {
                    if (act.kind === "merge") {
                        for (let i = 0; i < 3; i++)
                            win.puff(i + 1, cat.x + win.cloneDx(i), cat.y, false)
                        win.clones = 0
                    }
                    if (act.kind !== "fail") win.setMode("thumbs")
                }
            }
            PauseAnimation { duration: act.kind === "fail" ? 1 : 1800 }
            ScriptAction { script: { win.pending = null; win.rest(); win.nextEvent() } }
        }
        function cloneDx(i) { return [-84, 84, -168][i] }

        // ---------------------------------------------------- the bubble
        // An event's line shows for a few seconds; otherwise the mood's.
        property string sayText: ""
        property string sayKind: ""
        property string sayUrl: ""
        Timer { id: sayTimer; onTriggered: { win.sayText = ""; win.sayUrl = "" } }
        function say(text, kind, url, ms) {
            sayText = text
            sayKind = kind
            sayUrl = url
            sayTimer.interval = ms
            sayTimer.restart()
        }
        readonly property string moodText: {
            if (mood === "running") {
                const l = watchRun && watchRun.run ? watchRun.run.workflow : ""
                let done = 0, total = 0
                if (watchRun)
                    for (let i = 0; i < watchRun.jobs.length; i++)
                        for (let j = 0; j < watchRun.jobs[i].steps.length; j++) {
                            total++
                            if (watchRun.jobs[i].steps[j].status === "completed") done++
                        }
                return "螺旋丸… " + watchRepo + (l ? " · " + l : "") + (total > 0 ? "  " + done + "/" + total : "")
            }
            if (mood === "red" && failing.length > 0) {
                const f = failing[0]
                return "✗ " + f.repo + ": " + f.latest.workflow + " #" + f.latest.run_number
                     + (failing.length > 1 ? "  (+" + (failing.length - 1) + ")" : "")
            }
            if (mood === "down") return "つながらないってばよ… (" + downWhy + ")"
            return ""
        }
        readonly property string moodUrl: {
            if (!report) return ""
            if (mood === "running" && watchRun && watchRun.run && watchRun.run.html_url) return watchRun.run.html_url
            if (mood === "running") return report.url + "/" + watchRepo + "/actions"
            if (mood === "red" && failing.length > 0) return report.url + "/" + failing[0].repo + "/actions"
            return report.url
        }
        readonly property string bubbleText: sayText !== "" ? sayText : moodText
        readonly property string bubbleKind: sayText !== "" ? sayKind : mood === "running" ? "run" : mood === "red" ? "fail" : "down"

        IpcHandler {
            target: "naruto"
            function where(): string {
                const r = shell.rects[win.cur]
                return (r ? r.name : "none") + " " + win.mode + " " + Math.round(cat.x) + "," + Math.round(cat.y)
                     + " mood:" + win.mood + (win.mood === "running" ? "(" + win.watchRepo + " " + Math.round(win.progress * 100) + "%)" : "")
                     + (win.tripTo >= 0 ? " trip:" + shell.rects[win.tripTo].name : "")
                     + (win.arriving ? " arriving" : "")
                     + " events:" + win.events.length + (win.pending ? "+1" : "")
                     + (win.bubbleText !== "" ? " says:" + win.bubbleText : "")
            }
            // walk (or jutsu) over to another monitor now (resting only)
            function visit(screen: string): string {
                const j = shell.indexOf(screen)
                if (j < 0) return "no monitor " + screen
                if (!win.free() || win.mode === "gone") return "busy: " + win.mode
                if (j === win.cur) return "already there"
                win.beginTrip(j, false)
                return "ok"
            }
            // throw him (testing): toss <vx> <vy> in px/s, from a little off the floor
            function toss(vx: string, vy: string): string {
                if (!win.free() || win.mode === "gone") return "busy: " + win.mode
                cat.y -= 120
                win.vx = parseFloat(vx)
                win.vy = parseFloat(vy)
                win.faceTravel()
                win.setMode("fall")
                return "ok"
            }
            // poll the tracker right now
            function poll(): string {
                if (reportProc.running) return "already polling"
                rep.code = -1; rep.closed = false
                reportProc.running = true
                return "ok"
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
            WlrLayershell.namespace: "bromodachi-naruto"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // only he takes input; the rest of the screen is click-through
            mask: Region { item: view }

            readonly property real ox: modelData.x
            readonly property real oy: modelData.y
            readonly property bool here: win.mode !== "gone" && win.mode !== "transit" && win.mode !== "poofed"
                && cat.x < ox + modelData.width && cat.x + win.catW > ox
                && cat.y < oy + modelData.height && cat.y + win.catH > oy
            readonly property string sheet: "file://" + win.assetsDir + "/naruto/naruto_sheet_3x.png"
            readonly property string propSheet: "file://" + win.assetsDir + "/cat/cat_sheet_3x.png"

            // the log left behind by a jutsu
            Item {
                x: win.logX - pane.ox
                y: win.logY - pane.oy + win.catH - win.propH
                width: win.catW
                height: win.propH
                clip: true
                opacity: win.logOpacity
                visible: win.logOpacity > 0 && x > -width && x < pane.width && y > -height && y < pane.height
                Image {
                    source: pane.propSheet
                    smooth: false
                    x: -win.logFrame * win.catW
                    y: -win.props["log"].row * win.propH
                }
            }

            // shadow clones: copies of him, cheering alongside
            Repeater {
                model: win.clones
                Item {
                    required property int index
                    x: cat.x + win.cloneDx(index) - pane.ox
                    y: cat.y - pane.oy
                    width: win.catW
                    height: win.catH
                    clip: true
                    visible: pane.here
                    transform: Scale { origin.x: win.catW / 2; xScale: index % 2 === 0 ? -cat.facing : cat.facing }
                    Image {
                        source: pane.sheet
                        smooth: false
                        x: -win.frame * win.catW
                        y: -cat.anim.row * win.catH
                    }
                }
            }

            Item {
                id: view
                x: cat.x - pane.ox
                y: cat.y - pane.oy
                width: win.catW
                height: win.catH
                visible: pane.here || grabber.pressed

                Item {
                    id: body
                    anchors.fill: parent
                    transform: [
                        Scale {
                            origin.x: body.width / 2
                            xScale: win.mode === "held" ? 1 : cat.facing  // the dangle is face-on
                        },
                        Scale {
                            origin.x: body.width / 2
                            origin.y: body.height
                            yScale: 1 - squash.amount
                            xScale: 1 + squash.amount * 0.6
                        },
                        Rotation {
                            // held: swinging from the collar. Otherwise about his
                            // middle: spinning away, flipping off a wall, or turned
                            // a quarter so his feet are on the wall he's running up
                            origin.x: win.mode === "held" ? cat.grabX : cat.width / 2
                            origin.y: win.mode === "held" ? cat.grabY : cat.height / 2
                            angle: win.mode === "held" ? cat.sway
                                 : win.mode === "launched" ? cat.spin
                                 : win.mode === "wallrun" ? -90 * cat.facing : win.flip
                        }
                    ]
                    Item {
                        anchors.fill: parent
                        clip: true
                        Image {
                            source: pane.sheet
                            smooth: false
                            x: -win.frame * win.catW
                            y: -cat.anim.row * win.catH
                        }
                    }
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
                    onCanceled: win.release()
                }
            }

            // smoke, in front of him, and the ドロン floating off a big one
            Repeater {
                model: win.puffs
                Item {
                    required property var modelData
                    readonly property var p: modelData
                    readonly property var pa: win.props["smoke"]
                    readonly property int k: Math.floor((p.big ? p.t / 0.4 : p.t) * pa.frames)
                    x: p.x - pane.ox
                    y: p.y - pane.oy + win.catH - win.propH
                    width: win.catW
                    height: win.propH
                    visible: p.t < 1 && x > -width - 60 && x < pane.width + 60 && y > -height - 60 && y < pane.height
                    Item {
                        anchors.fill: parent
                        clip: true
                        visible: parent.k < parent.pa.frames
                        Image {
                            source: pane.propSheet
                            smooth: false
                            x: -Math.min(parent.parent.k, parent.parent.pa.frames - 1) * win.catW
                            y: -parent.parent.pa.row * win.propH
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

            // what he has to say: above his head, kept inside the monitor
            Rectangle {
                id: bubble
                readonly property var tint: ({ fail: "#f28b82", pass: "#7ce38b", merge: "#f0c419",
                                               run: "#6fc8f5", down: "#8888aa" })[win.bubbleKind] || "#ffffff"
                visible: win.bubbleText !== "" && pane.here && win.mode !== "held" && win.mode !== "launched"
                width: Math.min(line.implicitWidth, 380) + 20
                height: line.implicitHeight + 14
                x: Math.max(8, Math.min(pane.width - width - 8, view.x + view.width / 2 - width / 2))
                y: Math.max(8, view.y - height - 2)
                color: "#1a1a2e"
                border.color: tint
                border.width: 3
                Text {
                    id: line
                    x: 10; y: 7
                    width: Math.min(implicitWidth, 380)
                    wrapMode: Text.Wrap
                    text: win.bubbleText
                    color: "#ffffff"
                    font.family: "Noto Sans CJK JP"
                    font.pixelSize: 14
                }
            }

            // the little star at the top of the desk where he was thrown out
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
}
