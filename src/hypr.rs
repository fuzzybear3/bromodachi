//! Hyprland interaction: activity detection (lock / DPMS) and the cursor
//! warp used by the summon focus dance. All via subprocesses, same as the
//! old QML daemon did.

use std::process::Command;

/// Inactive when hyprlock is up (Omarchy's idle timeout raises it, so long
/// AFK stops the clock too) or when no display is awake (DPMS off).
pub fn system_active() -> bool {
    let locked = Command::new("pgrep")
        .args(["-x", "hyprlock"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);
    if locked {
        return false;
    }
    Command::new("hyprctl")
        .args(["monitors", "-j"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains("\"dpmsStatus\": true"))
        .unwrap_or(true) // if hyprctl itself fails, assume active: never wedge the clock
}

pub fn cursor_pos() -> Option<(i32, i32)> {
    let out = Command::new("hyprctl").arg("cursorpos").output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let (x, y) = text.trim().split_once(',')?;
    Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
}

/// Same dispatcher invocation the old launcher used verbatim.
pub fn warp(x: i32, y: i32) {
    let _ = Command::new("hyprctl")
        .args(["dispatch", &format!("hl.dsp.cursor.move({{ x = {x}, y = {y} }})")])
        .output();
}
