//! Thin PostgREST client. Online-only by design (user decision): a failed
//! call is logged and surfaced in `status`; the caller skips that pop and
//! the schedule keeps ticking. All durable state lives in Postgres.

use crate::config::Secrets;
use crate::srs::SrsState;
use anyhow::{Context, Result};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::time::Duration;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(from = "RawQuestion")]
pub struct Question {
    pub id: String,
    #[serde(rename = "type")]
    pub qtype: String,
    pub prompt: String,
    pub answers: Vec<String>,
    pub hint: Option<String>,
    pub ja: bool,
    pub position: i32,
    /// the lesson's class date
    pub lesson: String,
    /// when the lesson was added to the bank (ms): new cards enter in this
    /// order, since notes don't always arrive in class-date order
    #[serde(skip_serializing)]
    pub lesson_added_ms: i64,
}

/// PostgREST embeds the joined lesson as {"taught_on", "created_at"};
/// flatten it.
#[derive(Deserialize)]
struct RawQuestion {
    id: String,
    #[serde(rename = "type")]
    qtype: String,
    prompt: String,
    answers: Vec<String>,
    hint: Option<String>,
    ja: bool,
    position: i32,
    lesson: RawLesson,
}

#[derive(Deserialize)]
struct RawLesson {
    taught_on: String,
    #[serde(default)]
    created_at: Option<String>,
}

impl From<RawQuestion> for Question {
    fn from(r: RawQuestion) -> Question {
        Question {
            id: r.id,
            qtype: r.qtype,
            prompt: r.prompt,
            answers: r.answers,
            hint: r.hint,
            ja: r.ja,
            position: r.position,
            lesson: r.lesson.taught_on,
            lesson_added_ms: r.lesson.created_at.as_deref().map_or(0, ms_from_iso),
        }
    }
}

pub struct Attempt {
    pub id: String,
    pub question_id: String,
    pub shown_at_ms: i64,
    pub answered_at_ms: i64,
    pub correct: bool,
    pub mode: String,
    pub typed: String,
    pub hint_used: bool,
    pub active_ms: Option<i64>,
    pub ms_to_first_input: Option<i64>,
    pub self_corrected: bool,
    pub timing_unreliable: bool,
    /// answers[0] as it was when asked — the diff baseline on the web
    pub expected_text: Option<String>,
}

pub fn now_iso() -> String {
    iso(time::OffsetDateTime::now_utc().unix_timestamp() * 1000)
}

fn iso(ms: i64) -> String {
    time::OffsetDateTime::from_unix_timestamp_nanos(ms as i128 * 1_000_000)
        .unwrap_or(time::OffsetDateTime::UNIX_EPOCH)
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".into())
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout_connect(Duration::from_secs(4))
        .timeout(Duration::from_secs(8)) // stay well under the 15s suspend-gap threshold
        .build()
}

/// GET every row of a PostgREST query. Supabase caps a response at 1000
/// rows, silently, so page with Range until the exact count is reached.
/// The query must have a total order (a unique last sort key) for paging.
fn get_all<T: DeserializeOwned>(s: &Secrets, url: &str, what: &str) -> Result<Vec<T>> {
    const PAGE: usize = 1000;
    let mut rows: Vec<T> = Vec::new();
    loop {
        let from = rows.len();
        let resp = agent()
            .get(url)
            .set("apikey", &s.key)
            .set("Authorization", &format!("Bearer {}", s.key))
            .set("Prefer", "count=exact")
            .set("Range-Unit", "items")
            .set("Range", &format!("{}-{}", from, from + PAGE - 1))
            .call()
            .with_context(|| format!("fetch {what}"))?;
        // Content-Range: "0-999/1234" (or "*/0" when empty)
        let total: Option<usize> = resp
            .header("Content-Range")
            .and_then(|h| h.rsplit('/').next())
            .and_then(|t| t.parse().ok());
        let page: Vec<T> = serde_json::from_str(&resp.into_string()?).with_context(|| format!("parse {what}"))?;
        let n = page.len();
        rows.extend(page);
        if n == 0 || total.map_or(n < PAGE, |t| rows.len() >= t) {
            return Ok(rows);
        }
    }
}

pub fn fetch_bank(s: &Secrets) -> Result<Vec<Question>> {
    let url = format!(
        "{}/rest/v1/questions?select=id,type,prompt,answers,hint,ja,position,lesson:lessons!inner(taught_on,created_at)&active=is.true&lesson.active=is.true&order=position,id",
        s.url
    );
    get_all(s, &url, "questions")
}

pub fn post_attempt(s: &Secrets, a: &Attempt) -> Result<()> {
    let url = format!("{}/rest/v1/attempts?on_conflict=id", s.url);
    let payload = serde_json::json!({
        "id": a.id,
        "question_id": a.question_id,
        "shown_at": iso(a.shown_at_ms),
        "answered_at": iso(a.answered_at_ms),
        "correct": a.correct,
        "mode": a.mode,
        "typed": a.typed.chars().take(500).collect::<String>(),
        "hint_used": a.hint_used,
        "active_ms": a.active_ms,
        "ms_to_first_input": a.ms_to_first_input,
        "self_corrected": a.self_corrected,
        "timing_unreliable": a.timing_unreliable,
        "expected_text": a.expected_text,
    });
    agent()
        .post(&url)
        .set("apikey", &s.key)
        .set("Authorization", &format!("Bearer {}", s.key))
        // client-generated id + ignore-duplicates: a retry can never double-count
        .set("Prefer", "resolution=ignore-duplicates,return=minimal")
        .send_json(payload)
        .context("post attempt")?;
    Ok(())
}

