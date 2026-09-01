// Pure grading + hint helpers for the pop-up view. No I/O, no QML types:
// this file runs under node for testing exactly as it runs in the view.
.pragma library

// spacing is noise: chunked answers may be typed with ASCII or full-width
// spaces (or none), so compare with all whitespace stripped.
function normalize(s) {
    return s.replace(/[\s　]+/g, "").toLowerCase()
}

function isCorrect(entry, text) {
    var a = normalize(text)
    for (var i = 0; i < entry.answers.length; i++)
        if (normalize(entry.answers[i]) === a)
            return true
    return false
}

// F1 hint: the entry's own hint if it has one, otherwise just the opening
// character of the answer — enough to unstick you without giving it away.
function hintFor(entry) {
    if (entry.hint)
        return entry.hint
    var a = entry.answers.length > 0 ? entry.answers[0] : ""
    return a.length > 0 ? "「" + a.charAt(0) + "…」ではじまります" : ""
}

// The entry's own hint with no first-character fallback. Used once the
// answer is already on screen, where "starts with り…" is noise but the
// meaning is the thing actually worth remembering.
function meaningFor(entry) {
    return entry.hint ? entry.hint : ""
}
