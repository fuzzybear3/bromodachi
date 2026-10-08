//! The daemon event loop: active-time clock, pop lifecycle, control plane.
//!
//! Scheduling semantics are a straight port of the old QML daemon:
//! - the interval (config `intervalMinutes`) is jittered ±30% per cycle
//! - only ACTIVE time counts: ticks are skipped while hyprlock is up or all
//!   displays are DPMS-off, and any wall-clock gap ≥15s (suspend) is dropped
//! - an unanswered pop-up that nobody could have seen (screens blanked or a
//!   suspend happened while it was up) is retracted: view withdrawn, clock
//!   re-armed, nothing recorded. Once an answer is graded the view carries a
//!   result file and is left alone until dismissed.

use crate::api::{self, Attempt, Question};
use crate::config::{self, Config, Secrets};
use crate::control::{self, Request};
use crate::hypr;
use crate::srs::{self, SrsState};
use crate::stats;
use crate::view::{self, CatHost, View};
use anyhow::{Context, Result};
use rand::Rng;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TICK: Duration = Duration::from_secs(1);
const ACTIVITY_EVERY_MS: i64 = 5000;
const SUSPEND_GAP_MS: i64 = 15_000;
/// a command that waited longer than this behind a stall is dropped: the
/// client gave up on it, and a Super+B that fires seconds late surprises
const STALE_COMMAND: Duration = Duration::from_secs(5);
/// the bar's numbers are rebuilt after an answer, or when this old
const STATS_MAX_AGE_MS: i64 = 300_000;
/// after a failed rebuild (offline), the bar keeps the old numbers this long
const STATS_RETRY_MS: i64 = 60_000;

fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() as i64
}

struct Popped {
    view: View,
    /// this question's SRS state at pop time; the answer transitions it
    prev_srs: Option<SrsState>,
    /// cursor position saved before the autofocus warp; present = the
    /// cursor was parked on the buddy and has somewhere to return to
    saved_cursor: Option<(i32, i32)>,
    /// autofocus warp still pending (waiting for the view's ready file)
    want_focus: bool,
    /// when it went up: the bar shows how long a question has waited
    since_ms: i64,
}

pub struct Daemon {
    cfg: Config,
    /// the persistent cat view (None when config says `"cat": false`)
    cat: Option<CatHost>,
    /// the Gitea buddy (config `"naruto": true`): only kept alive
    naruto: Option<CatHost>,
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
    /// paused from the bar until this time (0 = not paused)
    paused_until_ms: i64,
    /// the bar's numbers and when they were built
    stats: Option<(i64, serde_json::Value)>,
    stats_dirty: bool,
    stats_retry_ms: i64,
}

