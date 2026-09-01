//! The daemon event loop: active-time clock, pop lifecycle, control plane.
//!
//! Scheduling semantics are a straight port of the old QML daemon:
//! - the interval (config `intervalMinutes`) is jittered ±30% per cycle
//! - only ACTIVE time counts: ticks are skipped while hyprlock is up or all
//!   displays are DPMS-off, and any wall-clock gap ≥15s (suspend) is dropped
//! - an unanswered pop-up that nobody could have seen (screens blanked or a
//!   suspend happened while it was up) is retracted: view killed, clock
//!   re-armed, nothing recorded. Once an answer is graded the view carries a
//!   result file and is left alone until dismissed.

use crate::api::{self, Attempt, Question};
use crate::config::{self, Config, Secrets};
use crate::control::{self, Request};
use crate::hypr;
use crate::view::{self, View};
use anyhow::Result;
use rand::Rng;
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TICK: Duration = Duration::from_secs(1);
const ACTIVITY_EVERY_MS: i64 = 5000;
const SUSPEND_GAP_MS: i64 = 15_000;

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64
}

struct Popped {
    view: View,
    /// cursor position saved before the autofocus warp, so summon can toggle back
    saved_cursor: Option<(i32, i32)>,
    /// autofocus warp still pending (waiting for the view's ready file)
    want_focus: bool,
    focused: bool,
}

pub struct Daemon {
    cfg: Config,
    secrets: Secrets,
    target_ms: f64,
    accum_ms: f64,
    last_tick_ms: i64,
    last_activity_ms: i64,
    sys_inactive: bool,
    popped: Option<Popped>,
    last_qid: Option<String>,
    last_error: Option<String>,
    last_fetch_ms: Option<i64>,
}

impl Daemon {
    pub fn run() -> Result<()> {
        let secrets = Secrets::load()?;
        let cfg = Config::load();
        let (tx, rx) = channel::<Request>();
        control::listen(&config::runtime_socket(), tx)?;

        let mut d = Daemon {
            cfg,
            secrets,
            target_ms: 0.0,
            accum_ms: 0.0,
            last_tick_ms: now_ms(),
            last_activity_ms: 0,
            sys_inactive: false,
            popped: None,
            last_qid: None,
            last_error: None,
            last_fetch_ms: None,
        };
        d.schedule_next();
        d.event_loop(rx)
    }

    fn schedule_next(&mut self) {
        let jitter = 0.7 + rand::thread_rng().gen::<f64>() * 0.6;
        self.target_ms = (self.cfg.interval_minutes * 60_000.0 * jitter).round();
        self.accum_ms = 0.0;
        self.last_tick_ms = now_ms();
    }

    fn event_loop(&mut self, rx: Receiver<Request>) -> Result<()> {
        loop {
            match rx.recv_timeout(TICK) {
                Ok(req) => {
                    if !self.handle_command(req) {
                        return Ok(());
                    }
                }
                Err(RecvTimeoutError::Timeout) => self.tick(),
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
            }
        }
    }

    fn tick(&mut self) {
        let now = now_ms();
        let dt = now - self.last_tick_ms;
        self.last_tick_ms = now;
        let jumped = dt >= SUSPEND_GAP_MS;

        if now - self.last_activity_ms >= ACTIVITY_EVERY_MS {
            self.last_activity_ms = now;
            self.sys_inactive = !hypr::system_active();
        }

        if let Some(p) = &mut self.popped {
            // reap first: a dismissed view means an answer to record
            if p.view.child.try_wait().ok().flatten().is_some() {
                self.finish_pop();
                return;
            }
            // pending autofocus warp once the surface reports its input box
            if p.want_focus {
                if let Some(ready) = p.view.ready() {
                    p.saved_cursor = hypr::cursor_pos();
                    hypr::warp(ready.input_x, ready.input_y);
                    p.want_focus = false;
                    p.focused = true;
                }
            }
            // retract: unanswered and unseeable (parity with the old daemon,
            // which only retracted in mode === "ask")
            if (self.sys_inactive || jumped) && !p.view.answered() {
                self.retract();
            }
            return;
        }

        if !jumped && !self.sys_inactive {
            self.accum_ms += dt as f64;
        }
        if self.accum_ms >= self.target_ms && !self.sys_inactive {
            self.pop(None, false);
        }
    }

