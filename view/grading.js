// Pure grading + hint helpers for the pop-up view. No I/O, no QML types:
// this file runs under node for testing exactly as it runs in the view.
.pragma library

// What the IME chose is noise, not the answer: spaces of any width (chunked
// answers come with or without them), full-width letters and digits (mozc
// types ３ for 3), half-width katakana, commas, a trailing 。/！/？, and
// case. NFKC folds the widths (and U+3000 into a plain space) first.
function normalize(s) {
    return s.normalize("NFKC")
        .replace(/\s+/g, "")
        .replace(/[、,]/g, "")
        .replace(/[。.!?]+$/, "")
        .toLowerCase()
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
    // the first whole character: a rare kanji (𠮟) is two UTF-16 units
    return a.length > 0 ? "「" + Array.from(a)[0] + "…」ではじまります" : ""
}

// The entry's own hint with no first-character fallback. Used once the
// answer is already on screen, where "starts with り…" is noise but the
// meaning is the thing actually worth remembering.
function meaningFor(entry) {
    return entry.hint ? entry.hint : ""
}
