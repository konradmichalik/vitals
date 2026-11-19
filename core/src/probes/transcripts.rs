//! Last activity of a Claude Code session, read from its transcript.
//!
//! Claude Code stores transcripts as JSONL under
//! `~/.claude/projects/<project>/<session-id>.jsonl`, where `<project>` is
//! the working directory with every non-alphanumeric character replaced
//! by `-` (Claude Code docs, "Where transcripts are stored"). The newest
//! modification time in that directory is when a session there last
//! wrote anything — a real timestamp, unlike the lifetime-average `%CPU`
//! that `ps` reports.
//!
//! Several sessions in the same directory share one project folder, so
//! this measures the directory, not an individual session.

use std::path::{Path, PathBuf};
use std::time::SystemTime;

pub fn encode_project_dir(working_directory: &str) -> String {
    working_directory
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

pub fn projects_root() -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("CLAUDE_CONFIG_DIR") {
        return Some(PathBuf::from(dir).join("projects"));
    }
    let home = std::env::var("HOME").ok()?;
    Some(PathBuf::from(home).join(".claude/projects"))
}

/// Seconds since any transcript for `working_directory` was last written,
/// or `None` when there is no transcript to go by.
pub fn seconds_since_last_write(working_directory: &str, now: SystemTime) -> Option<u64> {
    let dir = projects_root()?.join(encode_project_dir(working_directory));
    newest_jsonl_mtime(&dir).map(|mtime| now.duration_since(mtime).map_or(0, |d| d.as_secs()))
}

fn newest_jsonl_mtime(dir: &Path) -> Option<SystemTime> {
    std::fs::read_dir(dir)
        .ok()?
        .filter_map(Result::ok)
        .filter(|entry| entry.path().extension().is_some_and(|ext| ext == "jsonl"))
        .filter_map(|entry| entry.metadata().ok()?.modified().ok())
        .max()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn encodes_working_directory_like_claude_code_does() {
        assert_eq!(
            encode_project_dir("/Users/km/Sites/vitals"),
            "-Users-km-Sites-vitals"
        );
        assert_eq!(
            encode_project_dir("/Users/k.michalik/Sites/typo3_file-sync"),
            "-Users-k-michalik-Sites-typo3-file-sync"
        );
    }

    #[test]
    fn newest_mtime_ignores_non_transcript_files_and_missing_dirs() {
        let dir = std::env::temp_dir().join(format!("vitals-transcripts-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        assert_eq!(newest_jsonl_mtime(&dir), None);

        std::fs::write(dir.join("notes.txt"), "x").unwrap();
        assert_eq!(newest_jsonl_mtime(&dir), None);

        std::fs::write(dir.join("a.jsonl"), "{}").unwrap();
        let mtime = newest_jsonl_mtime(&dir).unwrap();
        let age = SystemTime::now().duration_since(mtime).unwrap_or_default();
        assert!(age < Duration::from_secs(60));

        assert_eq!(newest_jsonl_mtime(&dir.join("missing")), None);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
