// Bromodachi question bank.
// Each entry: prompt shown in the bubble, and every accepted answer
// (kana / kanji / romaji all count, case-insensitive; spacing is ignored).
// Optional `hint`: revealed with F1, written in N5 Japanese. Reading
// questions carry the meaning, since the prompt alone gives you nothing to
// hang the reading on — but never the reading itself, or the hint is the
// answer. Entries with no `hint` fall back to the answer's first character.
// Optional `ja: false`: leave the IME in English for this question.
//
// Only BANK is ever asked. Older lessons live in RETIRED below; move a
// section back up into BANK to start being asked it again.
.pragma library

var BANK = [
    // --- lesson 2026-09-01, vocabulary ---
    { type: "reading", prompt: "「選ぶ」はなんと読みますか？", hint: "ＡとＢ、どちらか ひとつ とること", answers: ["えらぶ", "erabu"] },
    { type: "reading", prompt: "「決める」はなんと読みますか？", hint: "「これに します」と いうこと", answers: ["きめる", "kimeru"] },
    { type: "reading", prompt: "「着る」はなんと読みますか？", hint: "ふくを からだに つけること", answers: ["きる", "kiru"] },
    { type: "reading", prompt: "「下着」はなんと読みますか？", hint: "シャツや ズボンの なかに きる もの", answers: ["したぎ", "shitagi"] },
    { type: "reading", prompt: "「職場」はなんと読みますか？", hint: "しごとを する ところ", answers: ["しょくば", "shokuba"] },
    { type: "reading", prompt: "「防波堤」はなんと読みますか？", hint: "うみの なみを とめる ながい かべ", answers: ["ぼうはてい", "bouhatei", "bohatei"] },
    { type: "en2ja", prompt: "How do you say \"to choose / to select\"?", answers: ["えらぶ", "選ぶ", "erabu", "えらびます", "選びます", "erabimasu"] },
    { type: "en2ja", prompt: "How do you say \"to decide\"?", answers: ["きめる", "決める", "kimeru", "きめます", "決めます", "kimemasu"] },
    { type: "en2ja", prompt: "How do you say \"free / not busy\"?", answers: ["ひま", "暇", "hima", "ひまです", "暇です"] },
    { type: "en2ja", prompt: "How do you say \"to hold\"?", answers: ["もつ", "持つ", "motsu", "もちます", "持ちます", "mochimasu"] },
    { type: "en2ja", prompt: "How do you say \"to wear\"?", answers: ["きる", "着る", "kiru", "きます", "着ます", "kimasu"] },
    { type: "en2ja", prompt: "How do you say \"socks\"?", answers: ["くつした", "靴下", "kutsushita"] },
    { type: "en2ja", prompt: "How do you say \"underwear\"?", answers: ["したぎ", "下着", "shitagi"] },
    { type: "en2ja", prompt: "How do you say \"workplace\"?", answers: ["しょくば", "職場", "shokuba"] },
    { type: "en2ja", prompt: "How do you say \"breakwater\"?", answers: ["ぼうはてい", "防波堤", "bouhatei", "bohatei"] },

    // --- lesson 2026-09-01, conjugation: もつ ---
    { type: "conj", prompt: "「もつ」のて形は？", hint: "てに とる こと", answers: ["もって", "持って", "motte"] },
    { type: "conj", prompt: "「もつ」のます形は？", hint: "てに とる こと", answers: ["もちます", "持ちます", "mochimasu"] },
    { type: "conj", prompt: "「えらぶ」のて形は？", hint: "ぶ → んで", answers: ["えらんで", "選んで", "erande"] },
    { type: "conj", prompt: "「きめる」のて形は？", hint: "「これに します」と いうこと", answers: ["きめて", "決めて", "kimete"] },

    // --- lesson 2026-09-01, grammar: 〜か (whether or not) ---
    { type: "grammar", prompt: "\"I have not decided yet.\"", hint: "まだ ＋ Ｖて形 ＋ いません", answers: ["まだきめていません", "まだ決めていません", "madakimeteimasen", "まだきめてません"] },
    { type: "grammar", prompt: "\"I haven't decided whether I'll go.\"（〜か）", hint: "じしょ形 ＋ か、まだ きめて いません", answers: ["いくか、まだきめていません", "いくかまだきめていません", "行くか、まだ決めていません", "行くかまだ決めていません"] },
    { type: "grammar", prompt: "\"I haven't decided whether I'll eat.\"（〜か）", hint: "じしょ形 ＋ か、まだ きめて いません", answers: ["たべるか、まだきめていません", "たべるかまだきめていません", "食べるか、まだ決めていません", "食べるかまだ決めていません"] },
    { type: "grammar", prompt: "\"I haven't decided if I'll rollerblade home after work tomorrow.\"", hint: "あした しごとの あと ＋ ローラーブレードで ＋ かえるか、まだ〜", answers: ["あしたしごとのあとローラーブレードでかえるか、まだきめていません", "あしたしごとのあとローラーブレードでかえるかまだきめていません", "明日仕事のあとローラーブレードで帰るか、まだ決めていません", "明日仕事の後ローラーブレードで帰るか、まだ決めていません"] },

    // --- lesson 2026-09-01, grammar: 〜とき ---
    { type: "grammar", prompt: "\"when going to work\"（〜とき）", hint: "かいしゃに ＋ じしょ形 ＋ とき", answers: ["かいしゃにいくとき", "会社に行くとき", "kaishaniikutoki"] },
    { type: "grammar", prompt: "\"when I wear socks\"（〜とき）", hint: "くつしたを ＋ じしょ形 ＋ とき", answers: ["くつしたをきるとき", "靴下を着るとき", "くつしたをはくとき", "靴下をはくとき"] },

    // --- lesson 2026-09-01, grammar: もっていく / もってくる ---
    { type: "grammar", prompt: "\"to bring (something from here to somewhere)\"", hint: "もって ＋ 「ここ→むこう」の うごき", answers: ["もっていく", "持っていく", "もっていきます", "持っていきます", "motteiku", "motteikimasu"] },
    { type: "grammar", prompt: "\"to bring (something from somewhere to here)\"", hint: "もって ＋ 「むこう→ここ」の うごき", answers: ["もってくる", "持ってくる", "もってきます", "持ってきます", "mottekuru", "mottekimasu"] },
    { type: "grammar", prompt: "「ここ→むこう」は もっていく。「むこう→ここ」は？", answers: ["もってくる", "持ってくる", "もってきます", "持ってきます", "mottekuru", "mottekimasu"] },
    { type: "grammar", prompt: "\"Tomorrow I'll take shorts to work.\"", hint: "あした、しごとに ＋ ショーツを ＋ もって〜", answers: ["あした、しごとにショーツをもっていきます", "あしたしごとにショーツをもっていきます", "明日、仕事にショーツを持っていきます", "明日仕事にショーツを持っていきます"] },
    { type: "grammar", prompt: "\"Please bring it here.\"（もって〜）", hint: "もって ＋ きて ＋ ください", answers: ["もってきてください", "持ってきてください", "もってきて", "持ってきて"] },
    { type: "grammar", prompt: "\"to take (something) and come back\"", hint: "とって ＋ 「むこう→ここ」の うごき", answers: ["とってくる", "とってきます", "tottekuru", "tottekimasu"] },
    { type: "grammar", prompt: "\"to buy (something) and come back\"", hint: "かって ＋ 「むこう→ここ」の うごき", answers: ["かってくる", "買ってくる", "かってきます", "買ってきます", "kattekuru", "kattekimasu"] },
    { type: "grammar", prompt: "\"I'll go buy socks and come back.\"", hint: "くつしたを ＋ かって ＋ きます", answers: ["くつしたをかってきます", "靴下を買ってきます", "くつしたをかってくる", "靴下を買ってくる"] },
]

