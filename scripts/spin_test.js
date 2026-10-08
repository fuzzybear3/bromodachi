#!/usr/bin/env node
// Tests for view/spin.js, the throw-away wind-up detector: synthetic hand
// paths at a real mouse's event rate, smoothed the way cat.qml smooths them.
//   node scripts/spin_test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs.readFileSync(path.join(__dirname, "..", "view", "spin.js"), "utf8")
const Spin = {}
vm.runInNewContext(src.replace(".pragma library", ""), Spin)

const DT = 8 // ms between mouse events

// Feed a path (a function of time in ms -> {x, y}) for `ms`, then report
// whether letting go right at the end would count as wound up.
function run(pathAt, ms, { noise = 0, seed = 1 } = {}) {
    let rnd = seed
    const jitter = () => ((rnd = (rnd * 16807) % 2147483647) / 2147483647 - 0.5) * 2 * noise
    let p = pathAt(0)
    const s = Spin.fresh(p.x, p.y, 0)
    let vx = 0, vy = 0
    for (let t = DT; t <= ms; t += DT) {
        const q = pathAt(t)
        q.x += jitter(); q.y += jitter()
        // cat.qml drag(): exponentially smoothed hand velocity
        vx = 0.6 * vx + 0.4 * (q.x - p.x) / (DT / 1000)
        vy = 0.6 * vy + 0.4 * (q.y - p.y) / (DT / 1000)
        Spin.track(s, q.x, q.y, t, Math.hypot(vx, vy))
        p = q
    }
    return Spin.charged(s, ms)
}

// a circle of radius r at `speed` px/s, clockwise (dir 1) or not (-1)
const circle = (r, speed, dir = 1) => t => {
    const a = dir * (speed / r) * (t / 1000)
    return { x: 500 + r * Math.cos(a), y: 500 + r * Math.sin(a) }
}
const revs = (n, r, speed) => (n * 2 * Math.PI * r) / speed * 1000 // ms for n turns

// stitch paths end to end: [[pathAt, ms], ...], each piece starting where the last ended
function chain(pieces) {
    const total = pieces.reduce((a, [, ms]) => a + ms, 0)
    const at = t => {
        let off = { x: 0, y: 0 }, t0 = 0
        for (const [f, ms] of pieces) {
            const start = f(0)
            if (t <= t0 + ms) {
                const q = f(t - t0)
                return { x: q.x - start.x + off.x, y: q.y - start.y + off.y }
            }
            const end = f(ms)
            off = { x: end.x - start.x + off.x, y: end.y - start.y + off.y }
            t0 += ms
        }
        return off
    }
    return [at, total]
}
const still = () => () => ({ x: 0, y: 0 })
const line = (vx, vy) => t => ({ x: vx * t / 1000, y: vy * t / 1000 })

const cases = [
    ["two brisk circles", true, circle(150, 1500), revs(2.05, 150, 1500)],
    ["two circles the other way", true, circle(150, 1500, -1), revs(2.05, 150, 1500)],
    ["two big slow circles", true, circle(400, 600), revs(2.05, 400, 600)],
    ["two small quick circles", true, circle(60, 1200), revs(2.1, 60, 1200)],
    ["two circles with a shaky hand (seed 1)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 1 }],
    ["two circles with a shaky hand (seed 2)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 2 }],
    ["two circles with a shaky hand (seed 3)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 3 }],
    ["two circles with a shaky hand (seed 4)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 4 }],
    ["two circles with a shaky hand (seed 5)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 5 }],
    ["two circles with a shaky hand (seed 6)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 6 }],
    ["two circles with a shaky hand (seed 7)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 7 }],
    ["two circles with a shaky hand (seed 8)", true, circle(150, 1500), revs(2.05, 150, 1500), { noise: 2, seed: 8 }],
    ["five circles, then throw", true, circle(150, 1500), revs(5, 150, 1500)],
    ["a slightly short second circle", true, circle(150, 1500), revs(1.9, 150, 1500)],
    ["only one and a half", false, circle(150, 1500), revs(1.5, 150, 1500)],
    ["one and three quarters", false, circle(150, 1500), revs(1.75, 150, 1500)],
    ["two circles too slowly", false, circle(150, 250), revs(2.05, 150, 250)],
    ["shaking side to side", false, t => ({ x: 500 + 200 * Math.sin(t / 1000 * 2 * Math.PI * 6), y: 500 }), 2000],
    ["one each way", false, ...chain([[circle(150, 1500), revs(1, 150, 1500)], [circle(150, 1500, -1), revs(1.05, 150, 1500)]])],
    ["two circles, then carry on straight", false, ...chain([[circle(150, 1500), revs(2.05, 150, 1500)], [line(1500, 0), 500]])],
    ["two circles, stop, then let go", false, ...chain([[circle(150, 1500), revs(2.05, 150, 1500)], [still(), 250]])],
    ["stop halfway, then only one more", false, ...chain([[circle(150, 1500), revs(1, 150, 1500)], [still(), 250], [circle(150, 1500), revs(1.05, 150, 1500)]])],
    ["stop halfway, then two fresh ones", true, ...chain([[circle(150, 1500), revs(1, 150, 1500)], [still(), 250], [circle(150, 1500), revs(2.1, 150, 1500)]])],
]

let fails = 0
for (const [name, want, f, ms, opts] of cases) {
    const got = run(f, ms, opts)
    const ok = got === want
    if (!ok) fails++
    console.log(`${ok ? "ok  " : "FAIL"}  ${name}: ${got ? "wound up" : "not wound up"}`)
}
console.log(fails ? `${fails} failed` : `all ${cases.length} passed`)
process.exit(fails ? 1 : 0)
