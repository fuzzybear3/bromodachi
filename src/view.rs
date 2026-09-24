//! The views. Two kinds share one file contract:
//!
//! - cat (view/cat.qml, default): ONE long-lived process for the whole
//!   session, supervised by `CatHost`. Questions go in with
//!   `qs ipc call cat ask`, withdrawals with `... retract`.
//! - popup (view/popup.qml, `"cat": false` in config): one short-lived
//!   process per question; the question rides in on BUDDY_QUESTION.
//!
//! Either way the view writes `<out>.ready` (global input-box coords, for the
//! cursor warp) shortly after it lands and `<out>.result` the moment the first
//! answer is graded. The cat also writes `<out>.done` when the bubble is
//! dismissed; the popup signals that by exiting. Withdrawing before any result
//! is the retract path: nothing was seen, nothing is recorded.

use crate::api::Question;
use anyhow::{Context, Result};
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

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

enum Kind {
    Popup(Child),
    /// the CatHost generation this question was asked on: if the cat has
    /// been respawned since, the bubble is gone and the pop is over
    Cat(u64),
}

pub struct View {
    kind: Kind,
    pub question: Question,
    ready: PathBuf,
    result: PathBuf,
    done: PathBuf,
}

fn clear(out_prefix: &Path) -> (PathBuf, PathBuf, PathBuf) {
    let files = (
        out_prefix.with_extension("ready"),
        out_prefix.with_extension("result"),
        out_prefix.with_extension("done"),
    );
    let _ = fs::remove_file(&files.0);
    let _ = fs::remove_file(&files.1);
    let _ = fs::remove_file(&files.2);
    files
}

/// The persistent cat: spawned once, respawned if it dies (rate-limited).
pub struct CatHost {
    child: Option<Child>,
    qml: PathBuf,
    last_spawn: Option<Instant>,
    generation: u64,
}

impl CatHost {
    pub fn new() -> Result<CatHost> {
        let qml = base_dir()?.join("view/cat.qml");
        // a cat left behind by a daemon that died without cleanup would
        // answer our ipc calls instead of the one we supervise
        let _ = Command::new("pkill")
            .arg("-f")
            .arg(format!("^qs -p {}$", qml.display()))
            .status();
        let mut host = CatHost { child: None, qml, last_spawn: None, generation: 0 };
        host.ensure();
        Ok(host)
    }

    /// Respawn the cat if it has died (at most once per 5 s). Returns the
    /// current generation, which bumps on every spawn.
    pub fn ensure(&mut self) -> u64 {
        let dead = match &mut self.child {
            None => true,
            Some(c) => c.try_wait().ok().flatten().is_some(),
        };
        let may_spawn = self.last_spawn.map_or(true, |t| t.elapsed() >= Duration::from_secs(5));
        if dead && may_spawn {
            self.last_spawn = Some(Instant::now());
            let log = fs::File::create(crate::config::state_dir().join("cat.log")).ok();
            let (out, err) = match log.and_then(|f| f.try_clone().ok().map(|g| (f, g))) {
                Some((f, g)) => (Stdio::from(f), Stdio::from(g)),
                None => (Stdio::null(), Stdio::null()),
            };
            match Command::new("qs").arg("-p").arg(&self.qml).stdin(Stdio::null()).stdout(out).stderr(err).spawn() {
                Ok(c) => {
                    self.child = Some(c);
                    self.generation += 1;
                }
                Err(e) => eprintln!("bromodachi: spawn cat: {e:#}"),
            }
        }
        self.generation
    }

    fn ipc(&self, args: &[&str]) -> Result<String> {
        let out = Command::new("qs")
            .arg("-p")
            .arg(&self.qml)
            .args(["ipc", "call", "cat"])
            .args(args)
            .stdin(Stdio::null())
            .output()
            .context("run qs ipc")?;
        if !out.status.success() {
            anyhow::bail!("cat ipc {}: {}", args[0], String::from_utf8_lossy(&out.stderr).trim());
        }
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }

    /// Put a question in the cat's bubble. Retries briefly: right after a
    /// (re)spawn the cat takes a moment to start answering ipc.
    pub fn ask(&self, question: &Question, drill: bool, out_prefix: &Path) -> Result<View> {
        let (ready, result, done) = clear(out_prefix);
        let json = serde_json::to_string(question)?;
        let prefix = out_prefix.display().to_string();
        let mut last = Err(anyhow::anyhow!("cat never answered"));
        for _ in 0..20 {
            last = self.ipc(&["ask", &json, &prefix, if drill { "1" } else { "0" }]);
            if last.is_ok() {
                break;
            }
            std::thread::sleep(Duration::from_millis(150));
        }
        last?;
        Ok(View { kind: Kind::Cat(self.generation), question: question.clone(), ready, result, done })
    }

    pub fn retract(&self) {
        if let Err(e) = self.ipc(&["retract"]) {
            eprintln!("bromodachi: {e:#}");
        }
    }
}

impl Drop for CatHost {
    fn drop(&mut self) {
        if let Some(c) = &mut self.child {
            let _ = c.kill();
            let _ = c.wait();
        }
    }
}

pub fn spawn(question: &Question, character: &str, drill: bool, out_prefix: &Path) -> Result<View> {
    let (ready, result, done) = clear(out_prefix);
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
    Ok(View { kind: Kind::Popup(child), question: question.clone(), ready, result, done })
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

    /// The user is done with it: popup exited, or the cat wrote `.done`
    /// (or was respawned since the ask, taking the bubble with it).
    pub fn finished(&mut self, cat_generation: u64) -> bool {
        match &mut self.kind {
            Kind::Popup(child) => child.try_wait().ok().flatten().is_some(),
            Kind::Cat(generation) => self.done.exists() || *generation != cat_generation,
        }
    }

    /// Take it off screen without the user dismissing it.
    pub fn withdraw(&mut self, cat: Option<&CatHost>) {
        match &mut self.kind {
            Kind::Popup(child) => {
                let _ = child.kill();
                let _ = child.wait();
            }
            Kind::Cat(_) => {
                if let Some(host) = cat {
                    host.retract();
                }
            }
        }
    }

    /// Collect the popup's exit status; the cat has nothing to reap.
    pub fn reap(&mut self) {
        if let Kind::Popup(child) = &mut self.kind {
            let _ = child.wait();
        }
    }

    pub fn cleanup(&self) {
        let _ = fs::remove_file(&self.ready);
        let _ = fs::remove_file(&self.result);
        let _ = fs::remove_file(&self.done);
    }
}

impl Question {
    /// JSON the view consumes; also what `status` reports.
    pub fn brief(&self) -> String {
        format!("{} | {}", self.qtype, self.prompt)
    }
}
