//! Spaced repetition: SM-2-lite state updates and the adaptive
//! newest-lesson-biased selector. Pure functions — randomness comes in
//! through the caller's Rng, so every test is deterministic.
//!
//! All tunables live in this one block.

use crate::api::Question;
use rand::Rng;
use std::collections::HashMap;

/// learning steps after each correct answer before graduating (minutes).
/// Shortened 2026-09-21 from [10,30,90,240,480] (user report: one card asked
/// 15x in 6 days): at ~20-40 pops/day a 6-correct ladder that fully resets on
/// every slip never lets anything leave rotation.
const LEARNING_STEPS_MIN: [f64; 3] = [10.0, 60.0, 240.0]; // 10m, 1h, 4h
/// first post-learning interval (minutes) — one day, on the 4th correct
const GRADUATE_MIN: f64 = 1440.0;
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
/// an item on a streak of 5 counts as fully mature. Measured in streak, not
/// interval: at ~40 pops/day intervals never grow (2026-09-20: a lesson with
/// 15 of 22 cards on a 4+ streak scored 7% mature by interval and would have
/// kept 92% of pops from a freshly added, earlier-dated lesson).
const MATURE_REPS: f64 = 4.0;
/// newest-lesson share: clamp(BASE + SPAN·(1−avgMaturity), FLOOR, BASE+SPAN)
/// → 95% of pops while the lesson is fresh, decaying as it matures
const NEWEST_BASE: f64 = 0.5;
const NEWEST_SPAN: f64 = 0.45;
const NEWEST_FLOOR: f64 = 0.25;
/// within-pool draw weights. A pop's priority is strength x difficulty x
/// lateness (see `weight`). The strength term is what retires an item you
/// keep getting right: at ~40 pops/day against a bank whose schedule asks for
/// ~50x that, due-times are all in the past and the due() gate passes nearly
/// everything, so the weight has to carry the whole ordering by itself
/// (2026-09-17: 15 of 26 items were tied at the old clamp ceiling, and the six
/// never-missed items still drew ~10% of pops).
/// unseen sits above any item with a streak, below one you are actively failing
const UNSEEN_WEIGHT: f64 = 3.0;
/// geometric decay per consecutive correct answer, floored after this many
const STRENGTH_DECAY: f64 = 0.6;
const STRENGTH_FLOOR_REPS: i32 = 6;
/// lateness cap, in units of the item's own interval
const OVERDUE_CAP: f64 = 3.0;

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
pub fn srs_update(prev: Option<&SrsState>, correct: bool, now_ms: i64, jitter: f64) -> SrsState {
    let (interval, ease, reps, lapses) = match prev {
        Some(p) => (p.interval_min, p.ease, p.reps, p.lapses),
        None => (0.0, EASE_START, 0, 0),
    };
    let (interval, ease, reps, lapses) = if correct {
        let reps = reps + 1;
        let interval = if (reps as usize) <= LEARNING_STEPS_MIN.len() {
            LEARNING_STEPS_MIN[reps as usize - 1]
        } else if reps as usize == LEARNING_STEPS_MIN.len() + 1 {
            GRADUATE_MIN
        } else {
            (interval * ease).round().min(MAX_INTERVAL_MIN)
        };
        (interval, (ease + EASE_RIGHT_DELTA).min(EASE_START), reps, lapses)
    } else {
        // a slip costs half the streak, not all of it: the item comes back in
        // 10 minutes, then climbs from where half its history puts it
        (LEARNING_STEPS_MIN[0], (ease - EASE_WRONG_DELTA).max(EASE_MIN), reps / 2, lapses + 1)
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

fn maturity(state: Option<&SrsState>) -> f64 {
    state.map(|s| (s.reps as f64 / MATURE_REPS).clamp(0.0, 1.0)).unwrap_or(0.0)
}

/// Probability that a pop draws from the newest lesson, given how mature
/// that lesson's items are. 0.95 for a fresh lesson, decaying as it sticks.
pub fn newest_share(bank: &[Question], srs: &HashMap<String, SrsState>, newest: &str) -> f64 {
    let ms: Vec<f64> = bank
        .iter()
        .filter(|q| q.lesson == newest)
        .map(|q| maturity(srs.get(&q.id)))
        .collect();
    if ms.is_empty() {
        return NEWEST_FLOOR;
    }
    let avg = ms.iter().sum::<f64>() / ms.len() as f64;
    (NEWEST_BASE + NEWEST_SPAN * (1.0 - avg)).clamp(NEWEST_FLOOR, NEWEST_BASE + NEWEST_SPAN)
}

fn due(q: &Question, srs: &HashMap<String, SrsState>, now_ms: i64) -> bool {
    match srs.get(&q.id) {
        None => true, // unseen counts as due
        Some(s) => s.due_at_ms <= now_ms,
    }
}

/// Draw weight for one question: strength x difficulty x lateness.
///
/// - strength: 0.6^min(reps, 6) -- 1.0 for an item with no streak, 0.047 after
///   six straight corrects. Answering right is what pushes an item out of
///   rotation; waiting for its due-time no longer does.
/// - difficulty: 1 + (EASE_START - ease) -- 1.0 for an untarnished item, 2.2 at
///   the ease floor. The durable memory of "this one keeps biting you", which
///   the old weight ignored entirely.
/// - lateness: 1 + clamp(overdue / interval, 0, OVERDUE_CAP). Normalised by the
///   real interval rather than max(interval, 30), so a 10-minute relearn step
///   is not flattened against a 4-hour one.
fn weight(q: &Question, srs: &HashMap<String, SrsState>, now_ms: i64) -> f64 {
    match srs.get(&q.id) {
        None => UNSEEN_WEIGHT,
        Some(s) => {
            let strength = STRENGTH_DECAY.powi(s.reps.clamp(0, STRENGTH_FLOOR_REPS));
            let difficulty = 1.0 + (EASE_START - s.ease).max(0.0);
            let overdue_min = (now_ms - s.due_at_ms) as f64 / 60_000.0;
            let lateness = 1.0 + (overdue_min / s.interval_min.max(1.0)).clamp(0.0, OVERDUE_CAP);
            strength * difficulty * lateness
        }
    }
}

/// Pick the next question. Two due-pools (newest lesson vs everything older),
/// pool chosen by `newest_share`, weighted draw inside the pool. When nothing
/// is due anywhere, the item closest to due is asked: the buddy never goes
/// silent. `except` is the previously shown question, skipped while any
/// alternative exists.
pub fn select<'a, R: Rng>(
    bank: &'a [Question],
    srs: &HashMap<String, SrsState>,
    now_ms: i64,
    except: Option<&str>,
    rng: &mut R,
) -> &'a Question {
    assert!(!bank.is_empty(), "select on empty bank");
    let newest = bank.iter().map(|q| q.lesson.as_str()).max().unwrap_or_default().to_string();

    let mut new_due: Vec<&Question> = vec![];
    let mut old_due: Vec<&Question> = vec![];
    for q in bank {
        if due(q, srs, now_ms) {
            if q.lesson == newest { &mut new_due } else { &mut old_due }.push(q);
        }
    }
    drop_except(&mut new_due, except);
    drop_except(&mut old_due, except);

    let pool: &[&Question] = if new_due.is_empty() && old_due.is_empty() {
        // ahead of schedule everywhere: ask whatever comes due soonest
        let mut all: Vec<&Question> = bank.iter().collect();
        drop_except(&mut all, except);
        return all
            .into_iter()
            .min_by_key(|q| srs.get(&q.id).map(|s| s.due_at_ms).unwrap_or(i64::MIN))
            .expect("bank non-empty");
    } else if old_due.is_empty() {
        &new_due
    } else if new_due.is_empty() {
        &old_due
    } else if rng.gen::<f64>() < newest_share(bank, srs, &newest) {
        &new_due
    } else {
        &old_due
    };

    // weighted draw: unseen items and long-overdue items come up more
    let weights: Vec<f64> = pool.iter().map(|q| weight(q, srs, now_ms)).collect();
    let total: f64 = weights.iter().sum();
    let mut roll = rng.gen::<f64>() * total;
    for (q, w) in pool.iter().zip(&weights) {
        roll -= w;
        if roll <= 0.0 {
            return q;
        }
    }
    pool[pool.len() - 1]
}