    /// Fetch the bank and put a question on screen. `forced` = summon/ask:
    /// pops even while sys_inactive says otherwise (the user asked).
    fn pop(&mut self, want: Option<String>, forced: bool) {
        if self.popped.is_some() {
            return;
        }
        if forced {
            // the user just asked: the stale 5s activity flag must not let
            // the next tick insta-retract a pop-up they are looking at
            self.sys_inactive = !hypr::system_active();
            self.last_activity_ms = now_ms();
        } else if self.sys_inactive {
            return;
        }
        let bank = match api::fetch_bank(&self.secrets) {
            Ok(b) if !b.is_empty() => {
                self.last_fetch_ms = Some(now_ms());
                self.last_error = None;
                b
            }
            Ok(_) => {
                self.note_error("bank is empty".into());
                return;
            }
            Err(e) => {
                // online-only by design: skip this pop, keep ticking
                self.note_error(format!("{e:#}"));
                return;
            }
        };
        let question = match want {
            Some(sel) => match find_question(&bank, &sel) {
                Some(q) => q,
                None => {
                    self.note_error(format!("no question matches '{sel}'"));
                    return;
                }
            },
            None => select_newest_random(&bank, self.last_qid.as_deref()),
        };
        self.last_qid = Some(question.id.clone());
        let out = config::state_dir().join("pop");
        match view::spawn(&question, &config::character(), self.cfg.drill_on_wrong, &out) {
            Ok(view) => {
                self.popped = Some(Popped {
                    view,
                    saved_cursor: None,
                    want_focus: self.cfg.autofocus,
                    focused: false,
                });
            }
            Err(e) => self.note_error(format!("spawn view: {e:#}")),
        }
    }

    /// The view exited: record the attempt (if one was graded) and re-arm.
    fn finish_pop(&mut self) {
        if let Some(mut p) = self.popped.take() {
            let _ = p.view.child.wait();
            if let Some(r) = p.view.result() {
                let attempt = Attempt {
                    id: uuid::Uuid::new_v4().to_string(),
                    question_id: p.view.question.id.clone(),
                    shown_at_ms: r.shown_at_ms,
                    answered_at_ms: r.answered_at_ms,
                    correct: r.correct,
                    mode: r.mode,
                    typed: r.typed,
                    hint_used: r.hint_used,
                };
                // one immediate retry; idempotent thanks to the client id
                if let Err(e) = api::post_attempt(&self.secrets, &attempt)
                    .or_else(|_| api::post_attempt(&self.secrets, &attempt))
                {
                    self.note_error(format!("record attempt: {e:#}"));
                }
            }
            if p.focused {
                if let Some((x, y)) = p.saved_cursor {
                    hypr::warp(x, y);
                }
            }
            p.view.cleanup();
        }
        self.schedule_next();
    }

    /// Withdraw an unanswered pop-up nobody could have seen.
    fn retract(&mut self) {
        if let Some(mut p) = self.popped.take() {
            p.view.kill();
            p.view.cleanup();
        }
        self.schedule_next();
    }

    fn note_error(&mut self, e: String) {
        eprintln!("bromodachi: {e}");
        self.last_error = Some(e);
        self.schedule_next();
    }

    /// Returns false when the daemon should exit.
    fn handle_command(&mut self, req: Request) -> bool {
        let cmd = req.cmd["cmd"].as_str().unwrap_or("").to_string();
        let reply = match cmd.as_str() {
            "summon" => self.cmd_summon(),
            "ask" => {
                let sel = req.cmd["q"].as_str().unwrap_or("").to_string();
                if let Some(mut p) = self.popped.take() {
                    p.view.kill();
                    p.view.cleanup();
                }
                self.pop(Some(sel), true);
                self.status()
            }
            "cycle" => {
                let next = config::cycle_character();
                if self.popped.is_none() {
                    self.pop(None, true);
                }
                serde_json::json!({"ok": true, "character": next})
            }
            "status" => self.status(),
            "stop" => {
                if let Some(mut p) = self.popped.take() {
                    p.view.kill();
                    p.view.cleanup();
                }
                let _ = req.reply.send(serde_json::json!({"ok": true}).to_string());
                let _ = std::fs::remove_file(config::runtime_socket());
                return false;
            }
            _ => serde_json::json!({"ok": false, "error": "unknown command"}),
        };
        let _ = req.reply.send(reply.to_string());
        true
    }

