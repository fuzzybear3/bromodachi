//! Unix-socket control plane: one JSON line in, one JSON line out.
//! The CLI subcommands are thin clients of this.

use anyhow::{Context, Result};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::mpsc::Sender;

pub struct Request {
    pub cmd: serde_json::Value,
    pub reply: Sender<String>,
}

/// Bind the control socket, stealing a stale one if its daemon is gone.
pub fn listen(path: &Path, tx: Sender<Request>) -> Result<()> {
    if path.exists() {
        if UnixStream::connect(path).is_ok() {
            anyhow::bail!("another daemon is already running on {}", path.display());
        }
        let _ = std::fs::remove_file(path);
    }
    let listener = UnixListener::bind(path).context("bind control socket")?;
    std::thread::spawn(move || {
        for conn in listener.incoming().flatten() {
            let tx = tx.clone();
            std::thread::spawn(move || handle(conn, tx));
        }
    });
    Ok(())
}

fn handle(conn: UnixStream, tx: Sender<Request>) {
    let mut reader = BufReader::new(match conn.try_clone() {
        Ok(c) => c,
        Err(_) => return,
    });
    let mut line = String::new();
    if reader.read_line(&mut line).is_err() {
        return;
    }
    let cmd: serde_json::Value = match serde_json::from_str(&line) {
        Ok(v) => v,
        Err(_) => serde_json::json!({"cmd": "invalid"}),
    };
    let (reply_tx, reply_rx) = std::sync::mpsc::channel();
    if tx.send(Request { cmd, reply: reply_tx }).is_err() {
        return;
    }
    if let Ok(reply) = reply_rx.recv_timeout(std::time::Duration::from_secs(10)) {
        let mut conn = conn;
        let _ = writeln!(conn, "{reply}");
    }
}

/// Client side: send one command, get one reply.
pub fn send(path: &Path, cmd: &serde_json::Value) -> Result<String> {
    let mut conn = UnixStream::connect(path).context("daemon not running")?;
    writeln!(conn, "{cmd}")?;
    let mut reply = String::new();
    BufReader::new(conn).read_line(&mut reply)?;
    Ok(reply.trim().to_string())
}
