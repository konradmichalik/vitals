//! `tmutil status -X` → running/phase/changed item count, plus
//! `tmutil isexcluded <path>` for configured watch paths.
//!
//! The default `tmutil status` output is plist-like but not valid XML —
//! always use `-X` and parse the result as a proper plist, never regex
//! the default form (§7).

use crate::error::VitalsError;
use crate::types::TmExclusion;

#[derive(Debug, Clone, Default)]
pub struct TmStatus {
    pub running: bool,
    pub phase: Option<String>,
    pub changed_item_count: Option<u64>,
}

pub fn status() -> Result<TmStatus, VitalsError> {
    let raw = super::shell::run("tmutil", &["status", "-X"])?;
    parse_status(&raw)
}

pub fn check_exclusions(paths: &[String]) -> Result<Vec<TmExclusion>, VitalsError> {
    if paths.is_empty() {
        return Ok(Vec::new());
    }
    let expanded: Vec<String> = paths.iter().map(|p| expand_tilde(p)).collect();
    let mut args = vec!["isexcluded"];
    args.extend(expanded.iter().map(String::as_str));
    let raw = super::shell::run("tmutil", &args)?;
    parse_exclusions(paths, &raw)
}

fn parse_status(raw: &str) -> Result<TmStatus, VitalsError> {
    const COMMAND: &str = "tmutil status -X";
    let parse_error = |reason: &str| VitalsError::parse(COMMAND, reason);

    let value = plist::Value::from_reader(std::io::Cursor::new(raw.as_bytes()))
        .map_err(|err| VitalsError::parse(COMMAND, err.to_string()))?;

    let dict = value
        .as_dictionary()
        .ok_or_else(|| parse_error("expected a top-level dictionary"))?;

    let running = dict
        .get("Running")
        .and_then(plist::Value::as_boolean)
        .ok_or_else(|| parse_error("missing or non-boolean `Running` key"))?;

    let phase = dict
        .get("BackupPhase")
        .and_then(plist::Value::as_string)
        .map(str::to_string);

    let changed_item_count = dict
        .get("ChangedItemCount")
        .and_then(plist::Value::as_unsigned_integer);

    Ok(TmStatus {
        running,
        phase,
        changed_item_count,
    })
}

fn expand_tilde(path: &str) -> String {
    match path.strip_prefix("~/") {
        Some(rest) => match std::env::var("HOME") {
            Ok(home) => format!("{home}/{rest}"),
            Err(_) => path.to_string(),
        },
        None => path.to_string(),
    }
}

fn parse_exclusions(original_paths: &[String], raw: &str) -> Result<Vec<TmExclusion>, VitalsError> {
    const COMMAND: &str = "tmutil isexcluded";

    let lines: Vec<&str> = raw.lines().filter(|line| !line.trim().is_empty()).collect();

    if lines.len() != original_paths.len() {
        return Err(VitalsError::parse(
            COMMAND,
            format!(
                "expected {} output line(s), got {}",
                original_paths.len(),
                lines.len()
            ),
        ));
    }

    original_paths
        .iter()
        .zip(lines)
        .map(|(path, line)| {
            let excluded = if line.trim_start().starts_with("[Excluded]") {
                Ok(true)
            } else if line.trim_start().starts_with("[Included]") {
                Ok(false)
            } else {
                Err(VitalsError::parse(
                    COMMAND,
                    format!("unrecognized output line: `{line}`"),
                ))
            }?;

            Ok(TmExclusion {
                path: path.clone(),
                excluded,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const COPYING_FIXTURE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BackupPhase</key>
	<string>Copying</string>
	<key>ClientID</key>
	<string>com.apple.backupd</string>
	<key>DateOfStateChange</key>
	<date>2026-08-12T07:25:54Z</date>
	<key>DestinationID</key>
	<string>D46413A8-7046-460C-AF3D-01B7203D6ACB</string>
	<key>DestinationMountPoint</key>
	<string>/Volumes/Backup km</string>
	<key>FractionOfProgressBar</key>
	<real>0.90000000000000002</real>
	<key>Progress</key>
	<dict>
		<key>Percent</key>
		<real>0.73163793226869744</real>
		<key>TimeRemaining</key>
		<real>1857.4205670299484</real>
		<key>_raw_Percent</key>
		<real>0.73163793226869744</real>
		<key>_raw_totalBytes</key>
		<integer>443560615936</integer>
		<key>bytes</key>
		<integer>7459409920</integer>
		<key>files</key>
		<integer>21131</integer>
		<key>totalBytes</key>
		<integer>443560615936</integer>
		<key>totalFiles</key>
		<integer>6709984</integer>
	</dict>
	<key>Running</key>
	<true/>
	<key>attemptOptions</key>
	<integer>1</integer>
</dict>
</plist>
"#;

    const FINDING_CHANGES_FIXTURE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>BackupPhase</key>
	<string>FindingChanges</string>
	<key>ChangedItemCount</key>
	<integer>57818</integer>
	<key>ClientID</key>
	<string>com.apple.backupd</string>
	<key>Running</key>
	<true/>
</dict>
</plist>
"#;

    const NOT_RUNNING_FIXTURE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>ClientID</key>
	<string>com.apple.backupd</string>
	<key>Running</key>
	<false/>
</dict>
</plist>
"#;

    #[test]
    fn parses_copying_phase() {
        let status = parse_status(COPYING_FIXTURE).unwrap();
        assert!(status.running);
        assert_eq!(status.phase, Some("Copying".to_string()));
        assert_eq!(status.changed_item_count, None);
    }

    #[test]
    fn parses_finding_changes_phase_with_changed_item_count() {
        let status = parse_status(FINDING_CHANGES_FIXTURE).unwrap();
        assert!(status.running);
        assert_eq!(status.phase, Some("FindingChanges".to_string()));
        assert_eq!(status.changed_item_count, Some(57818));
    }

    #[test]
    fn parses_not_running_status() {
        let status = parse_status(NOT_RUNNING_FIXTURE).unwrap();
        assert!(!status.running);
        assert_eq!(status.phase, None);
        assert_eq!(status.changed_item_count, None);
    }

    #[test]
    fn rejects_garbage_input() {
        let err = parse_status("not a plist at all").unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }

    #[test]
    fn expands_tilde_prefixed_path() {
        let home = std::env::var("HOME").unwrap();
        assert_eq!(expand_tilde("~/.orbstack"), format!("{home}/.orbstack"));
    }

    #[test]
    fn leaves_absolute_path_unchanged() {
        assert_eq!(expand_tilde("/already/absolute"), "/already/absolute");
    }

    #[test]
    fn parses_exclusions_by_position() {
        let paths = vec!["~/.orbstack".to_string(), "~/.ddev".to_string()];
        let raw = "[Included]  /Users/x/.orbstack\n[Excluded]  /Users/x/.ddev\n";
        let exclusions = parse_exclusions(&paths, raw).unwrap();
        assert_eq!(exclusions.len(), 2);
        assert_eq!(exclusions[0].path, "~/.orbstack");
        assert!(!exclusions[0].excluded);
        assert_eq!(exclusions[1].path, "~/.ddev");
        assert!(exclusions[1].excluded);
    }

    #[test]
    fn rejects_mismatched_exclusion_line_count() {
        let paths = vec!["~/.orbstack".to_string(), "~/.ddev".to_string()];
        let raw = "[Included]  /Users/x/.orbstack\n";
        let err = parse_exclusions(&paths, raw).unwrap_err();
        assert!(matches!(err, VitalsError::ParseError { .. }));
    }
}