fn ms_from_iso(s: &str) -> i64 {
    time::OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339)
        .map(|t| (t.unix_timestamp_nanos() / 1_000_000) as i64)
        .unwrap_or(0)
}

/// Answers since `since_ms`, newest first, as (question_id, answered_at ms):
/// the picker's memory of what was just asked and how often today.
pub fn fetch_history(s: &Secrets, since_ms: i64) -> Result<Vec<(String, i64)>> {
    Ok(fetch_answers(s, since_ms)?.into_iter().map(|a| (a.question_id, a.answered_at_ms)).collect())
}

/// One graded answer, as the stats count it.
pub struct Answer {
    pub question_id: String,
    pub answered_at_ms: i64,
    pub correct: bool,
}

/// Every answer since `since_ms`, newest first.
pub fn fetch_answers(s: &Secrets, since_ms: i64) -> Result<Vec<Answer>> {
    #[derive(Deserialize)]
    struct Row {
        question_id: String,
        answered_at: String,
        correct: bool,
    }
    let url = format!(
        "{}/rest/v1/attempts?select=question_id,answered_at,correct&answered_at=gte.{}&order=answered_at.desc,id",
        s.url,
        iso(since_ms)
    );
    let rows: Vec<Row> = get_all(s, &url, "attempts")?;
    Ok(rows
        .into_iter()
        .map(|r| Answer { question_id: r.question_id, answered_at_ms: ms_from_iso(&r.answered_at), correct: r.correct })
        .collect())
}

/// Which of these cards were answered before `before_ms`.
pub fn seen_before(s: &Secrets, ids: &[&str], before_ms: i64) -> Result<HashSet<String>> {
    #[derive(Deserialize)]
    struct Row {
        question_id: String,
    }
    if ids.is_empty() {
        return Ok(HashSet::new());
    }
    let url = format!(
        "{}/rest/v1/attempts?select=question_id&question_id=in.({})&answered_at=lt.{}&order=id",
        s.url,
        ids.join(","),
        iso(before_ms)
    );
    let rows: Vec<Row> = get_all(s, &url, "attempts")?;
    Ok(rows.into_iter().map(|r| r.question_id).collect())
}

#[derive(Deserialize)]
struct SrsRow {
    question_id: String,
    due_at: String,
    interval_min: f64,
    ease: f64,
    reps: i32,
    lapses: i32,
    last_correct: Option<bool>,
    updated_at: String,
}

impl SrsRow {
    fn state(self) -> (String, SrsState) {
        (self.question_id, SrsState {
            due_at_ms: ms_from_iso(&self.due_at),
            interval_min: self.interval_min,
            ease: self.ease,
            reps: self.reps,
            lapses: self.lapses,
            last_correct: self.last_correct.unwrap_or(false),
            updated_at_ms: ms_from_iso(&self.updated_at),
        })
    }
}

pub fn fetch_srs(s: &Secrets) -> Result<HashMap<String, SrsState>> {
    let url = format!("{}/rest/v1/srs_state?order=question_id", s.url);
    let rows: Vec<SrsRow> = get_all(s, &url, "srs_state")?;
    Ok(rows.into_iter().map(SrsRow::state).collect())
}

/// One card's state as it is now (None: never answered, or reset from the
/// web while its question was on screen).
pub fn fetch_srs_one(s: &Secrets, question_id: &str) -> Result<Option<SrsState>> {
    let url = format!("{}/rest/v1/srs_state?question_id=eq.{}", s.url, question_id);
    let rows: Vec<SrsRow> = get_all(s, &url, "srs_state")?;
    Ok(rows.into_iter().next().map(|r| r.state().1))
}

pub fn upsert_srs(s: &Secrets, question_id: &str, st: &SrsState) -> Result<()> {
    let url = format!("{}/rest/v1/srs_state?on_conflict=question_id", s.url);
    let payload = serde_json::json!({
        "question_id": question_id,
        "due_at": iso(st.due_at_ms),
        "interval_min": st.interval_min,
        "ease": st.ease,
        "reps": st.reps,
        "lapses": st.lapses,
        "last_correct": st.last_correct,
        "updated_at": iso(st.updated_at_ms),
    });
    agent()
        .post(&url)
        .set("apikey", &s.key)
        .set("Authorization", &format!("Bearer {}", s.key))
        .set("Prefer", "resolution=merge-duplicates,return=minimal")
        .send_json(payload)
        .context("upsert srs_state")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_formats_epoch_ms() {
        assert_eq!(iso(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso(1_756_684_800_000), "2025-09-01T00:00:00Z");
    }

    #[test]
    fn iso_round_trips_through_postgrest_format() {
        // PostgREST emits offsets like +00:00 and microsecond precision
        assert_eq!(ms_from_iso("2026-09-01T01:06:46.603115+00:00"), 1_788_224_806_603);
        assert_eq!(ms_from_iso(&iso(1_788_224_806_603)), 1_788_224_806_603);
        assert_eq!(ms_from_iso("garbage"), 0);
    }
}