// Previous lessons — kept for reference, never asked. Move a section back
// into BANK to re-enable it.
var RETIRED = [
    // --- lesson 2026-08-27: business trip / schedule / sending designs ---
    { type: "reading", prompt: "「出張」はなんと読みますか？", hint: "しごとで ほかの まちへ いくこと", answers: ["しゅっちょう", "shucchou", "shutchou", "shuccho", "shutcho"] },
    { type: "reading", prompt: "「予定」はなんと読みますか？", hint: "これから すること", answers: ["よてい", "yotei"] },
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
    { type: "en2ja", prompt: "How do you say \"the first half\"?", answers: ["ぜんはん", "前半", "zenhan"] },
    { type: "en2ja", prompt: "How do you say \"the last half\"?", answers: ["こうはん", "後半", "kouhan", "kohan"] },
    { type: "en2ja", prompt: "How do you say \"to send\"?", answers: ["おくる", "送る", "okuru"] },
    { type: "en2ja", prompt: "How do you say \"to start\"?", answers: ["はじめる", "始める", "hajimeru"] },

    // --- lesson 2026-08-28, vocabulary ---
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
    { type: "en2ja", prompt: "How do you say \"raw egg\"?", answers: ["なまたまご", "生卵", "namatamago"] },
    { type: "en2ja", prompt: "How do you say \"to get drunk\"?", answers: ["よっぱらう", "酔っ払う", "yopparau"] },
    { type: "en2ja", prompt: "How do you say \"choices / options\"?", answers: ["せんたくし", "選択肢", "sentakushi"] },
    { type: "en2ja", prompt: "How do you say \"stingy\"?", answers: ["けち", "kechi"] },
    { type: "en2ja", prompt: "How do you say \"sample\"?", answers: ["サンプル", "さんぷる", "sanpuru"] },
    { type: "en2ja", prompt: "How do you say \"to count\"?", answers: ["かぞえる", "数える", "kazoeru"] },
    { type: "en2ja", prompt: "How do you say \"maths\"?", answers: ["すうがく", "数学", "suugaku", "sugaku"] },
    { type: "en2ja", prompt: "How do you say \"to advance / progress\"?", answers: ["すすむ", "進む", "susumu"] },
    { type: "en2ja", prompt: "How do you say \"deadline\"?", answers: ["しめきり", "締め切り", "shimekiri", "きげん", "期限", "kigen"] },
    { type: "en2ja", prompt: "How do you say \"to arrive\"?", answers: ["つく", "着く", "tsuku"] },
    { type: "en2ja", prompt: "How do you say \"on time\"?", answers: ["じかんどおりに", "時間通りに", "jikandoorini", "jikandorini"] },
    { type: "en2ja", prompt: "How do you say \"By when?\"", answers: ["いつまでに", "いつまでに？", "itsumadeni"] },
    { type: "en2ja", prompt: "How do you say \"how much / how long?\"", answers: ["どのぐらい", "どのくらい", "donogurai", "donokurai"] },

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
    { type: "grammar", prompt: "\"It's not that I don't like coffee.\"", hint: "〜じゃない ＋ わけじゃない", answers: ["コーヒーがすきじゃないわけじゃない", "コーヒーが好きじゃないわけじゃない", "こーひーがすきじゃないわけじゃない"] },
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

// The entry's own hint with no first-character fallback. Used once the
// answer is already on screen, where "starts with り…" is noise but the
// meaning is the thing actually worth remembering.
function meaningFor(entry) {
    return entry.hint ? entry.hint : ""
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
