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