    /// Parity with the old summon: hidden -> pop now; visible and focused ->
    /// warp the cursor back; visible unfocused -> warp onto the input.
    fn cmd_summon(&mut self) -> serde_json::Value {
        match &mut self.popped {
            None => {
                self.pop(None, true);
                serde_json::json!({"ok": self.popped.is_some(),
                                   "error": self.last_error})
            }
            Some(p) => {
                if p.focused {
                    if let Some((x, y)) = p.saved_cursor.take() {
                        hypr::warp(x, y);
                    }
                    p.focused = false;
                } else if let Some(ready) = p.view.ready() {
                    p.saved_cursor = hypr::cursor_pos();
                    hypr::warp(ready.input_x, ready.input_y);
                    p.focused = true;
                } else {
                    p.want_focus = true; // surface not ready yet; warp when it is
                }
                serde_json::json!({"ok": true})
            }
        }
    }

    fn status(&self) -> serde_json::Value {
        serde_json::json!({
            "ok": true,
            "popped": self.popped.as_ref().map(|p| p.view.question.brief()),
            "answered": self.popped.as_ref().map(|p| p.view.answered()),
            "next_pop_active_ms": if self.popped.is_some() { -1.0 }
                                  else { (self.target_ms - self.accum_ms).max(0.0) },
            "inactive": self.sys_inactive,
            "character": config::character(),
            "interval_minutes": self.cfg.interval_minutes,
            "last_fetch_ms_ago": self.last_fetch_ms.map(|t| now_ms() - t),
            "last_error": self.last_error,
        })
    }
}

/// Phase 2 selection: uniform random over the NEWEST lesson only — behavior
/// parity with the old daemon's bank. The SRS phase replaces this.
fn select_newest_random(bank: &[Question], except: Option<&str>) -> Question {
    let newest = bank.iter().map(|q| q.lesson.as_str()).max().unwrap_or_default();
    let pool: Vec<&Question> = bank
        .iter()
        .filter(|q| q.lesson == newest)
        .filter(|q| pool_ok(q, except, bank))
        .collect();
    let pool = if pool.is_empty() {
        bank.iter().filter(|q| q.lesson == newest).collect::<Vec<_>>()
    } else {
        pool
    };
    let i = rand::thread_rng().gen_range(0..pool.len());
    pool[i].clone()
}

fn pool_ok(q: &Question, except: Option<&str>, bank: &[Question]) -> bool {
    match except {
        // never repeat the previous question when there is any alternative
        Some(id) if bank.len() > 1 => q.id != id,
        _ => true,
    }
}

/// `ask` dev hook: select by uuid, or by index into the newest lesson.
fn find_question(bank: &[Question], sel: &str) -> Option<Question> {
    if let Some(q) = bank.iter().find(|q| q.id == sel) {
        return Some(q.clone());
    }
    let idx: usize = sel.parse().ok()?;
    let newest = bank.iter().map(|q| q.lesson.as_str()).max()?;
    let mut pool: Vec<&Question> = bank.iter().filter(|q| q.lesson == newest).collect();
    pool.sort_by_key(|q| q.position);
    pool.get(idx).map(|q| (*q).clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q(id: &str, lesson: &str, position: i32) -> Question {
        serde_json::from_value(serde_json::json!({
            "id": id, "type": "reading", "prompt": id, "answers": ["a"],
            "hint": null, "ja": true, "position": position,
            "lesson": {"taught_on": lesson},
        }))
        .unwrap()
    }

    #[test]
    fn selects_only_from_newest_lesson() {
        let bank = vec![q("old", "2026-08-27", 0), q("new1", "2026-09-01", 0), q("new2", "2026-09-01", 1)];
        for _ in 0..200 {
            let picked = select_newest_random(&bank, None);
            assert_eq!(picked.lesson, "2026-09-01");
        }
    }

    #[test]
    fn never_repeats_when_alternatives_exist() {
        let bank = vec![q("a", "2026-09-01", 0), q("b", "2026-09-01", 1)];
        for _ in 0..100 {
            assert_ne!(select_newest_random(&bank, Some("a")).id, "a");
        }
    }

    #[test]
    fn repeats_allowed_when_sole_question() {
        let bank = vec![q("a", "2026-09-01", 0)];
        assert_eq!(select_newest_random(&bank, Some("a")).id, "a");
    }

    #[test]
    fn ask_by_index_uses_newest_lesson_order() {
        let bank = vec![q("old", "2026-08-27", 0), q("n1", "2026-09-01", 1), q("n0", "2026-09-01", 0)];
        assert_eq!(find_question(&bank, "0").unwrap().id, "n0");
        assert_eq!(find_question(&bank, "1").unwrap().id, "n1");
        assert_eq!(find_question(&bank, "n1").unwrap().id, "n1");
        assert!(find_question(&bank, "9").is_none());
    }
}
