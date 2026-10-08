//! bromodachi: pixel buddy that quizzes you on Japanese.
//! One binary: `bromodachi daemon` runs the brain; every other subcommand is
//! a thin client of its control socket (and will start the daemon if needed,
//! parity with the old launcher's ensure_running).

mod api;
mod config;
mod control;
mod daemon;
mod hypr;
mod srs;
mod stats;
mod view;

use anyhow::Result;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::Duration;

fn main() {
    let arg = std::env::args().nth(1).unwrap_or_else(|| "summon".into());
    let code = match run(&arg) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("bromodachi: {e:#}");
            1
        }
    };
    std::process::exit(code);
}

fn run(arg: &str) -> Result<()> {
    match arg {
        "daemon" => daemon::Daemon::run(),
        "summon" | "toggle" => client(serde_json::json!({"cmd": "summon"}), true),
        "cycle" => client(serde_json::json!({"cmd": "cycle"}), true),
        "status" => client(serde_json::json!({"cmd": "status"}), false),
        "ask" => {
            let q = std::env::args().nth(2).unwrap_or_default();
            client(serde_json::json!({"cmd": "ask", "q": q}), true)
        }
        "hide" | "stop" => client(serde_json::json!({"cmd": "stop"}), false),
        // the bar's commands (bar/steveng.bromodachi)
        "stats" => client(serde_json::json!({"cmd": "stats", "utc_offset_min": utc_offset_min()}), false),
        "skip" => client(serde_json::json!({"cmd": "skip"}), false),
        "pause" => {
            let minutes: f64 = std::env::args().nth(2).and_then(|m| m.parse().ok()).unwrap_or(30.0);
            client(serde_json::json!({"cmd": "pause", "minutes": minutes}), false)
        }
        "resume" => client(serde_json::json!({"cmd": "pause", "minutes": 0}), false),
        "set" => {
            let key = std::env::args().nth(2).unwrap_or_default();
            let value = match std::env::args().nth(3).unwrap_or_default().as_str() {
                "on" | "true" => true.into(),
                "off" | "false" => false.into(),
                other => other.parse::<f64>().map_or(serde_json::Value::Null, Into::into),
            };
            client(serde_json::json!({"cmd": "set", "key": key, "value": value}), false)
        }
        _ => {
            eprintln!(
                "usage: bromodachi [daemon|summon|status|cycle|ask <uuid|index|new>|hide|\n                   stats|skip|pause <minutes>|resume|set interval <minutes>|set naruto on|off]"
            );
            std::process::exit(1);
        }
    }
}

/// Minutes east of UTC: the daemon counts "today" from the caller's midnight.
/// Read here because the lookup is only allowed in a single-threaded process.
fn utc_offset_min() -> i64 {
    time::UtcOffset::current_local_offset().map_or(0, |o| o.whole_minutes() as i64)
}

/// Send one command; optionally auto-start the daemon first.
fn client(cmd: serde_json::Value, autostart: bool) -> Result<()> {
    let sock = config::runtime_socket();
    let reply = match control::send(&sock, &cmd) {
        Ok(r) => r,
        Err(_) if autostart => {
            start_daemon()?;
            // wait for the socket to come up (parity: 30 x 0.1s)
            let mut last = Err(anyhow::anyhow!("daemon failed to start"));
            for _ in 0..30 {
                std::thread::sleep(Duration::from_millis(100));
                last = control::send(&sock, &cmd);
                if last.is_ok() {
                    break;
                }
            }
            last?
        }
        Err(e) => return Err(e),
    };
    println!("{reply}");
    Ok(())
}

fn start_daemon() -> Result<()> {
    let exe = std::env::current_exe()?;
    Command::new(exe)
        .arg("daemon")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0) // detach from our session, like the old setsid
        .spawn()?;
    Ok(())
}
