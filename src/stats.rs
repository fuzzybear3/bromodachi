//! The numbers the bar shows (`bromodachi stats`): today, the queue, the
//! newest lesson and a week of answers. Built from the bank, SRS states and
//! answers the picker itself reads, so the bar cannot disagree with it.

use crate::api::{self, Answer};
use crate::config::Secrets;
use crate::srs;
use anyhow::Result;
use std::collections::HashSet;

const DAY_MS: i64 = 86_400_000;
/// days in the chart, today last
const WEEK: usize = 7;

/// Days since the epoch in the user's zone (`offset_min` east of UTC).
fn local_day(ms: i64, offset_min: i64) -> i64 {
    (ms + offset_min * 60_000).div_euclid(DAY_MS)
}

/// The first instant of the chart's first day.
fn week_start_ms(now_ms: i64, offset_min: i64) -> i64 {
    (local_day(now_ms, offset_min) - (WEEK as i64 - 1)) * DAY_MS - offset_min * 60_000
}

#[derive(Debug, PartialEq)]
struct Tally<'a> {
    /// today
    answers: usize,
    right: usize,
    /// answers per local day, oldest first, today last
    week: [usize; WEEK],
    /// cards answered today and on no earlier day of the week: new today,
    /// unless they were first seen before the week began
    maybe_new: Vec<&'a str>,
}

fn tally(answers: &[Answer], now_ms: i64, offset_min: i64) -> Tally<'_> {
    let today = local_day(now_ms, offset_min);
    let mut t = Tally { answers: 0, right: 0, week: [0; WEEK], maybe_new: vec![] };
    let mut earlier: HashSet<&str> = HashSet::new();
    for a in answers {
        let age = today - local_day(a.answered_at_ms, offset_min);
        if !(0..WEEK as i64).contains(&age) {
            continue;
        }
        t.week[WEEK - 1 - age as usize] += 1;
        if age > 0 {
            earlier.insert(&a.question_id);
        } else {
            t.answers += 1;
            t.right += a.correct as usize;
            if !t.maybe_new.contains(&a.question_id.as_str()) {
                t.maybe_new.push(&a.question_id);
            }
        }
    }
    t.maybe_new.retain(|id| !earlier.contains(id));
    t
}

/// Fetch and count: four requests, the last only on a day with cards that
/// might be new.
pub fn build(s: &Secrets, now_ms: i64, offset_min: i64) -> Result<serde_json::Value> {
    let bank = api::fetch_bank(s)?;
    let srs_map = api::fetch_srs(s)?;
    let since = week_start_ms(now_ms, offset_min);
    let answers = api::fetch_answers(s, since)?;
    let t = tally(&answers, now_ms, offset_min);
    let seen = api::seen_before(s, &t.maybe_new, since)?;
    let new = t.maybe_new.iter().filter(|id| !seen.contains(**id)).count();
    let history: Vec<(String, i64)> = answers.iter().map(|a| (a.question_id.clone(), a.answered_at_ms)).collect();
    Ok(serde_json::json!({
        "today": {"answers": t.answers, "right": t.right, "new": new},
        "queue": srs::queue(&bank, &srs_map, &history, now_ms),
        "week": t.week,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    const JST: i64 = 9 * 60;
    const HOUR: i64 = 3_600_000;
    /// 2026-10-07 13:00 JST
    const NOW: i64 = 1_791_345_600_000;

    fn a(id: &str, hours_ago: i64, correct: bool) -> Answer {
        Answer { question_id: id.into(), answered_at_ms: NOW - hours_ago * HOUR, correct }
    }

    #[test]
    fn the_clock_in_the_tests_is_what_it_says() {
        // 13:00 on a local day: 13 h past its midnight
        assert_eq!((NOW + JST * 60_000).rem_euclid(DAY_MS), 13 * HOUR);
    }

    #[test]
    fn days_break_at_local_midnight() {
        // 12 h ago was 01:00 today in Tokyo, though yesterday in UTC
        let answers = vec![a("x", 1, true), a("y", 12, false), a("z", 14, true)];
        let t = tally(&answers, NOW, JST);
        assert_eq!((t.answers, t.right), (2, 1));
        assert_eq!(t.week, [0, 0, 0, 0, 0, 1, 2]);
        // the same answers counted in UTC: 04:00 now, so 12 h ago was yesterday
        assert_eq!(tally(&answers, NOW, 0).week, [0, 0, 0, 0, 0, 2, 1]);
    }

    #[test]
    fn the_chart_holds_seven_days_and_no_more() {
        let answers = vec![a("x", 0, true), a("x", 24 * 6, true), a("x", 24 * 7, true)];
        let t = tally(&answers, NOW, JST);
        assert_eq!(t.week, [1, 0, 0, 0, 0, 0, 1]);
        // the week starts at the local midnight six days back
        assert_eq!(week_start_ms(NOW, JST), NOW - 13 * HOUR - 6 * DAY_MS);
    }

    #[test]
    fn a_card_seen_earlier_in_the_week_is_not_new() {
        let answers = vec![a("fresh", 1, false), a("fresh", 2, false), a("old", 3, true), a("old", 30, true)];
        assert_eq!(tally(&answers, NOW, JST).maybe_new, vec!["fresh"]);
    }
}
