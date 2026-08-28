// Bromodachi question bank.
// Each entry: prompt shown in the bubble, and every accepted answer
// (kana / kanji / romaji all count, case-insensitive; spacing is ignored).
// Optional `hint`: revealed with F1, written in N5 Japanese. Reading
// questions carry the meaning, since the prompt alone gives you nothing to
// hang the reading on — but never the reading itself, or the hint is the
// answer. Entries with no `hint` fall back to the answer's first character.
// Optional `ja: false`: leave the IME in English for this question.
.pragma library

var BANK = [
    // --- lesson 2026-08-27: business trip / schedule / sending designs ---
    { type: "reading", prompt: "「出張」はなんと読みますか？", hint: "しごとで ほかの まちへ いくこと", answers: ["しゅっちょう", "shucchou", "shutchou", "shuccho", "shutcho"] },
    { type: "reading", prompt: "「予定」はなんと読みますか？", hint: "これから すること", answers: ["よてい", "yotei"] },
    { type: "reading", prompt: "「決める」はなんと読みますか？", hint: "「これに します」と いうこと", answers: ["きめる", "kimeru"] },
    { type: "reading", prompt: "「前半」はなんと読みますか？", hint: "はじめの はんぶん", answers: ["ぜんはん", "zenhan"] },
    { type: "reading", prompt: "「後半」はなんと読みますか？", hint: "あとの はんぶん", answers: ["こうはん", "kouhan", "kohan"] },
    { type: "reading", prompt: "「週間」はなんと読みますか？", hint: "７日を かぞえる ことば", answers: ["しゅうかん", "shuukan", "shukan"] },
    { type: "reading", prompt: "「中国」はなんと読みますか？", hint: "となりの おおきい くに", answers: ["ちゅうごく", "chuugoku", "chugoku"] },
    { type: "reading", prompt: "「会社」はなんと読みますか？", hint: "はたらく ところ", answers: ["かいしゃ", "kaisha"] },
    { type: "reading", prompt: "「設計」はなんと読みますか？", hint: "つくる まえに かんがえて かくこと", answers: ["せっけい", "sekkei"] },
    { type: "reading", prompt: "「基板」はなんと読みますか？", hint: "コンピューターの なかの みどりの いた", answers: ["きばん", "kiban"] },
    { type: "reading", prompt: "「便利」はなんと読みますか？", hint: "つかいやすくて いいこと", answers: ["べんり", "benri"] },
    { type: "reading", prompt: "「始める」はなんと読みますか？", hint: "「おわる」の はんたい", answers: ["はじめる", "hajimeru"] },
    { type: "reading", prompt: "「終わる」はなんと読みますか？", hint: "「はじめる」の はんたい", answers: ["おわる", "owaru"] },
    { type: "reading", prompt: "「送る」はなんと読みますか？", hint: "メールや にもつを だすこと", answers: ["おくる", "okuru"] },
    { type: "en2ja", prompt: "How do you say \"business trip\"?", answers: ["しゅっちょう", "出張", "shucchou", "shutchou", "shuccho", "shutcho"] },
    { type: "en2ja", prompt: "How do you say \"schedule / plan\"?", answers: ["よてい", "予定", "yotei"] },
    { type: "en2ja", prompt: "How do you say \"to decide\"?", answers: ["きめる", "決める", "kimeru"] },
    { type: "en2ja", prompt: "How do you say \"the first half\"?", answers: ["ぜんはん", "前半", "zenhan"] },
    { type: "en2ja", prompt: "How do you say \"the last half\"?", answers: ["こうはん", "後半", "kouhan", "kohan"] },
    { type: "en2ja", prompt: "How do you say \"to send\"?", answers: ["おくる", "送る", "okuru"] },
    { type: "en2ja", prompt: "How do you say \"to start\"?", answers: ["はじめる", "始める", "hajimeru"] },
    { type: "en2ja", prompt: "How do you say \"to finish\"?", answers: ["おわる", "終わる", "owaru"] },
    { type: "en2ja", prompt: "How do you say \"convenient\"?", answers: ["べんり", "便利", "benri"] },

    // --- lesson 2026-08-28, vocabulary ---
    { type: "reading", prompt: "「生ビール」はなんと読みますか？", hint: "おみせで のむ つめたい おさけ", answers: ["なまビール", "なまびーる", "namabiiru", "namabiru"] },
    { type: "reading", prompt: "「生卵」はなんと読みますか？", hint: "やいていない たまご", answers: ["なまたまご", "namatamago"] },
    { type: "reading", prompt: "「酔っ払う」はなんと読みますか？", hint: "おさけを たくさん のんで ふらふら すること", answers: ["よっぱらう", "yopparau"] },
    { type: "reading", prompt: "「選択肢」はなんと読みますか？", hint: "「Ａか Ｂか Ｃか」えらぶ もの", answers: ["せんたくし", "sentakushi"] },
    { type: "reading", prompt: "「数える」はなんと読みますか？", hint: "「１、２、３…」と いうこと", answers: ["かぞえる", "kazoeru"] },
    { type: "reading", prompt: "「数学」はなんと読みますか？", hint: "かずの べんきょう", answers: ["すうがく", "suugaku", "sugaku"] },
    { type: "reading", prompt: "「進む」はなんと読みますか？", hint: "まえへ いくこと", answers: ["すすむ", "susumu"] },
    { type: "reading", prompt: "「遅れる」はなんと読みますか？", hint: "じかんに まにあわないこと", answers: ["おくれる", "okureru"] },
    { type: "reading", prompt: "「締め切り」はなんと読みますか？", hint: "「この ひまでに してください」の ひ", answers: ["しめきり", "shimekiri"] },
    { type: "reading", prompt: "「期限」はなんと読みますか？", hint: "いつまでに するか きめた とき", answers: ["きげん", "kigen"] },
    { type: "reading", prompt: "「着く」はなんと読みますか？", hint: "その ばしょに くること", answers: ["つく", "tsuku"] },
    { type: "reading", prompt: "「少ない」はなんと読みますか？", hint: "「おおくない」と おなじ", answers: ["すくない", "sukunai"] },
    { type: "reading", prompt: "「少し」はなんと読みますか？", hint: "「ちょっと」と おなじ", answers: ["すこし", "sukoshi"] },
    { type: "reading", prompt: "「時間通りに」はなんと読みますか？", hint: "おくれないで、ちょうど その じかんに", answers: ["じかんどおりに", "jikandoorini", "jikandorini"] },
    { type: "reading", prompt: "「大きさ」はなんと読みますか？", hint: "おおきいか ちいさいか", answers: ["おおきさ", "ookisa", "okisa"] },
    { type: "reading", prompt: "「量」はなんと読みますか？", hint: "おおいか すくないか", answers: ["りょう", "ryou", "ryo"] },
    { type: "en2ja", prompt: "How do you say \"draft beer\"?", answers: ["なまビール", "生ビール", "なまびーる", "namabiiru", "namabiru"] },
    { type: "en2ja", prompt: "How do you say \"raw egg\"?", answers: ["なまたまご", "生卵", "namatamago"] },
    { type: "en2ja", prompt: "How do you say \"to get drunk\"?", answers: ["よっぱらう", "酔っ払う", "yopparau"] },
    { type: "en2ja", prompt: "How do you say \"choices / options\"?", answers: ["せんたくし", "選択肢", "sentakushi"] },
    { type: "en2ja", prompt: "How do you say \"stingy\"?", answers: ["けち", "kechi"] },
    { type: "en2ja", prompt: "How do you say \"sample\"?", answers: ["サンプル", "さんぷる", "sanpuru"] },
    { type: "en2ja", prompt: "How do you say \"to count\"?", answers: ["かぞえる", "数える", "kazoeru"] },
    { type: "en2ja", prompt: "How do you say \"maths\"?", answers: ["すうがく", "数学", "suugaku", "sugaku"] },
    { type: "en2ja", prompt: "How do you say \"to advance / progress\"?", answers: ["すすむ", "進む", "susumu"] },
    { type: "en2ja", prompt: "How do you say \"to be delayed\"?", answers: ["おくれる", "遅れる", "okureru", "おくれています", "遅れています"] },
    { type: "en2ja", prompt: "How do you say \"deadline\"?", answers: ["しめきり", "締め切り", "shimekiri", "きげん", "期限", "kigen"] },
    { type: "en2ja", prompt: "How do you say \"the real deadline\"?", answers: ["ほんとうのしめきり", "本当の締め切り", "hontounoshimekiri"] },
    { type: "en2ja", prompt: "How do you say \"to arrive\"?", answers: ["つく", "着く", "tsuku"] },
    { type: "en2ja", prompt: "How do you say \"on time\"?", answers: ["じかんどおりに", "時間通りに", "jikandoorini", "jikandorini"] },
    { type: "en2ja", prompt: "How do you say \"Exactly!\"?", answers: ["そのとおり", "そのとおり！", "その通り", "sonotoori", "sonotori"] },
    { type: "en2ja", prompt: "How do you say \"So I told you.\"?", answers: ["いったとおりでしょ", "言ったとおりでしょ", "ittatooridesho"] },
    { type: "en2ja", prompt: "How do you say \"By when?\"", answers: ["いつまでに", "いつまでに？", "itsumadeni"] },
    { type: "en2ja", prompt: "How do you say \"By November.\"", answers: ["11がつまでに", "１１月までに", "11月までに", "じゅういちがつまでに", "juuichigatsumadeni"] },
    { type: "en2ja", prompt: "How do you say \"how many?\"", answers: ["いくつ", "ikutsu"] },
    { type: "en2ja", prompt: "How do you say \"how much / how long?\"", answers: ["どのぐらい", "どのくらい", "donogurai", "donokurai"] },
    { type: "en2ja", prompt: "How do you say \"the whole week\"?", answers: ["そのしゅうはずっと", "その週はずっと", "sonoshuuwazutto", "sonoshuuhazutto", "ずっと", "zutto"] },

    // --- lesson 2026-08-28, conjugation ---
    { type: "conj", prompt: "「よっぱらう」のます形は？", hint: "おさけを のんで ふらふら すること", answers: ["よっぱらいます", "酔っ払います", "yopparaimasu"] },
    { type: "conj", prompt: "「よっぱらう」のた形は？", hint: "おさけを のんで ふらふら すること", answers: ["よっぱらった", "酔っ払った", "yopparatta"] },

    // --- lesson 2026-08-28, grammar: V-た＋ばかり (just did) ---
    { type: "grammar", prompt: "「たべる」→ \"just ate\"（V-た＋ばかり）", answers: ["たべたばかり", "食べたばかり", "tabetabakari"] },
    { type: "grammar", prompt: "「くる」→ \"just came\"（V-た＋ばかり）", answers: ["きたばかり", "来たばかり", "kitabakari"] },
    { type: "grammar", prompt: "\"I just finished work.\"（ばかり）", hint: "しごとが ＋ Ｖた形 ＋ ばかりです", answers: ["しごとがおわったばかりです", "仕事が終わったばかりです", "いましごとがおわったばかりです", "おわったばかりです"] },
    { type: "grammar", prompt: "\"I just ate dinner.\"（ばかり）", hint: "ばんごはんを ＋ Ｖた形 ＋ ばかりです", answers: ["ばんごはんをたべたばかりです", "晩ご飯を食べたばかりです", "ばんごはんをたべたばかりだよ", "たべたばかりです"] },

    // --- lesson 2026-08-28, grammar: V-ないと いけません (must) ---
    { type: "grammar", prompt: "\"I must go.\"（V-ないと〜）", answers: ["いかないといけません", "行かないといけません", "ikanaitoikemasen"] },
    { type: "grammar", prompt: "\"I must arrive.\"（V-ないと〜）", answers: ["つかないといけません", "着かないといけません", "tsukanaitoikemasen"] },
    { type: "grammar", prompt: "\"I must work quickly.\"", hint: "はやく ＋ Ｖない形 ＋ と いけません", answers: ["はやくはたらかないといけません", "早く働かないといけません"] },
    { type: "grammar", prompt: "\"Do I have to go?\"", hint: "Ｖない形 ＋ と いけません ＋ か", answers: ["いかないといけませんか", "いかないといけませんか？", "行かないといけませんか"] },
    { type: "grammar", prompt: "\"I must arrive at work on time.\"", hint: "じかんどおりに ＋ しごとに ＋ つく", answers: ["じかんどおりにしごとにつかないといけません", "時間通りに仕事に着かないといけません"] },

    // --- lesson 2026-08-28, grammar: V-なくても いいです (don't have to) ---
    { type: "grammar", prompt: "\"I don't have to go.\"（V-なくても〜）", answers: ["いかなくてもいいです", "行かなくてもいいです", "いかなくてももんだいないです", "いかなくてもだいじょうぶです"] },
    { type: "grammar", prompt: "\"I don't have to eat.\"（V-なくても〜）", answers: ["たべなくてもいいです", "食べなくてもいいです", "tabenakutemoiidesu"] },
    { type: "grammar", prompt: "\"I don't have to eat snacks this week.\"", hint: "こんしゅうは ＋ おかしを ＋ Ｖなくても いいです", answers: ["こんしゅうはおかしをたべなくてもいいです", "今週はお菓子を食べなくてもいいです"] },
    { type: "grammar", prompt: "「いく」→ \"even if I don't go\"", answers: ["いかなくても", "行かなくても", "ikanakutemo"] },

    // --- lesson 2026-08-28, grammar: advice / should ---
    { type: "grammar", prompt: "\"It's better not to go.\"", hint: "Ｖない形 ＋ ほうが いいです", answers: ["いかないほうがいいです", "行かない方がいいです", "ikanaihougaiidesu"] },
    { type: "grammar", prompt: "\"I should go.\"（辞書形＋〜）", hint: "じしょ形 ＋ べきです", answers: ["いくべきです", "行くべきです", "ikubekidesu"] },
    { type: "grammar", prompt: "「たべる」→ \"should eat\"（〜べき）", answers: ["たべるべきです", "食べるべきです", "たべるべき", "taberubekidesu"] },

    // --- lesson 2026-08-28, grammar: misc ---
    { type: "grammar", prompt: "\"It's not that I don't like coffee.\"", hint: "〜じゃない ＋ わけじゃない", answers: ["コーヒーがすきじゃないわけじゃない", "コーヒーが好きじゃないわけじゃない"] },
    { type: "grammar", prompt: "\"I will eat pizza tomorrow.\"", hint: "あした ＋ ます形（みらいも ます形）", answers: ["あしたピザをたべます", "明日ピザを食べます", "あしたぴざをたべます"] },
    { type: "grammar", prompt: "「少ない」は りょう？ おおきさ？", hint: "「ひとが すくない」と いいます", answers: ["りょう", "量", "ryou", "ryo"] },
    { type: "grammar", prompt: "「小さい」は りょう？ おおきさ？", hint: "「かばんが ちいさい」と いいます", answers: ["おおきさ", "大きさ", "ookisa", "okisa"] },
]

function randomIndex(except) {
    var n = Math.floor(Math.random() * BANK.length)
    if (BANK.length > 1 && n === except)
        n = (n + 1) % BANK.length
    return n
}

// F1 hint: the entry's own hint if it has one, otherwise just the opening
// character of the answer — enough to unstick you without giving it away.
function hintFor(entry) {
    if (entry.hint)
        return entry.hint
    var a = entry.answers.length > 0 ? entry.answers[0] : ""
    return a.length > 0 ? "「" + a.charAt(0) + "…」ではじまります" : ""
}

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
