//! Config (~/.config/bromodachi/config.json), secrets
//! (~/.config/bromodachi/secrets.env) and the state directory.

use anyhow::{bail, Context, Result};
use std::fs;
use std::path::PathBuf;

pub struct Config {
    pub autofocus: bool,
    pub drill_on_wrong: bool,
    pub interval_minutes: f64,
}

pub struct Secrets {
    pub url: String,
    pub key: String,
}

fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

pub fn config_path() -> PathBuf {
    std::env::var("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home().join(".config"))
        .join("bromodachi/config.json")
}

pub fn state_dir() -> PathBuf {
    let dir = std::env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home().join(".local/state"))
        .join("bromodachi");
    let _ = fs::create_dir_all(&dir);
    dir
}

pub fn runtime_socket() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| state_dir())
        .join("bromodachi.sock")
}

impl Config {
    /// Read config, writing the default file on first run (parity with the
    /// old bash launcher).
    pub fn load() -> Config {
        let path = config_path();
        if !path.exists() {
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = fs::write(
                &path,
                "{\n  \"autofocus\": true,\n  \"drillOnWrong\": true,\n  \"intervalMinutes\": 10\n}\n",
            );
        }
        let v: serde_json::Value = fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or(serde_json::Value::Null);
        Config {
            autofocus: v["autofocus"].as_bool().unwrap_or(true),
            drill_on_wrong: v["drillOnWrong"].as_bool().unwrap_or(true),
            interval_minutes: v["intervalMinutes"].as_f64().filter(|m| *m > 0.0).unwrap_or(10.0),
        }
    }
}

impl Secrets {
    /// SUPABASE_URL / SUPABASE_SECRET_KEY from the environment, falling back
    /// to parsing ~/.config/bromodachi/secrets.env (0600, never in the repo).
    pub fn load() -> Result<Secrets> {
        let mut url = std::env::var("SUPABASE_URL").ok();
        let mut key = std::env::var("SUPABASE_SECRET_KEY").ok();
        if url.is_none() || key.is_none() {
            let path = config_path().with_file_name("secrets.env");
            let text = fs::read_to_string(&path)
                .with_context(|| format!("no SUPABASE_URL/SUPABASE_SECRET_KEY in env and cannot read {}", path.display()))?;
            for line in text.lines() {
                let line = line.trim().trim_start_matches("export ").trim();
                if let Some((k, v)) = line.split_once('=') {
                    match k.trim() {
                        "SUPABASE_URL" if url.is_none() => url = Some(v.trim().to_string()),
                        "SUPABASE_SECRET_KEY" if key.is_none() => key = Some(v.trim().to_string()),
                        _ => {}
                    }
                }
            }
        }
        match (url, key) {
            (Some(url), Some(key)) if !url.is_empty() && !key.is_empty() => {
                Ok(Secrets { url: url.trim_end_matches('/').to_string(), key })
            }
            _ => bail!(
                "missing SUPABASE_URL or SUPABASE_SECRET_KEY (set them in {})",
                config_path().with_file_name("secrets.env").display()
            ),
        }
    }
}

/// Current character (shiba|robot|ninja), persisted across restarts.
pub const ROSTER: [&str; 3] = ["shiba", "robot", "ninja"];

pub fn character() -> String {
    let path = state_dir().join("current");
    let cur = fs::read_to_string(&path).unwrap_or_default();
    let cur = cur.trim();
    if ROSTER.contains(&cur) {
        cur.to_string()
    } else {
        "shiba".to_string()
    }
}

pub fn cycle_character() -> String {
    let next = match character().as_str() {
        "shiba" => "robot",
        "robot" => "ninja",
        _ => "shiba",
    };
    let _ = fs::write(state_dir().join("current"), next);
    next.to_string()
}
