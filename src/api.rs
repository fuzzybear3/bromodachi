//! Thin PostgREST client. Online-only by design (user decision): a failed
//! call is logged and surfaced in `status`; the caller skips that pop and
//! the schedule keeps ticking. All durable state lives in Postgres.

use crate::config::Secrets;
use crate::srs::SrsState;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Question {
    pub id: String,
    #[serde(rename = "type")]
    pub qtype: String,
    pub prompt: String,
    pub answers: Vec<String>,
    pub hint: Option<String>,
    pub ja: bool,
    pub position: i32,
    #[serde(deserialize_with = "lesson_date")]
    pub lesson: String,
}

/// PostgREST embeds the joined lesson as {"taught_on": "..."}; flatten it.
fn lesson_date<'de, D: serde::Deserializer<'de>>(d: D) -> Result<String, D::Error> {
    #[derive(Deserialize)]
    struct Lesson {
        taught_on: String,
    }
    Ok(Lesson::deserialize(d)?.taught_on)
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

pub fn fetch_bank(s: &Secrets) -> Result<Vec<Question>> {
    let url = format!(
        "{}/rest/v1/questions?select=id,type,prompt,answers,hint,ja,position,lesson:lessons(taught_on)&active=is.true&order=position",
        s.url
    );
    let body = agent()
        .get(&url)
        .set("apikey", &s.key)
        .set("Authorization", &format!("Bearer {}", s.key))
        .call()
        .context("fetch questions")?
        .into_string()?;
    let bank: Vec<Question> = serde_json::from_str(&body).context("parse questions")?;
    Ok(bank)
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

pub fn fetch_srs(s: &Secrets) -> Result<HashMap<String, SrsState>> {
    #[derive(Deserialize)]
    struct Row {
        question_id: String,
        due_at: String,
        interval_min: f64,
        ease: f64,
        reps: i32,
        lapses: i32,
        last_correct: Option<bool>,
        updated_at: String,
    }
    let url = format!("{}/rest/v1/srs_state", s.url);
    let body = agent()
        .get(&url)
        .set("apikey", &s.key)
        .set("Authorization", &format!("Bearer {}", s.key))
        .call()
        .context("fetch srs_state")?
        .into_string()?;
    let rows: Vec<Row> = serde_json::from_str(&body).context("parse srs_state")?;
    Ok(rows
        .into_iter()
        .map(|r| {
            (r.question_id, SrsState {
                due_at_ms: ms_from_iso(&r.due_at),
                interval_min: r.interval_min,
                ease: r.ease,
                reps: r.reps,
                lapses: r.lapses,
                last_correct: r.last_correct.unwrap_or(false),
                updated_at_ms: ms_from_iso(&r.updated_at),
            })
        })
        .collect())
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
