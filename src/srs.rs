//! Spaced repetition: SM-2-lite state updates and a tiered picker. Pure
//! functions: the caller passes in the clock and the recent answer history,
//! so every test is deterministic.
//!
//! Reworked 2026-09-25 after reviewing ~450 answers (9/14-9/24). The old
//! picker split pops between "newest lesson" and "everything else", then ran
//! a weighted lottery inside each pool:
//! - a missed card was one ticket among ~25, so the 10-minute comeback almost
//!   never happened (2 of 119 re-asks after a miss came within 30 min). Re-asked
//!   within 3 h, a missed card was right 72% of the time; later, 17-43%.
//! - "newest" meant the latest class date, so a lesson added after a later-
//!   dated one was filed as old and starved.
//! - a card's odds depended on how many others happened to share its pool.
//!
//! Now: strict tiers, least-remembered first, a fixed number of learning
//! slots, and new cards in the order their lessons were added.
//!
//! All tunables live in this one block.

use crate::api::Question;
use std::collections::{HashMap, HashSet};

/// learning steps after each correct answer before graduating (minutes).
/// Shortened 2026-09-21 from [10,30,90,240,480] (user report: one card asked
/// 15x in 6 days): at ~20-40 pops/day a 6-correct ladder that fully resets on
/// every slip never lets anything leave rotation.
const LEARNING_STEPS_MIN: [f64; 3] = [10.0, 60.0, 240.0]; // 10m, 1h, 4h
/// first post-learning interval (minutes) — one day, on the 4th correct
const GRADUATE_MIN: f64 = 1440.0;
/// streak at which a card leaves the learning steps
const GRADUATE_REPS: i32 = LEARNING_STEPS_MIN.len() as i32 + 1;
const EASE_START: f64 = 2.5;
const EASE_MIN: f64 = 1.3;
const EASE_WRONG_DELTA: f64 = 0.2;
/// each correct answer wins back half a lapse, so one bad week is not a
/// permanent difficulty mark (the classic SM-2 "ease hell")
const EASE_RIGHT_DELTA: f64 = 0.1;
/// interval cap: 90 days
const MAX_INTERVAL_MIN: f64 = 129_600.0;
/// ±10% jitter on due times so items don't clump
const DUE_JITTER: f64 = 0.10;
/// a graduated card grows by the time that actually passed, not by its
/// schedule: S' = S + t·(ease − 1). On time that is S·ease, as before; asked
/// early (a spare pop) it barely grows; remembered late it grows more. The
/// credit stops at 4 intervals so one lucky guess can't launch it for months.
const LATE_CREDIT_CAP: f64 = 4.0;
/// a right answer given after F1 earns half the growth and no ease back
const HINT_GROWTH: f64 = 0.5;
/// cards worked through the learning steps at once (user pick, 2026-09-25).
/// A missed card only sticks if it comes back within hours, and ~40 pops a
/// day spread over 28 learning cards brought each back about once a day.
const LEARNING_SLOTS: usize = 6;
/// a card sits out until this many other answers have gone by
const RECENT_GAP: usize = 3;
/// asks per card per rolling 24 h (the なんにんか report: ~60 asks of one
/// card). A clean card graduates in 4 asks, 5 after a first-sight miss; 6
/// leaves room for one slip. A capped card steps out of its learning slot.
const DAILY_CAP: usize = 6;
/// kanji readings get a lane of their own (user request, 2026-10-08, when 26
/// of a week's 97 answers were kanji): at most one answer in KANJI_ONE_IN
/// over a rolling 24 h, and one learning slot beside LEARNING_SLOTS, so a
/// kanji card waiting for its turn never holds up the other new cards.
const KANJI_ONE_IN: usize = 8;
const KANJI_SLOTS: usize = 1;
const DAY_MS: i64 = 86_400_000;

#[derive(Clone, Debug, PartialEq)]
pub struct SrsState {
    pub due_at_ms: i64,
    pub interval_min: f64,
    pub ease: f64,
    pub reps: i32,
    pub lapses: i32,
    pub last_correct: bool,
    pub updated_at_ms: i64,
}

