// Wind-up detector for throwing the cat away: two full circles and the
// fling, as ONE smooth motion. Pure (state in, state out, no QML types),
// so scripts/spin_test.js runs it under node exactly as the view does.
//
// A circle is measured by how far the direction the hand is travelling
// turns, so its size and centre don't matter: two circles = 720° of
// turning one way. Slowing to a crawl, shaking back and forth, or carrying
// on without throwing all start it over; circling back the other way unwinds it.
.pragma library

var TURNS = 2
var SHORT_BY = 0.9   // rad (~50°): the second circle may come up this short
var MIN_SPEED = 350  // px/s: the hand keeps moving at least this fast...
var STALL_MS = 150   // ...never dipping below it for longer than this
var SAMPLE_PX = 8    // the heading is sampled every this many px of travel
var BENDING = 0.008  // rad per sample: less is travelling straight (radius > 1000 px)
var REVERSAL = 2.0   // rad (~115°) in one sample: a shake, not a circle
var FRESH_MS = 350   // the throw comes within this long of the last turning

function fresh(px, py, now) {
    return { turn: 0, heading: null, ax: px, ay: py, lastFast: now, lastTurn: now }
}

// One hand position while held. `speed` is the view's smoothed hand speed.
function track(s, px, py, now, speed) {
    if (speed >= MIN_SPEED) {
        s.lastFast = now
    } else if (now - s.lastFast > STALL_MS) {
        s.turn = 0  // the motion broke
        s.heading = null
        s.ax = px
        s.ay = py
        return s
    }
    var dx = px - s.ax, dy = py - s.ay
    if (Math.sqrt(dx * dx + dy * dy) < SAMPLE_PX)
        return s
    s.ax = px
    s.ay = py
    var h = Math.atan2(dy, dx)
    if (s.heading === null) {
        s.heading = h
        return s
    }
    var d = h - s.heading
    while (d > Math.PI) d -= 2 * Math.PI
    while (d <= -Math.PI) d += 2 * Math.PI
    s.heading = h
    // spun up, then kept going without throwing: it has to start over
    if (now - s.lastTurn > FRESH_MS)
        s.turn = 0
    if (Math.abs(d) > REVERSAL) {
        s.turn = 0
        return s
    }
    if (Math.abs(d) < BENDING)
        return s
    s.lastTurn = now
    // signed: a circle one way and one back cancel out, and a wobbly hand's
    // little backward steps just shave a bit off
    s.turn += d
    return s
}

// Let go now: was that two circles straight into the throw?
function charged(s, now) {
    return Math.abs(s.turn) >= TURNS * 2 * Math.PI - SHORT_BY
        && now - s.lastTurn < FRESH_MS
        && now - s.lastFast < STALL_MS
}
