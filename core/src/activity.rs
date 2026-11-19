//! Remembers when vitals last saw a DDEV project doing something, so a
//! project can be called idle ("no activity seen for 3 h") instead of
//! guessing from a single sample. DDEV itself reports only a status, not
//! a last-used time, so this is measured by vitals and can only ever
//! cover the time vitals was actually running.
//!
//! Claude sessions do not need this: their transcript files carry a real
//! modification time (see `probes::transcripts`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// A gap between two observations longer than this means vitals was not
/// running in between. Activity in that gap is unknown, so the idle clock
/// starts over rather than counting the gap as quiet time.
pub const MAX_OBSERVATION_GAP_SECONDS: u64 = 10 * 60;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct ActivityState {
    pub entries: BTreeMap<String, Entry>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub last_active: u64,
    pub last_seen: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Observation {
    pub key: String,
    pub active: bool,
}

/// Returns the new state for this round's observations. Keys that were
/// not observed are dropped: a stopped project starts from zero when it
/// comes back.
pub fn update(state: &ActivityState, observations: &[Observation], now: u64) -> ActivityState {
    let entries = observations
        .iter()
        .map(|observation| {
            let previous = state
                .entries
                .get(&observation.key)
                .filter(|entry| now.saturating_sub(entry.last_seen) <= MAX_OBSERVATION_GAP_SECONDS);
            let last_active = match (observation.active, previous) {
                (false, Some(entry)) => entry.last_active,
                _ => now,
            };
            (
                observation.key.clone(),
                Entry {
                    last_active,
                    last_seen: now,
                },
            )
        })
        .collect();
    ActivityState { entries }
}

pub fn idle_seconds(state: &ActivityState, key: &str, now: u64) -> Option<u64> {
    state
        .entries
        .get(key)
        .map(|entry| now.saturating_sub(entry.last_active))
}

pub fn default_path() -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("VITALS_STATE_DIR") {
        return Some(PathBuf::from(dir).join("activity.json"));
    }
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join("Library/Caches/vitals/activity.json"))
}

/// A missing or unreadable state file is not an error: it only means the
/// idle clock starts now.
pub fn load(path: &Path) -> ActivityState {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

/// Best effort. Failing to persist only shortens the next idle measurement.
pub fn save(path: &Path, state: &ActivityState) {
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string(state) {
        let tmp = path.with_extension("json.tmp");
        if std::fs::write(&tmp, raw).is_ok() {
            let _ = std::fs::rename(&tmp, path);
        }
    }
}

pub fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn obs(key: &str, active: bool) -> Observation {
        Observation {
            key: key.to_string(),
            active,
        }
    }

    #[test]
    fn first_sighting_starts_the_idle_clock_now_even_when_quiet() {
        let state = update(&ActivityState::default(), &[obs("ddev:witte", false)], 1000);
        assert_eq!(idle_seconds(&state, "ddev:witte", 1000), Some(0));
    }

    #[test]
    fn quiet_observations_keep_the_last_active_time() {
        let s1 = update(&ActivityState::default(), &[obs("ddev:witte", true)], 1000);
        let s2 = update(&s1, &[obs("ddev:witte", false)], 1300);
        let s3 = update(&s2, &[obs("ddev:witte", false)], 1600);
        assert_eq!(idle_seconds(&s3, "ddev:witte", 1600), Some(600));
    }

    #[test]
    fn activity_resets_the_clock() {
        let s1 = update(&ActivityState::default(), &[obs("ddev:witte", false)], 1000);
        let s2 = update(&s1, &[obs("ddev:witte", true)], 1300);
        assert_eq!(idle_seconds(&s2, "ddev:witte", 1300), Some(0));
    }

    #[test]
    fn a_gap_in_observations_restarts_the_clock() {
        let s1 = update(&ActivityState::default(), &[obs("ddev:witte", true)], 1000);
        let later = 1000 + MAX_OBSERVATION_GAP_SECONDS + 1;
        let s2 = update(&s1, &[obs("ddev:witte", false)], later);
        assert_eq!(idle_seconds(&s2, "ddev:witte", later), Some(0));
    }

    #[test]
    fn unobserved_keys_are_dropped() {
        let s1 = update(&ActivityState::default(), &[obs("ddev:witte", true)], 1000);
        let s2 = update(&s1, &[obs("ddev:verdi", true)], 1100);
        assert_eq!(idle_seconds(&s2, "ddev:witte", 1100), None);
    }

    #[test]
    fn round_trips_through_a_file_and_tolerates_a_missing_one() {
        let dir = std::env::temp_dir().join(format!("vitals-activity-{}", std::process::id()));
        let path = dir.join("activity.json");
        assert_eq!(load(&path), ActivityState::default());

        let state = update(&ActivityState::default(), &[obs("ddev:witte", true)], 42);
        save(&path, &state);
        assert_eq!(load(&path), state);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