/// One graded answer -> the item's next state. `jitter` is a caller-supplied
/// value in [-1, 1] (tests pass 0; production passes a random draw).
pub fn srs_update(prev: Option<&SrsState>, correct: bool, hint: bool, now_ms: i64, jitter: f64) -> SrsState {
    let (interval, ease, reps, lapses) = match prev {
        // first sight is the introduction, right or wrong. Most first sights
        // are misses (18% right, 9/14-9/24): the drill that follows is where
        // the card gets learned, so a miss here is no lapse and costs no ease
        None => (LEARNING_STEPS_MIN[0], EASE_START, if correct { 1 } else { 0 }, 0),
        Some(p) if correct => {
            // a learning card skips the steps it has already outlasted: right
            // after an hour it goes to the 4 h step, right after four hours
            // it graduates. At a dozen answers a day most gaps are hours
            // long, and climbing one step per answer kept cards in their
            // slots for days (replayed 2026-10-07: 14 of the last 35 answers
            // were steps this would have skipped).
            // The 10-minute step is never skipped: it is the quick check on
            // a card that was just missed.
            let gap = (now_ms - p.updated_at_ms) as f64 / 60_000.0;
            let outlasted = LEARNING_STEPS_MIN.iter().skip(1).filter(|step| gap >= **step).count() as i32;
            let reps = if p.reps < GRADUATE_REPS && outlasted > 0 {
                (p.reps + 1).max(outlasted + 2).min(GRADUATE_REPS)
            } else {
                p.reps + 1
            };
            let interval = if reps < GRADUATE_REPS {
                LEARNING_STEPS_MIN[reps as usize - 1]
            } else if reps == GRADUATE_REPS {
                GRADUATE_MIN
            } else {
                let elapsed = ((now_ms - p.updated_at_ms) as f64 / 60_000.0)
                    .clamp(0.0, LATE_CREDIT_CAP * p.interval_min);
                let credit = if hint { HINT_GROWTH } else { 1.0 };
                (p.interval_min + elapsed * (p.ease - 1.0) * credit).round().min(MAX_INTERVAL_MIN)
            };
            let ease = if hint { p.ease } else { (p.ease + EASE_RIGHT_DELTA).min(EASE_START) };
            (interval, ease, reps, p.lapses)
        }
        // a slip costs half the streak, not all of it, but always drops the
        // card back into the learning steps: it comes back in 10 minutes and
        // the next right answer re-graduates it at one day at most
        Some(p) => (
            LEARNING_STEPS_MIN[0],
            (p.ease - EASE_WRONG_DELTA).max(EASE_MIN),
            (p.reps / 2).min(GRADUATE_REPS - 1),
            p.lapses + 1,
        ),
    };
    SrsState {
        due_at_ms: now_ms + (interval * 60_000.0 * (1.0 + DUE_JITTER * jitter)).round() as i64,
        interval_min: interval,
        ease,
        reps,
        lapses,
        last_correct: correct,
        updated_at_ms: now_ms,
    }
}

/// How far a card is into its interval: 1.0 at due_at, 2.0 at twice its
/// interval. Predicted recall is 0.9^overdue (90% at due, falling after), so
/// the most overdue card is the least remembered one.
fn overdue(s: &SrsState, now_ms: i64) -> f64 {
    let span = (s.due_at_ms - s.updated_at_ms).max(60_000) as f64;
    (now_ms - s.updated_at_ms).max(0) as f64 / span
}

/// The eligible card furthest into its interval; `due_only` keeps only cards
/// at or past due.
fn furthest<'a>(cards: &[(&'a Question, f64)], due_only: bool, ok: &dyn Fn(&Question) -> bool) -> Option<&'a Question> {
    cards
        .iter()
        .filter(|(q, o)| ok(q) && (!due_only || *o >= 1.0))
        .max_by(|a, b| a.1.total_cmp(&b.1))
        .map(|(q, _)| *q)
}

/// A card that shows kanji to be read. Whole words and radicals alike have
/// this type; every other type is asked and answered in kana or English.
fn is_kanji(q: &Question) -> bool {
    q.qtype == "reading"
}

/// May a kanji card be asked now? Only while kanji stays within one answer
/// in KANJI_ONE_IN over the last 24 h, this one included: the first comes
/// after seven other answers, the second after fifteen. A kanji question
/// shown last and never answered (skipped) counts as asked.
fn kanji_open(bank: &[Question], history: &[(String, i64)], now_ms: i64, except: Option<&str>) -> bool {
    let kanji: HashSet<&str> = bank.iter().filter(|q| is_kanji(q)).map(|q| q.id.as_str()).collect();
    let day: Vec<&str> = history.iter().filter(|(_, at)| now_ms - at < DAY_MS).map(|(id, _)| id.as_str()).collect();
    let skipped = except.filter(|id| day.first() != Some(id));
    let asked = day.len() + skipped.iter().count();
    let of_them = day.iter().chain(skipped.iter()).filter(|id| kanji.contains(*id)).count();
    KANJI_ONE_IN * (of_them + 1) <= asked + 1
}

