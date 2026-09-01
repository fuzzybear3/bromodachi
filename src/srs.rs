//! Spaced repetition: SM-2-lite state updates and the adaptive
//! newest-lesson-biased selector. Pure functions — randomness comes in
//! through the caller's Rng, so every test is deterministic.
//!
//! All tunables live in this one block.

use crate::api::Question;
use rand::Rng;
use std::collections::HashMap;

/// learning steps after each correct answer before graduating (minutes).
/// Deliberately long ladder (user request 2026-09-01): a new word earns
/// ~6 exposures before day-scale intervals; steps are minimum spacings,
/// rationed in practice by the ~40-pops/day budget via the overdue weights.
const LEARNING_STEPS_MIN: [f64; 5] = [10.0, 30.0, 90.0, 240.0, 480.0]; // 10m..8h
/// first post-learning interval (minutes) — one day, on the 6th correct
const GRADUATE_MIN: f64 = 1440.0;
const EASE_START: f64 = 2.5;
const EASE_MIN: f64 = 1.3;
const EASE_WRONG_DELTA: f64 = 0.2;
/// interval cap: 90 days
const MAX_INTERVAL_MIN: f64 = 129_600.0;
/// ±10% jitter on due times so items don't clump
const DUE_JITTER: f64 = 0.10;
/// an item with a 3-day interval counts as fully mature
const MATURE_MIN: f64 = 4320.0;
/// newest-lesson share: clamp(BASE + SPAN·(1−avgMaturity), FLOOR, BASE+SPAN)
/// → 95% of pops while the lesson is fresh, decaying as it matures
const NEWEST_BASE: f64 = 0.5;
const NEWEST_SPAN: f64 = 0.45;
const NEWEST_FLOOR: f64 = 0.25;
/// within-pool draw weights
const UNSEEN_WEIGHT: f64 = 3.0;
const OVERDUE_CAP: f64 = 4.0;

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
        (interval, ease, reps, lapses)
    } else {
        // full relearn; the ease decrement is the durable difficulty memory
        (LEARNING_STEPS_MIN[0], (ease - EASE_WRONG_DELTA).max(EASE_MIN), 0, lapses + 1)
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
    state.map(|s| (s.interval_min / MATURE_MIN).clamp(0.0, 1.0)).unwrap_or(0.0)
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

fn weight(q: &Question, srs: &HashMap<String, SrsState>, now_ms: i64) -> f64 {
    match srs.get(&q.id) {
        None => UNSEEN_WEIGHT,
        Some(s) => {
            let overdue_min = (now_ms - s.due_at_ms) as f64 / 60_000.0;
            1.0 + (overdue_min / s.interval_min.max(30.0)).clamp(0.0, OVERDUE_CAP)
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
        for expect in [30.0, 90.0, 240.0, 480.0] {
            s = srs_update(Some(&s), true, now, 0.0);
            assert_eq!(s.interval_min, expect);
        }
        s = srs_update(Some(&s), true, now, 0.0);
        assert_eq!((s.interval_min, s.reps), (1440.0, 6)); // graduated: 1 day
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
        assert_eq!((lapsed.interval_min, lapsed.reps, lapsed.lapses), (10.0, 0, 1));
        assert_eq!(lapsed.ease, 2.3);
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
                due_at_ms: 0, interval_min: MATURE_MIN, ease: 2.5,
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
        for (id, interval) in [("new1", MATURE_MIN), ("old", 1440.0)] {
            srs.insert(id.into(), SrsState {
                due_at_ms: 0, interval_min: interval, ease: 2.5,
                reps: 4, lapses: 0, last_correct: true, updated_at_ms: 0,
            });
        }
        let mut rng = StdRng::seed_from_u64(7);
        let hits = (0..4000)
            .filter(|_| select(&bank, &srs, 1_000_000, None, &mut rng).lesson == "2026-09-01")
            .count();
        let share = hits as f64 / 4000.0;
        assert!((0.45..=0.55).contains(&share), "matured newest share was {share}");
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
