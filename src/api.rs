//! Thin PostgREST client. Online-only by design (user decision): a failed
//! call is logged and surfaced in `status`; the caller skips that pop and
//! the schedule keeps ticking. All durable state lives in Postgres.

use crate::config::Secrets;
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn iso_formats_epoch_ms() {
        assert_eq!(iso(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso(1_756_684_800_000), "2025-09-01T00:00:00Z");
    }
}
