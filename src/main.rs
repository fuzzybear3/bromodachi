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
        _ => {
            eprintln!("usage: bromodachi [daemon|summon|status|cycle|ask <uuid|index>|hide]");
            std::process::exit(1);
        }
    }
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
