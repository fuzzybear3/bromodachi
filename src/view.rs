//! Spawn and reap the short-lived QML view (view/popup.qml).
//!
//! Contract: the question rides in on BUDDY_QUESTION (JSON); the view writes
//! `<out>.ready` (global input-box coords, for the cursor warp) shortly after
//! it lands, and `<out>.result` the moment the first answer is graded
//! (rewritten when a drill completes). Killing the view before any result is
//! the retract path: nothing was seen, nothing is recorded.

use crate::api::Question;
use anyhow::{Context, Result};
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

#[derive(Debug, Deserialize)]
pub struct Ready {
    pub input_x: i32,
    pub input_y: i32,
    #[serde(default)]
    pub window_x: i32,
    #[serde(default)]
    pub window_y: i32,
    #[serde(default)]
    pub window_w: i32,
    #[serde(default)]
    pub window_h: i32,
}

#[derive(Debug, Deserialize)]
pub struct ViewResult {
    pub correct: bool,
    pub mode: String,
    pub typed: String,
    pub shown_at_ms: i64,
    pub answered_at_ms: i64,
    pub hint_used: bool,
    #[serde(default)]
    pub active_ms: Option<i64>,
    // training-console fields (2026-09-03); defaults keep an older view
    // binary's result file parseable
    #[serde(default)]
    pub ms_to_first_input: Option<i64>,
    #[serde(default)]
    pub self_corrected: bool,
    #[serde(default)]
    pub timing_unreliable: bool,
    #[serde(default)]
    pub expected_text: Option<String>,
}

/// Locate the repo/install dir holding view/popup.qml: BUDDY_DIR wins,
/// otherwise walk up from the executable (works from target/{debug,release}).
pub fn base_dir() -> Result<PathBuf> {
    if let Ok(dir) = std::env::var("BUDDY_DIR") {
        return Ok(PathBuf::from(dir));
    }
    let exe = std::env::current_exe().context("current_exe")?;
    let mut dir = exe.parent().map(Path::to_path_buf);
    while let Some(d) = dir {
        if d.join("view/popup.qml").exists() {
            return Ok(d);
        }
        dir = d.parent().map(Path::to_path_buf);
    }
    anyhow::bail!("cannot locate view/popup.qml (set BUDDY_DIR)")
}

pub struct View {
    pub child: Child,
    pub question: Question,
    ready: PathBuf,
    result: PathBuf,
}

pub fn spawn(question: &Question, character: &str, drill: bool, out_prefix: &Path) -> Result<View> {
    let ready = out_prefix.with_extension("ready");
    let result = out_prefix.with_extension("result");
    let _ = fs::remove_file(&ready);
    let _ = fs::remove_file(&result);
    let child = Command::new("qs")
        .arg("-p")
        .arg(base_dir()?.join("view/popup.qml"))
        .env("BUDDY_QUESTION", serde_json::to_string(question)?)
        .env("BUDDY_CHARACTER", character)
        .env("BUDDY_DRILL", if drill { "1" } else { "0" })
        .env("BUDDY_ASSETS", base_dir()?.join("assets"))
        .env("BUDDY_OUT", out_prefix)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("spawn qs view")?;
    Ok(View { child, question: question.clone(), ready, result })
}

impl View {
    pub fn ready(&self) -> Option<Ready> {
        serde_json::from_str(&fs::read_to_string(&self.ready).ok()?).ok()
    }

    pub fn result(&self) -> Option<ViewResult> {
        serde_json::from_str(&fs::read_to_string(&self.result).ok()?).ok()
    }

    pub fn answered(&self) -> bool {
        self.result.exists()
    }

    pub fn kill(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    pub fn cleanup(&self) {
        let _ = fs::remove_file(&self.ready);
        let _ = fs::remove_file(&self.result);
    }
}

impl Question {
    /// JSON the view consumes; also what `status` reports.
    pub fn brief(&self) -> String {
        format!("{} | {}", self.qtype, self.prompt)
    }
}
