#!/usr/bin/env node
// Tests for view/grading.js: answers typed through mozc should grade on
// what was meant, not on which width or punctuation the IME picked.
//   node scripts/grading_test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs.readFileSync(path.join(__dirname, "..", "view", "grading.js"), "utf8")
const G = {}
vm.runInNewContext(src.replace(".pragma library", ""), G)

const card = (...answers) => ({ answers, hint: null })
const cases = [
    // [answers, typed, expected]
    [["さいしゅう", "saishuu"], "さいしゅう", true],
    [["さいしゅう", "saishuu"], " さい しゅう　", true],           // spaces, ASCII and full-width
    [["さいしゅう", "saishuu"], "SAISHUU", true],                   // case
    [["さいしゅう", "saishuu"], "ｓａｉｓｈｕｕ", true],             // full-width romaji
    [["3じ", "さんじ"], "３じ", true],                              // mozc's full-width digit
    [["サンプル"], "ｻﾝﾌﾟﾙ", true],                                  // half-width katakana
    [["あしたピザをたべます"], "あしたピザをたべます。", true],      // trailing 。
    [["いつまでに？"], "いつまでに?", true],                        // ASCII ? for ？
    [["いつまでに"], "いつまでに！？", true],
    [["どっちにしても、いそがしいです"], "どっちにしてもいそがしいです", true],  // a comma either way
    [["さいしゅう", "saishuu"], "０", false],                       // the give-up
    [["さいしゅう", "saishuu"], "0", false],
    [["さいしゅう", "saishuu"], "さいしゅうてき", false],
    [["もとめる"], "もとめ", false],
    [["こと"], "", false],
    [["。"], "。", true],                                          // degenerate, but self-consistent
]

let fails = 0
for (const [answers, typed, want] of cases) {
    const got = G.isCorrect(card(...answers), typed)
    if (got !== want) fails++
    console.log(`${got === want ? "ok  " : "FAIL"}  ${JSON.stringify(typed)} vs ${JSON.stringify(answers)}: ${got}`)
}
const h = G.hintFor(card("さいしゅう"))
if (!h.includes("さ")) { fails++; console.log("FAIL  hintFor fallback: " + h) } else console.log("ok    hintFor fallback: " + h)
const rare = G.hintFor(card("𠮟る"))
if (rare !== "「𠮟…」ではじまります") { fails++; console.log("FAIL  hintFor rare kanji: " + rare) } else console.log("ok    hintFor rare kanji: " + rare)
console.log(fails ? `${fails} failed` : `all ${cases.length + 2} passed`)
process.exit(fails ? 1 : 0)