/// Skip the previously shown question while any alternative exists.
fn drop_except(pool: &mut Vec<&Question>, except: Option<&str>) {
    if let Some(id) = except {
        if pool.len() > 1 {
            pool.retain(|q| q.id != id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::rngs::StdRng;
    use rand::SeedableRng;

    fn q(id: &str, lesson: &str) -> Question {
        serde_json::from_value(serde_json::json!({
            "id": id, "type": "reading", "prompt": id, "answers": ["a"],
            "hint": null, "ja": true, "position": 0,
            "lesson": {"taught_on": lesson},
        }))
        .unwrap()
    }

    #[test]
    fn learning_ladder_then_ease_growth() {
        let now = 1_000_000_000_000;
        let mut s = srs_update(None, true, now, 0.0);
        assert_eq!((s.interval_min, s.reps), (10.0, 1));
        assert_eq!(s.due_at_ms, now + 10 * 60_000);
        for expect in [60.0, 240.0] {
            s = srs_update(Some(&s), true, now, 0.0);
            assert_eq!(s.interval_min, expect);
        }
        s = srs_update(Some(&s), true, now, 0.0);
        assert_eq!((s.interval_min, s.reps), (1440.0, 4)); // graduated: 1 day
        s = srs_update(Some(&s), true, now, 0.0);
        assert_eq!(s.interval_min, 3600.0); // 1d * 2.5
        s = srs_update(Some(&s), true, now, 0.0);
        assert_eq!(s.interval_min, 9000.0);
    }

    #[test]
    fn interval_caps_at_90_days() {
        let mut s = srs_update(None, true, 0, 0.0);
        for _ in 0..20 {
            s = srs_update(Some(&s), true, 0, 0.0);
        }
        assert_eq!(s.interval_min, 129_600.0);
    }

    #[test]
    fn lapse_resets_and_ease_floors() {
        let now = 0;
        let mut s = srs_update(None, true, now, 0.0);
        for _ in 0..4 {
            s = srs_update(Some(&s), true, now, 0.0);
        }
        let lapsed = srs_update(Some(&s), false, now, 0.0);
        // streak of 5 halves to 2; back in 10 minutes
        assert_eq!((lapsed.interval_min, lapsed.reps, lapsed.lapses), (10.0, 2, 1));
        assert_eq!(lapsed.ease, 2.3);
        // the next correct answer resumes the climb from there and heals ease
        let back = srs_update(Some(&lapsed), true, now, 0.0);
        assert_eq!((back.interval_min, back.reps), (240.0, 3));
        assert!((back.ease - 2.4).abs() < 1e-9);
        let mut e = lapsed;
        for _ in 0..20 {
            e = srs_update(Some(&e), false, now, 0.0);
        }
        assert_eq!(e.ease, EASE_MIN); // floors, never below
    }

    #[test]
    fn share_is_95_fresh_and_50_mature() {
        let bank = vec![q("a", "2026-09-01"), q("b", "2026-09-01")];
        let empty = HashMap::new();
        assert!((newest_share(&bank, &empty, "2026-09-01") - 0.95).abs() < 1e-9);
        let mut mature = HashMap::new();
        for id in ["a", "b"] {
            mature.insert(id.to_string(), SrsState {
                due_at_ms: 0, interval_min: 480.0, ease: 2.5,
                reps: 5, lapses: 0, last_correct: true, updated_at_ms: 0,
            });
        }
        assert!((newest_share(&bank, &mature, "2026-09-01") - 0.5).abs() < 1e-9);
    }

    #[test]
    fn fresh_lesson_dominates_at_about_95_percent() {
        let bank = vec![q("new1", "2026-09-01"), q("new2", "2026-09-01"), q("old", "2026-08-27")];
        // the old item is due for review; newest items unseen
        let mut srs = HashMap::new();
        srs.insert("old".into(), SrsState {
            due_at_ms: 0, interval_min: 1440.0, ease: 2.5,
            reps: 3, lapses: 0, last_correct: true, updated_at_ms: 0,
        });
        let mut rng = StdRng::seed_from_u64(7);
        let now = 1_000_000;
        let hits = (0..4000)
            .filter(|_| select(&bank, &srs, now, None, &mut rng).lesson == "2026-09-01")
            .count();
        let share = hits as f64 / 4000.0;
        assert!((0.92..=0.98).contains(&share), "newest share was {share}");
    }

    #[test]
    fn matured_lesson_yields_to_reviews() {
        let bank = vec![q("new1", "2026-09-01"), q("old", "2026-08-27")];
        let mut srs = HashMap::new();
        for (id, interval) in [("new1", 480.0), ("old", 1440.0)] {
            srs.insert(id.into(), SrsState {
                due_at_ms: 0, interval_min: interval, ease: 2.5,
                reps: 5, lapses: 0, last_correct: true, updated_at_ms: 0,
            });
        }
        let mut rng = StdRng::seed_from_u64(7);
        let hits = (0..4000)
            .filter(|_| select(&bank, &srs, 1_000_000, None, &mut rng).lesson == "2026-09-01")
            .count();
        let share = hits as f64 / 4000.0;
        assert!((0.45..=0.55).contains(&share), "matured newest share was {share}");
    }

    /// state helper for weight tests: `overdue` minutes past due
    fn st(reps: i32, ease: f64, interval: f64, overdue: f64, now: i64) -> SrsState {
        SrsState {
            due_at_ms: now - (overdue * 60_000.0) as i64,
            interval_min: interval,
            ease,
            reps,
            lapses: 0,
            last_correct: true,
            updated_at_ms: now,
        }
    }

    #[test]
    fn weight_retires_a_streak_and_remembers_difficulty() {
        let now = 1_000_000_000_000;
        let one = vec![q("x", "2026-09-15")];
        let w = |state: SrsState| {
            let mut m = HashMap::new();
            m.insert("x".to_string(), state);
            weight(&one[0], &m, now)
        };
        // same ease and lateness: each consecutive correct answer decays weight
        let fresh = w(st(0, 2.5, 10.0, 0.0, now));
        let streak = w(st(4, 2.5, 10.0, 0.0, now));
        assert!((fresh / streak - 1.0 / 0.6f64.powi(4)).abs() < 1e-9);
        // the decay floors after six, so a 90-day item cannot vanish entirely
        assert_eq!(w(st(6, 2.5, 10.0, 0.0, now)), w(st(40, 2.5, 10.0, 0.0, now)));
        // same streak and lateness: a battered ease outweighs a clean one
        assert!(w(st(2, EASE_MIN, 10.0, 0.0, now)) > 2.0 * w(st(2, 2.5, 10.0, 0.0, now)));
        // lateness caps in units of the item's own interval, not a flat floor
        assert_eq!(w(st(0, 2.5, 10.0, 30.0, now)), w(st(0, 2.5, 240.0, 720.0, now)));
        assert_eq!(w(st(0, 2.5, 10.0, 999.0, now)), 1.0 + OVERDUE_CAP);
    }

    #[test]
    fn struggling_item_outdraws_a_mastered_one() {
        // the 2026-09-17 report: at ~40 pops/day nothing is ever on time, so
        // both are perpetually due and the weight alone decides.
        let bank = vec![q("mastered", "2026-09-15"), q("weak", "2026-09-15")];
        let now = 1_000_000_000_000;
        let mut srs = HashMap::new();
        srs.insert("mastered".into(), st(4, 2.5, 240.0, 240.0, now)); // 4-for-4
        srs.insert("weak".into(), st(0, 1.5, 10.0, 100.0, now)); // 0-for-5
        let mut rng = StdRng::seed_from_u64(7);
        let hits = (0..4000)
            .filter(|_| select(&bank, &srs, now, None, &mut rng).id == "weak")
            .count();
        let share = hits as f64 / 4000.0;
        assert!((0.94..=0.99).contains(&share), "weak share was {share}");
    }

    #[test]
    fn unseen_outranks_a_streak_but_yields_to_a_failing_item() {
        let now = 1_000_000_000_000;
        let bank = vec![q("unseen", "2026-09-15"), q("other", "2026-09-15")];
        let w_other = |state: SrsState| {
            let mut m = HashMap::new();
            m.insert("other".to_string(), state);
            (weight(&bank[0], &m, now), weight(&bank[1], &m, now))
        };
        let (unseen, streak) = w_other(st(4, 2.5, 240.0, 240.0, now));
        assert!(unseen > streak, "unseen {unseen} should outrank a streak {streak}");
        let (unseen, failing) = w_other(st(0, 1.5, 10.0, 100.0, now));
        assert!(failing > unseen, "a failing item {failing} should outrank unseen {unseen}");
    }

    #[test]
    fn nothing_due_picks_soonest_and_never_goes_silent() {
        let bank = vec![q("a", "2026-09-01"), q("b", "2026-09-01")];
        let mut srs = HashMap::new();
        let far = |ms| SrsState {
            due_at_ms: ms, interval_min: 1440.0, ease: 2.5,
            reps: 3, lapses: 0, last_correct: true, updated_at_ms: 0,
        };
        srs.insert("a".into(), far(5_000_000));
        srs.insert("b".into(), far(9_000_000));
        let mut rng = StdRng::seed_from_u64(7);
        assert_eq!(select(&bank, &srs, 1_000_000, None, &mut rng).id, "a");
        // ...and with `a` just shown, the buddy still asks something
        assert_eq!(select(&bank, &srs, 1_000_000, Some("a"), &mut rng).id, "b");
    }

    #[test]
    fn except_skipped_while_alternatives_exist() {
        let bank = vec![q("a", "2026-09-01"), q("b", "2026-09-01")];
        let srs = HashMap::new();
        let mut rng = StdRng::seed_from_u64(7);
        for _ in 0..100 {
            assert_eq!(select(&bank, &srs, 0, Some("a"), &mut rng).id, "b");
        }
        let solo = vec![q("a", "2026-09-01")];
        assert_eq!(select(&solo, &srs, 0, Some("a"), &mut rng).id, "a");
    }
}