/// The bank sorted the way the picker sees it.
struct Deck<'a> {
    /// learning cards holding a slot in either lane, with how far each is
    /// into its step
    slots: Vec<(&'a Question, f64)>,
    /// cards in the learning steps, slot or not (capped ones sit out):
    /// everything but kanji, then kanji
    learning: usize,
    kanji_learning: usize,
    graduated: Vec<(&'a Question, f64)>,
    /// unseen cards in the order they get introduced
    unseen: Vec<&'a Question>,
}

/// asks per card over the last 24 h
fn asks_today(history: &[(String, i64)], now_ms: i64) -> HashMap<&str, usize> {
    let mut asks: HashMap<&str, usize> = HashMap::new();
    for (id, at) in history {
        if now_ms - at < DAY_MS {
            *asks.entry(id.as_str()).or_default() += 1;
        }
    }
    asks
}

fn deck<'a>(bank: &'a [Question], srs: &HashMap<String, SrsState>, asks: &HashMap<&str, usize>, now_ms: i64) -> Deck<'a> {
    let capped = |q: &Question| asks.get(q.id.as_str()).copied().unwrap_or(0) >= DAILY_CAP;
    let mut learning = vec![];
    let mut graduated = vec![];
    let mut unseen = vec![];
    for q in bank {
        match srs.get(&q.id) {
            None => unseen.push(q),
            Some(s) if s.reps < GRADUATE_REPS => {
                if !capped(q) {
                    learning.push((q, s.updated_at_ms, overdue(s, now_ms)));
                }
            }
            Some(s) => graduated.push((q, overdue(s, now_ms))),
        }
    }
    learning.sort_by_key(|(_, answered, _)| std::cmp::Reverse(*answered));
    // the lesson added most recently first, then lesson order
    unseen.sort_by(|a, b| {
        b.lesson_added_ms
            .cmp(&a.lesson_added_ms)
            .then_with(|| b.lesson.cmp(&a.lesson))
            .then_with(|| a.position.cmp(&b.position))
    });
    let lane = |kanji: bool| learning.iter().filter(move |(q, _, _)| is_kanji(q) == kanji);
    Deck {
        slots: lane(false)
            .take(LEARNING_SLOTS)
            .chain(lane(true).take(KANJI_SLOTS))
            .map(|(q, _, o)| (*q, *o))
            .collect(),
        learning: lane(false).count(),
        kanji_learning: lane(true).count(),
        graduated,
        unseen,
    }
}

/// Pick the next question. The first tier with a candidate wins; inside a
/// tier the least-remembered card goes first. No dice.
///
///   A  learning  a card holding a learning slot, its step due
///   B  new       the next unseen card with a free slot in its lane
///   C  review    a graduated card past due
///   D  spare     nothing needs asking: a graduated card early, else a new
///                card past the slot limit, else a learning card early
///
/// Slots go to the learning cards answered most recently, so a card being
/// worked keeps its slot until it graduates. Kanji readings have a lane of
/// their own: KANJI_SLOTS beside the LEARNING_SLOTS, and in every tier they
/// sit out while kanji is over its share of the day's answers (`kanji_open`).
/// `history` is recent answers, newest first, covering at least 24 h: a card
/// among the last RECENT_GAP answers, or asked DAILY_CAP times in 24 h, sits
/// out. `except` is the question shown last, answered or not. The buddy
/// never goes silent: if every card sits out, the least-remembered one is
/// asked anyway, a kanji card only when nothing else is left.
pub fn select<'a>(
    bank: &'a [Question],
    srs: &HashMap<String, SrsState>,
    history: &[(String, i64)],
    now_ms: i64,
    except: Option<&str>,
) -> &'a Question {
    assert!(!bank.is_empty(), "select on empty bank");
    let asks = asks_today(history, now_ms);
    let capped = |q: &Question| asks.get(q.id.as_str()).copied().unwrap_or(0) >= DAILY_CAP;
    let recent: Vec<&str> = history.iter().take(RECENT_GAP).map(|(id, _)| id.as_str()).chain(except).collect();
    let kanji_open = kanji_open(bank, history, now_ms, except);
    let in_share = |q: &Question| kanji_open || !is_kanji(q);
    let ok = |q: &Question| !recent.contains(&q.id.as_str()) && !capped(q) && in_share(q);

    let d = deck(bank, srs, &asks, now_ms);
    let slot_free = |q: &Question| if is_kanji(q) { d.kanji_learning < KANJI_SLOTS } else { d.learning < LEARNING_SLOTS };
    let new_card = d.unseen.iter().copied().find(|q| ok(q));

    furthest(&d.slots, true, &ok)
        .or_else(|| d.unseen.iter().copied().find(|q| ok(q) && slot_free(q)))
        .or_else(|| furthest(&d.graduated, true, &ok))
        .or_else(|| furthest(&d.graduated, false, &ok))
        .or(new_card)
        .or_else(|| furthest(&d.slots, false, &ok))
        .unwrap_or_else(|| {
            // everything sits out: ask the least-remembered card that
            // wasn't just shown (unseen counts as least remembered)
            let all: Vec<(&Question, f64)> = bank
                .iter()
                .map(|q| (q, srs.get(&q.id).map_or(f64::INFINITY, |s| overdue(s, now_ms))))
                .collect();
            let not_last = |q: &Question| Some(q.id.as_str()) != except;
            furthest(&all, false, &|q| not_last(q) && in_share(q))
                .or_else(|| furthest(&all, false, &not_last))
                .unwrap_or(&bank[0])
        })
}