impl Daemon {
    pub fn run() -> Result<()> {
        let secrets = Secrets::load()?;
        let cfg = Config::load();
        let (tx, rx) = channel::<Request>();
        control::listen(&config::runtime_socket(), tx)?;

        let cat = if cfg.cat { Some(CatHost::new()?) } else { None };
        let naruto = if cfg.naruto { Some(CatHost::naruto()?) } else { None };
        let mut d = Daemon {
            cfg,
            cat,
            naruto,
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
            paused_until_ms: 0,
            stats: None,
            stats_dirty: true,
            stats_retry_ms: 0,
        };
        d.schedule_next();
        // systemd stops us with SIGTERM (restarts, logout): an answer that is
        // graded but not yet dismissed still has to be recorded on the way out
        let term = Arc::new(AtomicBool::new(false));
        for sig in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
            signal_hook::flag::register(sig, Arc::clone(&term))?;
        }
        d.event_loop(rx, &term)
    }

    fn schedule_next(&mut self) {
        let jitter = 0.7 + rand::thread_rng().gen::<f64>() * 0.6;
        self.target_ms = (self.cfg.interval_minutes * 60_000.0 * jitter).round();
        self.accum_ms = 0.0;
        self.last_tick_ms = now_ms();
    }

    fn event_loop(&mut self, rx: Receiver<Request>, term: &AtomicBool) -> Result<()> {
        loop {
            if term.load(Ordering::Relaxed) {
                self.end_pop();
                let _ = std::fs::remove_file(config::runtime_socket());
                return Ok(());
            }
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
        // wall clock: an NTP step backwards would go negative and eat active time
        let dt = (now - self.last_tick_ms).max(0);
        self.last_tick_ms = now;
        let jumped = dt >= SUSPEND_GAP_MS;

        if now - self.last_activity_ms >= ACTIVITY_EVERY_MS {
            self.last_activity_ms = now;
            self.sys_inactive = !hypr::system_active();
        }

        // keep the cat alive; a respawn ends any pop it was showing
        let cat_generation = self.cat.as_mut().map(|c| c.ensure()).unwrap_or(0);
        if let Some(n) = &mut self.naruto {
            n.ensure();
        }

        if let Some(p) = &mut self.popped {
            // reap first: a dismissed view means an answer to record
            if p.view.finished(cat_generation) {
                self.finish_pop();
                return;
            }
            // pending autofocus warp once the surface reports its input box
            if p.want_focus {
                if let Some(ready) = p.view.ready() {
                    if p.saved_cursor.is_none() {
                        p.saved_cursor = hypr::cursor_pos();
                    }
                    eprintln!("bromodachi: focus: bubble up -> box at {},{}", ready.input_x, ready.input_y);
                    hypr::warp_into(ready.input_x, ready.input_y);
                    p.want_focus = false;
                }
            }
            // screens sleeping (or a suspend) while a pop-up is on screen:
            // layer surfaces may not survive their output going away, so a
            // ghost process must never be left behind. Unanswered -> retract
            // (nothing was seen, nothing recorded); answered -> the result
            // is already on disk, so reap it and record the attempt.
            if self.sys_inactive || jumped {
                if p.view.answered() {
                    p.view.withdraw(self.cat.as_ref());
                    self.finish_pop();
                } else {
                    self.retract();
                }
            }
            return;
        }

        // paused from the bar: the clock stands still until the pause runs out
        if self.paused_until_ms > 0 {
            if now < self.paused_until_ms {
                return;
            }
            self.paused_until_ms = 0;
        }

        if !jumped && !self.sys_inactive {
            self.accum_ms += dt as f64;
        }
        if self.accum_ms >= self.target_ms && !self.sys_inactive {
            self.pop(None, false);
        }
    }

    /// Put a question up. Its network round-trips can take many seconds on a
    /// bad connection; that time is not a suspend, so it is kept out of the
    /// next tick's gap (otherwise a slow pop read as a >= 15 s gap and was
    /// retracted about a second after it appeared).
    fn pop(&mut self, want: Option<String>, forced: bool) {
        let (t0, before) = (now_ms(), self.last_tick_ms);
        self.pop_now(want, forced);
        if self.last_tick_ms == before {
            self.last_tick_ms += now_ms() - t0;
        }
    }

    /// Fetch the bank and put a question on screen. `forced` = summon/ask:
    /// pops even while sys_inactive says otherwise (the user asked).
    fn pop_now(&mut self, want: Option<String>, forced: bool) {
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
        // srs state must load too: answering without it would reset the
        // item's schedule on upsert, so a failed fetch skips the pop
        let srs_map = match api::fetch_srs(&self.secrets) {
            Ok(m) => m,
            Err(e) => {
                self.note_error(format!("{e:#}"));
                return;
            }
        };
        // what was just asked and how often today; only guards depend on
        // it, so a failed fetch degrades to "no history" instead of a skip
        let history = api::fetch_history(&self.secrets, now_ms() - 86_400_000).unwrap_or_else(|e| {
            eprintln!("bromodachi: {e:#}");
            vec![]
        });
        let question = match want.as_deref() {
            // the bar's "New word": the next unseen card, slot free or not
            Some("new") => match srs::next_new(&bank, &srs_map, &history, now_ms(), self.last_qid.as_deref()) {
                Some(q) => q.clone(),
                None => {
                    self.note_error("no new card to ask right now".into());
                    return;
                }
            },
            Some(sel) => match find_question(&bank, sel) {
                Some(q) => q,
                None => {
                    self.note_error(format!("no question matches '{sel}'"));
                    return;
                }
            },
            None => srs::select(&bank, &srs_map, &history, now_ms(), self.last_qid.as_deref()).clone(),
        };
        self.last_qid = Some(question.id.clone());
        let out = config::state_dir().join("pop");
        let prev_srs = srs_map.get(&question.id).cloned();
        let shown = match &self.cat {
            Some(cat) => cat.ask(&question, self.cfg.drill_on_wrong, &out),
            None => view::spawn(&question, &config::character(), self.cfg.drill_on_wrong, &out),
        };
        match shown {
            Ok(view) => {
                self.popped = Some(Popped {
                    view,
                    prev_srs,
                    saved_cursor: None,
                    // parity with the old launcher: only a manual summon/ask
                    // warps the cursor; a timer pop never steals it mid-work
                    want_focus: forced && self.cfg.autofocus,
                    since_ms: now_ms(),
                });
            }
            Err(e) => self.note_error(format!("spawn view: {e:#}")),
        }
    }

    /// The view exited: record the attempt (if one was graded) and re-arm.
    fn finish_pop(&mut self) {
        if let Some(mut p) = self.popped.take() {
            p.view.reap();
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
                    active_ms: r.active_ms,
                    ms_to_first_input: r.ms_to_first_input,
                    self_corrected: r.self_corrected,
                    timing_unreliable: r.timing_unreliable,
                    expected_text: r.expected_text,
                };
                // one immediate retry each; idempotent thanks to the client
                // id (attempts) and the merge-upsert keyed on question_id
                if let Err(e) = api::post_attempt(&self.secrets, &attempt)
                    .or_else(|_| api::post_attempt(&self.secrets, &attempt))
                {
                    self.note_error(format!("record attempt: {e:#}"));
                }
                // the card's state now, not as it was when shown: a reset from
                // the web while the bubble was up must not be undone
                let prev = api::fetch_srs_one(&self.secrets, &p.view.question.id).unwrap_or(p.prev_srs);
                let jitter = rand::thread_rng().gen_range(-1.0..=1.0);
                let next = srs::srs_update(prev.as_ref(), r.correct, r.hint_used, now_ms(), jitter);
                if let Err(e) = api::upsert_srs(&self.secrets, &p.view.question.id, &next)
                    .or_else(|_| api::upsert_srs(&self.secrets, &p.view.question.id, &next))
                {
                    self.note_error(format!("record srs: {e:#}"));
                }
                self.stats_dirty = true;
            }
            // hand the cursor back if it was parked on the buddy
            if let Some((x, y)) = p.saved_cursor {
                hypr::warp(x, y);
            }
            p.view.cleanup();
        }
        self.schedule_next();
    }

    /// Take the pop down now (a command, or shutting down). An answer that
    /// was already graded still counts and is recorded, even though the
    /// bubble was never dismissed.
    fn end_pop(&mut self) {
        if let Some(p) = &mut self.popped {
            p.view.withdraw(self.cat.as_ref());
            self.finish_pop();
        }
    }

    /// Withdraw an unanswered pop-up nobody could have seen.
    fn retract(&mut self) {
        if let Some(mut p) = self.popped.take() {
            p.view.withdraw(self.cat.as_ref());
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
        if req.received.elapsed() > STALE_COMMAND && matches!(cmd.as_str(), "summon" | "ask" | "cycle") {
            eprintln!("bromodachi: dropped a {cmd} that waited {:?} behind a stall", req.received.elapsed());
            let _ = req.reply.send(serde_json::json!({"ok": false, "error": "stale"}).to_string());
            return true;
        }
        let reply = match cmd.as_str() {
            "summon" => self.cmd_summon(),
            "ask" => {
                let sel = req.cmd["q"].as_str().unwrap_or("").to_string();
                self.end_pop();
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
            "stats" => self.cmd_stats(req.cmd["utc_offset_min"].as_i64().unwrap_or(0)),
            // take the question down ungraded; the next one waits a full interval
            "skip" => {
                self.end_pop();
                self.status()
            }
            "pause" => {
                let minutes = req.cmd["minutes"].as_f64().unwrap_or(0.0);
                if minutes > 0.0 {
                    self.paused_until_ms = now_ms() + (minutes * 60_000.0) as i64;
                    self.end_pop();
                } else {
                    self.paused_until_ms = 0;
                }
                self.status()
            }
            "set" => match self.cmd_set(req.cmd["key"].as_str().unwrap_or(""), &req.cmd["value"]) {
                Ok(()) => self.status(),
                Err(e) => serde_json::json!({"ok": false, "error": format!("{e:#}")}),
            },
            "stop" => {
                self.end_pop();
                self.cat = None; // Drop kills the cat process
                self.naruto = None;
                let _ = req.reply.send(serde_json::json!({"ok": true}).to_string());
                let _ = std::fs::remove_file(config::runtime_socket());
                return false;
            }
            _ => serde_json::json!({"ok": false, "error": "unknown command"}),
        };
        let _ = req.reply.send(reply.to_string());
        true
    }

    /// Parity with the old summon: hidden -> pop now; already on screen ->
    /// focus the existing pop-up (never a second one). Whether to focus or
    /// un-focus is decided by where the cursor actually IS — with
    /// focus-follows-mouse, "cursor on the buddy" is what focused means.
    /// Super+B: bring a question up, or jump into its answer box, or (from
    /// inside the box) jump back to where the cursor was. Each decision is
    /// logged: "it didn't select the box" reports need the why.
    fn cmd_summon(&mut self) -> serde_json::Value {
        match &mut self.popped {
            None => {
                self.pop(None, true);
                // asked for one now: a cat that has to travel there hurries
                if self.popped.is_some() {
                    if let Some(cat) = &self.cat {
                        eprintln!("bromodachi: summon: new question, hurry: {}", cat.hurry());
                    }
                }
                serde_json::json!({"ok": self.popped.is_some(),
                                   "error": self.last_error})
            }
            Some(p) => {
                match p.view.ready() {
                    Some(ready) => {
                        let cursor = hypr::cursor_pos();
                        // already in the box? The cat says so; for the old
                        // popup, guess from the cursor being over it
                        let in_box = ready.focused.unwrap_or_else(|| {
                            cursor
                                .map(|(cx, cy)| {
                                    cx >= ready.window_x && cx < ready.window_x + ready.window_w
                                        && cy >= ready.window_y && cy < ready.window_y + ready.window_h
                                })
                                .unwrap_or(false)
                        });
                        if in_box {
                            match p.saved_cursor.take() {
                                Some((x, y)) => {
                                    eprintln!("bromodachi: summon: in the box -> back to {x},{y}");
                                    hypr::warp(x, y);
                                }
                                None => eprintln!("bromodachi: summon: in the box already"),
                            }
                        } else {
                            if p.saved_cursor.is_none() {
                                p.saved_cursor = cursor;
                            }
                            eprintln!(
                                "bromodachi: summon: cursor {:?} -> box at {},{}",
                                cursor, ready.input_x, ready.input_y
                            );
                            hypr::warp_into(ready.input_x, ready.input_y);
                        }
                    }
                    None => {
                        // not up yet: the cat is still on its way (or the
                        // popup still starting). Hurry it; warp once it lands
                        let hurried = self.cat.as_ref().map(|c| c.hurry());
                        eprintln!("bromodachi: summon: bubble not up yet, hurry: {hurried:?}; warp when it is");
                        p.want_focus = true;
                    }
                }
                serde_json::json!({"ok": true})
            }
        }
    }

    /// `status` plus the bar's numbers. They are rebuilt (a few requests)
    /// after an answer or when stale, never while the screens are off, and a
    /// failed rebuild keeps serving the old ones.
    fn cmd_stats(&mut self, offset_min: i64) -> serde_json::Value {
        let now = now_ms();
        let old = self.stats.as_ref().map_or(true, |(at, _)| now - at > STATS_MAX_AGE_MS);
        if (self.stats_dirty || old) && now >= self.stats_retry_ms && !self.sys_inactive {
            match stats::build(&self.secrets, now, offset_min) {
                Ok(v) => {
                    self.stats = Some((now_ms(), v));
                    self.stats_dirty = false;
                }
                Err(e) => {
                    eprintln!("bromodachi: stats: {e:#}");
                    self.stats_retry_ms = now_ms() + STATS_RETRY_MS;
                }
            }
            // like pop(): time spent fetching is not a suspend
            self.last_tick_ms += now_ms() - now;
        }
        let mut reply = self.status();
        if let Some((at, v)) = &self.stats {
            reply["stats"] = v.clone();
            reply["stats_age_ms"] = (now_ms() - at).into();
        }
        reply
    }

    /// A setting changed from the bar: applied now and written to config.json.
    fn cmd_set(&mut self, key: &str, value: &serde_json::Value) -> Result<()> {
        match key {
            "interval" => {
                let m = value.as_f64().filter(|m| (1.0..=240.0).contains(m)).context("interval: minutes, 1 to 240")?;
                config::set("intervalMinutes", if m.fract() == 0.0 { (m as i64).into() } else { m.into() })?;
                self.cfg.interval_minutes = m;
                if self.popped.is_none() {
                    self.schedule_next();
                }
            }
            "naruto" => {
                let on = value.as_bool().context("naruto: on or off")?;
                config::set("naruto", on.into())?;
                self.cfg.naruto = on;
                if !on {
                    self.naruto = None; // Drop kills the process
                } else if self.naruto.is_none() {
                    self.naruto = Some(CatHost::naruto()?);
                }
            }
            _ => anyhow::bail!("unknown setting '{key}'"),
        }
        Ok(())
    }

    fn status(&self) -> serde_json::Value {
        serde_json::json!({
            "ok": true,
            "popped": self.popped.as_ref().map(|p| p.view.question.brief()),
            "answered": self.popped.as_ref().map(|p| p.view.answered()),
            "waiting_ms": self.popped.as_ref().map(|p| now_ms() - p.since_ms),
            "paused_ms": (self.paused_until_ms - now_ms()).max(0),
            "naruto": self.cfg.naruto,
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

/// `ask` dev hook: select by uuid, or by index into the lesson added last.
fn find_question(bank: &[Question], sel: &str) -> Option<Question> {
    if let Some(q) = bank.iter().find(|q| q.id == sel) {
        return Some(q.clone());
    }
    let idx: usize = sel.parse().ok()?;
    let newest = bank.iter().map(|q| (q.lesson_added_ms, q.lesson.as_str())).max()?.1;
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
    fn ask_by_index_uses_newest_lesson_order() {
        let bank = vec![q("old", "2026-08-27", 0), q("n1", "2026-09-01", 1), q("n0", "2026-09-01", 0)];
        assert_eq!(find_question(&bank, "0").unwrap().id, "n0");
        assert_eq!(find_question(&bank, "1").unwrap().id, "n1");
        assert_eq!(find_question(&bank, "n1").unwrap().id, "n1");
        assert!(find_question(&bank, "9").is_none());
    }
}
