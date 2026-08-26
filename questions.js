// Bromodachi question bank.
// Each entry: prompt shown in the bubble, and every accepted answer
// (kana / kanji / romaji all count, case-insensitive).
.pragma library

var BANK = [
    // --- kanji readings ---
    { type: "reading", prompt: "「犬」はなんと読みますか？", answers: ["いぬ", "inu"] },
    { type: "reading", prompt: "「猫」はなんと読みますか？", answers: ["ねこ", "neko"] },
    { type: "reading", prompt: "「水」はなんと読みますか？", answers: ["みず", "mizu"] },
    { type: "reading", prompt: "「山」はなんと読みますか？", answers: ["やま", "yama"] },
    { type: "reading", prompt: "「川」はなんと読みますか？", answers: ["かわ", "kawa"] },
    { type: "reading", prompt: "「日本」はなんと読みますか？", answers: ["にほん", "にっぽん", "nihon", "nippon"] },
    { type: "reading", prompt: "「先生」はなんと読みますか？", answers: ["せんせい", "sensei"] },
    { type: "reading", prompt: "「学生」はなんと読みますか？", answers: ["がくせい", "gakusei"] },
    { type: "reading", prompt: "「食べる」はなんと読みますか？", answers: ["たべる", "taberu"] },
    { type: "reading", prompt: "「友達」はなんと読みますか？", answers: ["ともだち", "tomodachi"] },

    // --- english -> japanese ---
    { type: "en2ja", prompt: "How do you say \"dog\" in Japanese?", answers: ["いぬ", "犬", "inu"] },
    { type: "en2ja", prompt: "How do you say \"cat\" in Japanese?", answers: ["ねこ", "猫", "neko"] },
    { type: "en2ja", prompt: "How do you say \"water\" in Japanese?", answers: ["みず", "水", "mizu"] },
    { type: "en2ja", prompt: "How do you say \"book\" in Japanese?", answers: ["ほん", "本", "hon"] },
    { type: "en2ja", prompt: "How do you say \"thank you\"?", answers: ["ありがとう", "ありがとうございます", "arigatou", "arigato", "arigatou gozaimasu"] },
    { type: "en2ja", prompt: "How do you say \"good morning\"?", answers: ["おはよう", "おはようございます", "ohayou", "ohayo", "ohayou gozaimasu"] },
    { type: "en2ja", prompt: "How do you say \"friend\" in Japanese?", answers: ["ともだち", "友達", "tomodachi"] },
    { type: "en2ja", prompt: "How do you say \"delicious\"?", answers: ["おいしい", "oishii", "うまい", "umai"] },
    { type: "en2ja", prompt: "How do you say \"tomorrow\"?", answers: ["あした", "明日", "ashita"] },
    { type: "en2ja", prompt: "How do you say \"teacher\" in Japanese?", answers: ["せんせい", "先生", "sensei"] },

    // --- lesson 2026-08-27: business trip / schedule / sending designs ---
    { type: "reading", prompt: "「出張」はなんと読みますか？", answers: ["しゅっちょう", "shucchou", "shutchou", "shuccho", "shutcho"] },
    { type: "reading", prompt: "「予定」はなんと読みますか？", answers: ["よてい", "yotei"] },
    { type: "reading", prompt: "「決める」はなんと読みますか？", answers: ["きめる", "kimeru"] },
    { type: "reading", prompt: "「前半」はなんと読みますか？", answers: ["ぜんはん", "zenhan"] },
    { type: "reading", prompt: "「後半」はなんと読みますか？", answers: ["こうはん", "kouhan", "kohan"] },
    { type: "reading", prompt: "「週間」はなんと読みますか？", answers: ["しゅうかん", "shuukan", "shukan"] },
    { type: "reading", prompt: "「中国」はなんと読みますか？", answers: ["ちゅうごく", "chuugoku", "chugoku"] },
    { type: "reading", prompt: "「会社」はなんと読みますか？", answers: ["かいしゃ", "kaisha"] },
    { type: "reading", prompt: "「設計」はなんと読みますか？", answers: ["せっけい", "sekkei"] },
    { type: "reading", prompt: "「基板」はなんと読みますか？", answers: ["きばん", "kiban"] },
    { type: "reading", prompt: "「便利」はなんと読みますか？", answers: ["べんり", "benri"] },
    { type: "reading", prompt: "「始める」はなんと読みますか？", answers: ["はじめる", "hajimeru"] },
    { type: "reading", prompt: "「終わる」はなんと読みますか？", answers: ["おわる", "owaru"] },
    { type: "reading", prompt: "「送る」はなんと読みますか？", answers: ["おくる", "okuru"] },
    { type: "en2ja", prompt: "How do you say \"business trip\"?", answers: ["しゅっちょう", "出張", "shucchou", "shutchou", "shuccho", "shutcho"] },
    { type: "en2ja", prompt: "How do you say \"schedule / plan\"?", answers: ["よてい", "予定", "yotei"] },
    { type: "en2ja", prompt: "How do you say \"to decide\"?", answers: ["きめる", "決める", "kimeru"] },
    { type: "en2ja", prompt: "How do you say \"the first half\"?", answers: ["ぜんはん", "前半", "zenhan"] },
    { type: "en2ja", prompt: "How do you say \"the last half\"?", answers: ["こうはん", "後半", "kouhan", "kohan"] },
    { type: "en2ja", prompt: "How do you say \"to send\"?", answers: ["おくる", "送る", "okuru"] },
    { type: "en2ja", prompt: "How do you say \"to start\"?", answers: ["はじめる", "始める", "hajimeru"] },
    { type: "en2ja", prompt: "How do you say \"to finish\"?", answers: ["おわる", "終わる", "owaru"] },
    { type: "en2ja", prompt: "How do you say \"convenient\"?", answers: ["べんり", "便利", "benri"] },
]

function randomIndex(except) {
    var n = Math.floor(Math.random() * BANK.length)
    if (BANK.length > 1 && n === except)
        n = (n + 1) % BANK.length
    return n
}

function isCorrect(entry, text) {
    var a = text.trim().toLowerCase()
    for (var i = 0; i < entry.answers.length; i++)
        if (entry.answers[i].toLowerCase() === a)
            return true
    return false
}