/// The card `select` would introduce next, slot free or not (the bar's
/// "New word"). Kanji keeps to its share here too: while it is over, the
/// next card of another kind is given instead. `except` is the question
/// shown last: a new card that was just skipped steps aside unless it is the
/// only one left.
pub fn next_new<'a>(
    bank: &'a [Question],
    srs: &HashMap<String, SrsState>,
    history: &[(String, i64)],
    now_ms: i64,
    except: Option<&str>,
) -> Option<&'a Question> {
    let kanji_open = kanji_open(bank, history, now_ms, except);
    let d = deck(bank, srs, &HashMap::new(), now_ms);
    let mut fits = d.unseen.iter().copied().filter(|q| kanji_open || !is_kanji(q));
    let first = fits.next()?;
    if Some(first.id.as_str()) != except {
        return Some(first);
    }
    fits.next().or(Some(first))
}

/// The queue as the bar shows it, counted the way `select` sees it.
#[derive(Debug, PartialEq, serde::Serialize)]
pub struct Queue {
    /// cards in the learning steps, kanji aside; `slots` of them are worked
    /// at once
    pub learning: usize,
    pub slots: usize,
    /// kanji cards in the learning steps (their lane works one at a time)
    pub kanji_learning: usize,
    /// slot cards whose step is due
    pub due: usize,
    /// graduated cards past due
    pub late: usize,
    /// the lesson added last: class date, cards, cards seen, cards graduated
    pub lesson: String,
    pub lesson_total: usize,
    pub lesson_started: usize,
    pub lesson_graduated: usize,
}

pub fn queue(bank: &[Question], srs: &HashMap<String, SrsState>, history: &[(String, i64)], now_ms: i64) -> Queue {
    let d = deck(bank, srs, &asks_today(history, now_ms), now_ms);
    let newest = bank.iter().map(|q| (q.lesson_added_ms, q.lesson.as_str())).max().map_or("", |(_, l)| l);
    let in_lesson = |q: &&Question| q.lesson == newest;
    let state = |q: &Question| srs.get(&q.id);
    Queue {
        learning: d.learning,
        slots: LEARNING_SLOTS,
        kanji_learning: d.kanji_learning,
        due: d.slots.iter().filter(|(_, o)| *o >= 1.0).count(),
        late: d.graduated.iter().filter(|(_, o)| *o >= 1.0).count(),
        lesson: newest.to_string(),
        lesson_total: bank.iter().filter(in_lesson).count(),
        lesson_started: bank.iter().filter(in_lesson).filter(|q| state(q).is_some()).count(),
        lesson_graduated: bank.iter().filter(in_lesson).filter(|q| state(q).is_some_and(|s| s.reps >= GRADUATE_REPS)).count(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_000_000_000_000;
    const MIN: i64 = 60_000;

    fn q(id: &str, lesson: &str) -> Question {
        qa(id, lesson, "2026-09-01T00:00:00Z", 0)
    }

    /// a question whose lesson was added at `added` (ISO), at `position`
    fn qa(id: &str, lesson: &str, added: &str, position: i32) -> Question {
        typed(id, "en2ja", lesson, added, position)
    }

    /// a kanji reading
    fn kanji(id: &str, lesson: &str, position: i32) -> Question {
        typed(id, "reading", lesson, "2026-09-01T00:00:00Z", position)
    }

    fn typed(id: &str, qtype: &str, lesson: &str, added: &str, position: i32) -> Question {
        serde_json::from_value(serde_json::json!({
            "id": id, "type": qtype, "prompt": id, "answers": ["a"],
            "hint": null, "ja": true, "position": position,
            "lesson": {"taught_on": lesson, "created_at": added},
        }))
        .unwrap()
    }

    /// `n` answers to other cards, the newest `first_ago` minutes old
    fn answers(n: usize, first_ago: i64) -> Vec<(String, i64)> {
        (0..n).map(|i| (format!("other{i}"), NOW - (first_ago + i as i64) * MIN)).collect()
    }

    /// last answered `ago` minutes before NOW, due `interval` minutes after that
    fn st(reps: i32, interval: f64, ago: f64) -> SrsState {
        let answered = NOW - (ago * MIN as f64) as i64;
        SrsState {
            due_at_ms: answered + (interval * MIN as f64) as i64,
            interval_min: interval,
            ease: 2.5,
            reps,
            lapses: 0,
            last_correct: true,
            updated_at_ms: answered,
        }
    }

    fn srs_of(entries: &[(&str, SrsState)]) -> HashMap<String, SrsState> {
        entries.iter().map(|(id, s)| (id.to_string(), s.clone())).collect()
    }

    fn pick<'a>(bank: &'a [Question], srs: &HashMap<String, SrsState>, history: &[(String, i64)]) -> &'a str {
        select(bank, srs, history, NOW, None).id.as_str()
    }

    #[test]
    fn learning_ladder_then_growth_on_time() {
        let mut t = NOW;
        let mut s = srs_update(None, true, false, t, 0.0);
        assert_eq!((s.interval_min, s.reps), (10.0, 1));
        assert_eq!(s.due_at_ms, t + 10 * MIN);
        for expect in [60.0, 240.0, 1440.0] {
            t = s.due_at_ms;
            s = srs_update(Some(&s), true, false, t, 0.0);
            assert_eq!(s.interval_min, expect);
        }
        assert_eq!(s.reps, 4); // graduated: 1 day
        // answered exactly on time, growth matches the old S * ease
        t = s.due_at_ms;
        s = srs_update(Some(&s), true, false, t, 0.0);
        assert_eq!(s.interval_min, 3600.0);
        t = s.due_at_ms;
        s = srs_update(Some(&s), true, false, t, 0.0);
        assert_eq!(s.interval_min, 9000.0);
    }

    #[test]
    fn growth_follows_the_real_gap() {
        let grad = st(5, 1440.0, 0.0); // answered at NOW, 1-day interval
        let at = |minutes: i64| srs_update(Some(&grad), true, false, NOW + minutes * MIN, 0.0).interval_min;
        assert_eq!(at(144), 1440.0 + 144.0 * 1.5); // a spare pop, early: barely grows
        assert_eq!(at(2880), 1440.0 + 2880.0 * 1.5); // remembered late: grows more
        assert_eq!(at(30 * 1440), 1440.0 + 4.0 * 1440.0 * 1.5); // credit caps at 4 intervals
        assert_eq!(at(-5), 1440.0); // clock skew never shrinks it
    }

    #[test]
    fn hint_halves_growth_and_keeps_ease() {
        let mut grad = st(5, 1440.0, 0.0);
        grad.ease = 2.0;
        let helped = srs_update(Some(&grad), true, true, NOW + 1440 * MIN, 0.0);
        assert_eq!(helped.interval_min, 1440.0 + 1440.0 * 1.0 * 0.5);
        assert_eq!(helped.ease, 2.0);
        let clean = srs_update(Some(&grad), true, false, NOW + 1440 * MIN, 0.0);
        assert_eq!(clean.interval_min, 1440.0 + 1440.0 * 1.0);
        assert!((clean.ease - 2.1).abs() < 1e-9);
    }

    #[test]
    fn interval_caps_at_90_days() {
        let mut s = srs_update(None, true, false, NOW, 0.0);
        for _ in 0..30 {
            s = srs_update(Some(&s), true, false, s.due_at_ms, 0.0);
        }
        assert_eq!(s.interval_min, 129_600.0);
    }

    #[test]
    fn first_sight_miss_is_an_introduction() {
        let s = srs_update(None, false, false, NOW, 0.0);
        assert_eq!((s.interval_min, s.reps, s.lapses, s.ease), (10.0, 0, 0, EASE_START));
        // the second miss is a real lapse
        let again = srs_update(Some(&s), false, false, NOW + 10 * MIN, 0.0);
        assert_eq!((again.lapses, again.ease), (1, 2.3));
    }

    #[test]
    fn lapse_relearns_then_regraduates_at_a_day() {
        let mut s = st(7, 9000.0, 9000.0);
        let lapsed = srs_update(Some(&s), false, false, NOW, 0.0);
        // streak of 7 halves to 3; back in 10 minutes
        assert_eq!((lapsed.interval_min, lapsed.reps, lapsed.lapses), (10.0, 3, 1));
        assert_eq!(lapsed.ease, 2.3);
        let back = srs_update(Some(&lapsed), true, false, lapsed.due_at_ms, 0.0);
        assert_eq!((back.interval_min, back.reps), (1440.0, 4));
        // a long streak still lands in the learning steps, not at "graduated
        // with a 10-minute interval"
        s.reps = 12;
        assert_eq!(srs_update(Some(&s), false, false, NOW, 0.0).reps, 3);
        let mut e = lapsed;
        for _ in 0..20 {
            e = srs_update(Some(&e), false, false, NOW, 0.0);
        }
        assert_eq!(e.ease, EASE_MIN); // floors, never below
    }

    #[test]
    fn a_missed_card_comes_back_before_anything_else() {
        let bank = vec![q("missed", "2026-09-14"), q("review", "2026-09-15"), q("new", "2026-09-15")];
        let srs = srs_of(&[
            ("missed", st(0, 10.0, 15.0)), // 10-min step, 15 min ago
            ("review", st(5, 1440.0, 4000.0)), // graduated, well overdue
        ]);
        assert_eq!(pick(&bank, &srs, &[]), "missed");
        // not yet due: the free slot lets the new card in ahead of the review
        let srs = srs_of(&[("missed", st(0, 10.0, 5.0)), ("review", st(5, 1440.0, 4000.0))]);
        assert_eq!(pick(&bank, &srs, &[]), "new");
    }

    #[test]
    fn new_cards_wait_for_a_free_slot() {
        let mut bank: Vec<Question> = (0..6).map(|i| q(&format!("l{i}"), "2026-09-14")).collect();
        bank.push(q("review", "2026-09-15"));
        bank.push(q("new", "2026-09-15"));
        // six cards mid-ladder, none due: slots full, so the due review goes
        let mut srs: HashMap<String, SrsState> = (0..6).map(|i| (format!("l{i}"), st(2, 60.0, 30.0))).collect();
        srs.insert("review".into(), st(5, 1440.0, 2000.0));
        assert_eq!(pick(&bank, &srs, &[]), "review");
        // one graduates: a slot opens and the new card is next
        srs.insert("l0".into(), st(4, 1440.0, 0.0));
        assert_eq!(pick(&bank, &srs, &[]), "new");
    }

    #[test]
    fn slots_go_to_the_cards_worked_on_most_recently() {
        // eight learning cards, all due; the two answered longest ago wait
        let bank: Vec<Question> = (0..8).map(|i| q(&format!("l{i}"), "2026-09-14")).collect();
        let srs: HashMap<String, SrsState> =
            (0..8).map(|i| (format!("l{i}"), st(0, 10.0, 60.0 + 600.0 * i as f64))).collect();
        // l7 and l6 are the most overdue, but hold no slot
        assert_eq!(pick(&bank, &srs, &[]), "l5");
    }

    #[test]
    fn new_cards_enter_by_when_their_lesson_was_added() {
        // the 9/19 report: 9/14 notes arrived after the 9/15 lesson
        let bank = vec![
            qa("sep15_a", "2026-09-15", "2026-09-14T21:09:25Z", 0),
            qa("sep14_b", "2026-09-14", "2026-09-19T20:09:56Z", 1),
            qa("sep14_a", "2026-09-14", "2026-09-19T20:09:56Z", 0),
        ];
        assert_eq!(pick(&bank, &HashMap::new(), &[]), "sep14_a");
    }

    #[test]
    fn reviews_go_least_remembered_first() {
        let bank = vec![q("strong", "2026-09-15"), q("weak", "2026-09-15")];
        let srs = srs_of(&[
            ("strong", st(7, 4320.0, 5760.0)), // 3-day interval, 1 day late: 1.33
            ("weak", st(5, 1440.0, 2160.0)),   // 1-day interval, 12 h late: 1.5
        ]);
        assert_eq!(pick(&bank, &srs, &[]), "weak");
    }

    #[test]
    fn spare_pops_ask_the_least_remembered_card_early() {
        // the 2026-09-17 report: spare pops kept landing on mastered cards
        let bank = vec![q("mastered", "2026-09-15"), q("shaky", "2026-09-15")];
        let srs = srs_of(&[
            ("mastered", st(9, 20000.0, 2000.0)), // 10% into its interval
            ("shaky", st(4, 1440.0, 1000.0)),      // 69% into its interval
        ]);
        assert_eq!(pick(&bank, &srs, &[]), "shaky");
    }

    #[test]
    fn recent_and_daily_capped_cards_sit_out() {
        let bank = vec![q("a", "2026-09-15"), q("b", "2026-09-15")];
        let srs = srs_of(&[("a", st(0, 10.0, 60.0)), ("b", st(0, 10.0, 30.0))]);
        let h = |id: &str, ago: i64| (id.to_string(), NOW - ago * MIN);
        let others = || vec![h("x", 1), h("y", 2), h("z", 3)];
        assert_eq!(pick(&bank, &srs, &[]), "a"); // furthest past its step
        // a was among the last few answers: b goes instead
        assert_eq!(pick(&bank, &srs, &[h("a", 1)]), "b");
        // a has had its six asks today
        let capped: Vec<_> = (0..6).map(|i| h("a", 60 + 100 * i)).collect();
        assert_eq!(pick(&bank, &srs, &[others(), capped].concat()), "b");
        // asks older than 24 h don't count
        let stale: Vec<_> = (0..6).map(|i| h("a", 1500 + i)).collect();
        assert_eq!(pick(&bank, &srs, &[others(), stale].concat()), "a");
    }

    #[test]
    fn a_capped_card_gives_up_its_slot() {
        let mut bank: Vec<Question> = (0..6).map(|i| q(&format!("l{i}"), "2026-09-14")).collect();
        bank.push(q("new", "2026-09-15"));
        bank.push(q("known", "2026-09-15"));
        let mut srs: HashMap<String, SrsState> = (0..6).map(|i| (format!("l{i}"), st(2, 60.0, 30.0))).collect();
        srs.insert("known".into(), st(6, 4320.0, 60.0));
        let h = |id: &str, ago: i64| (id.to_string(), NOW - ago * MIN);
        let mut history = vec![h("x", 1), h("y", 2), h("z", 3)];
        assert_eq!(pick(&bank, &srs, &history), "known"); // slots full: a spare pop
        history.extend((0..6).map(|i| h("l0", 30 + 60 * i)));
        assert_eq!(pick(&bank, &srs, &history), "new");
    }

    #[test]
    fn never_goes_silent() {
        let solo = vec![q("a", "2026-09-01")];
        let srs = srs_of(&[("a", st(5, 1440.0, 1.0))]);
        assert_eq!(select(&solo, &srs, &[("a".into(), NOW)], NOW, Some("a")).id, "a");
        // with an alternative, the one just shown is skipped even when both sit out
        let two = vec![q("a", "2026-09-01"), q("b", "2026-09-01")];
        let h: Vec<(String, i64)> = vec![("b".into(), NOW), ("a".into(), NOW - MIN)];
        assert_eq!(select(&two, &srs, &h, NOW, Some("b")).id, "a");
    }

    #[test]
    fn a_right_answer_skips_the_steps_it_outlasted() {
        let missed = srs_update(None, false, false, NOW, 0.0);
        let right_after = |minutes: i64| {
            let s = srs_update(Some(&missed), true, false, NOW + minutes * MIN, 0.0);
            (s.reps, s.interval_min)
        };
        assert_eq!(right_after(10), (1, 10.0)); // on time: one step
        assert_eq!(right_after(45), (1, 10.0)); // the 10-minute check is never skipped
        assert_eq!(right_after(90), (3, 240.0)); // outlasted the hour: on to the 4 h step
        assert_eq!(right_after(450), (4, 1440.0)); // outlasted 4 h: graduates
        // further up the ladder a long gap never costs a step
        let third = st(3, 240.0, 30.0);
        assert_eq!(srs_update(Some(&third), true, false, NOW, 0.0).reps, 4);
        // a miss after any gap still drops back to 10 minutes
        let slip = srs_update(Some(&missed), false, false, NOW + 450 * MIN, 0.0);
        assert_eq!((slip.reps, slip.interval_min), (0, 10.0));
        // graduated cards grow by their own rule, one rep at a time
        let grad = st(5, 1440.0, 3000.0);
        assert_eq!(srs_update(Some(&grad), true, false, NOW, 0.0).reps, 6);
    }

    #[test]
    fn kanji_stays_within_one_answer_in_eight() {
        let bank = vec![kanji("k", "2026-09-30", 0), q("word", "2026-09-30")];
        // both in learning; the kanji card is far more overdue
        let srs = srs_of(&[("k", st(1, 10.0, 600.0)), ("word", st(1, 10.0, 20.0))]);
        // six answers today: a kanji card now would be 1 in 7
        assert_eq!(pick(&bank, &srs, &answers(6, 30)), "word");
        // seven: it would be 1 in 8
        assert_eq!(pick(&bank, &srs, &answers(7, 30)), "k");
        // one kanji answer already today: the second waits for fifteen answers
        let with_kanji = |others: usize| [answers(others, 30), vec![("k".to_string(), NOW - 500 * MIN)]].concat();
        assert_eq!(pick(&bank, &srs, &with_kanji(13)), "word");
        assert_eq!(pick(&bank, &srs, &with_kanji(14)), "k");
        // answers older than a day count for nothing
        assert_eq!(pick(&bank, &srs, &answers(7, 1500)), "word");
    }

    #[test]
    fn a_skipped_kanji_question_counts_as_asked() {
        let bank = vec![kanji("k1", "2026-09-30", 0), kanji("k2", "2026-09-30", 1), q("word", "2026-09-30")];
        let srs = srs_of(&[("k2", st(1, 10.0, 600.0)), ("word", st(1, 10.0, 20.0))]);
        let history = answers(7, 30);
        assert_eq!(select(&bank, &srs, &history, NOW, None).id, "k2");
        // k1 was shown last and skipped: with it, k2 would make 2 in 9
        assert_eq!(select(&bank, &srs, &history, NOW, Some("k1")).id, "word");
    }

    #[test]
    fn kanji_learns_in_its_own_slot() {
        let mut bank: Vec<Question> = (0..5).map(|i| q(&format!("l{i}"), "2026-09-14")).collect();
        bank.push(kanji("k-learning", "2026-09-30", 0));
        bank.push(kanji("k-new", "2026-09-30", 1));
        bank.push(q("new", "2026-09-30"));
        bank.push(q("known", "2026-09-30"));
        let day = answers(40, 30);
        let mut srs: HashMap<String, SrsState> = (0..5).map(|i| (format!("l{i}"), st(2, 60.0, 30.0))).collect();
        srs.insert("k-learning".into(), st(2, 60.0, 30.0));
        srs.insert("known".into(), st(6, 4320.0, 60.0));
        // five words and a kanji card in learning: the kanji card holds no
        // word slot, so the sixth word starts
        assert_eq!(pick(&bank, &srs, &day), "new");
        srs.insert("new".into(), st(2, 60.0, 30.0));
        // both lanes full: nothing new starts, word or kanji
        assert_eq!(pick(&bank, &srs, &day), "known");
        // the kanji card graduates: the next kanji card starts, though the
        // word slots are still full
        srs.insert("k-learning".into(), st(4, 1440.0, 30.0));
        assert_eq!(pick(&bank, &srs, &day), "k-new");
        // unless kanji is over its share for the day
        assert_eq!(pick(&bank, &srs, &answers(3, 30)), "known");
    }

    #[test]
    fn with_nothing_else_left_kanji_is_still_asked() {
        let only = vec![kanji("k1", "2026-09-30", 0), kanji("k2", "2026-09-30", 1)];
        assert_eq!(select(&only, &HashMap::new(), &[], NOW, Some("k1")).id, "k2");
    }

    #[test]
    fn new_word_ignores_the_slot_limit() {
        // six learning cards fill the slots; the bar can still ask for a new one
        let mut bank: Vec<Question> = (0..6).map(|i| q(&format!("l{i}"), "2026-09-14")).collect();
        bank.push(qa("old-new", "2026-09-14", "2026-09-14T00:00:00Z", 0));
        bank.push(qa("n1", "2026-10-05", "2026-10-07T00:00:00Z", 1));
        bank.push(qa("n0", "2026-10-05", "2026-10-07T00:00:00Z", 0));
        let srs: HashMap<String, SrsState> = (0..6).map(|i| (format!("l{i}"), st(2, 60.0, 30.0))).collect();
        assert_eq!(next_new(&bank, &srs, &[], NOW, None).unwrap().id, "n0");
        // the one just skipped steps aside
        assert_eq!(next_new(&bank, &srs, &[], NOW, Some("n0")).unwrap().id, "n1");
        // unless it is the last one
        let solo = vec![q("a", "2026-09-01")];
        assert_eq!(next_new(&solo, &HashMap::new(), &[], NOW, Some("a")).unwrap().id, "a");
        assert!(next_new(&solo, &srs_of(&[("a", st(1, 10.0, 1.0))]), &[], NOW, None).is_none());
    }

    #[test]
    fn new_word_keeps_kanji_to_its_share() {
        let bank = vec![kanji("k", "2026-10-05", 0), qa("word", "2026-10-05", "2026-09-01T00:00:00Z", 1)];
        let none = HashMap::new();
        // kanji over its share: the next card of another kind
        assert_eq!(next_new(&bank, &none, &answers(3, 30), NOW, None).unwrap().id, "word");
        // within it: lesson order
        assert_eq!(next_new(&bank, &none, &answers(7, 30), NOW, None).unwrap().id, "k");
        // only kanji left and over its share: nothing to give
        let only = vec![kanji("k", "2026-10-05", 0)];
        assert!(next_new(&only, &none, &answers(3, 30), NOW, None).is_none());
    }

    #[test]
    fn queue_counts_what_the_picker_sees() {
        let bank = vec![
            qa("due", "2026-09-30", "2026-09-30T00:00:00Z", 0),
            qa("waiting", "2026-09-30", "2026-09-30T00:00:00Z", 1),
            qa("late", "2026-09-30", "2026-09-30T00:00:00Z", 2),
            qa("fresh", "2026-09-30", "2026-09-30T00:00:00Z", 3),
            qa("started", "2026-10-05", "2026-10-07T00:00:00Z", 0),
            qa("done", "2026-10-05", "2026-10-07T00:00:00Z", 1),
            qa("unseen", "2026-10-05", "2026-10-07T00:00:00Z", 2),
        ];
        let srs = srs_of(&[
            ("due", st(2, 60.0, 90.0)),
            ("waiting", st(1, 10.0, 2.0)),
            ("late", st(4, 1440.0, 3000.0)),
            ("fresh", st(5, 4320.0, 60.0)),
            ("started", st(3, 240.0, 30.0)),
            ("done", st(4, 1440.0, 30.0)),
        ]);
        assert_eq!(
            queue(&bank, &srs, &[], NOW),
            Queue {
                learning: 3,
                slots: 6,
                kanji_learning: 0,
                due: 1,
                late: 1,
                lesson: "2026-10-05".into(),
                lesson_total: 3,
                lesson_started: 2,
                lesson_graduated: 1,
            }
        );
    }
}
