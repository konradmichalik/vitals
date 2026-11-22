//! `~/.vitals.toml` — all fields optional, CLI arguments take precedence
//! over config values (§8).

use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::error::VitalsError;

#[derive(Debug, Clone, Deserialize, Default, PartialEq)]
#[serde(default)]
pub struct Config {
    pub watch: WatchConfig,
    pub ide: IdeConfig,
    pub thresholds: Thresholds,
    pub actions: ActionsConfig,
    pub rules: RulesConfig,
    pub idle: IdleConfig,
}

/// What counts as "idle" — the basis for the quick wins and for
/// `--fix free_idle`. Nothing here is a fact macOS reports: it is the
/// policy for when an item may be freed without asking.
#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(default)]
pub struct IdleConfig {
    /// How long a DDEV project or Claude session must have shown no
    /// activity before it counts as idle.
    pub after_minutes: f64,
    /// Combined container CPU below which a DDEV project shows no activity
    /// in a sample. Idle databases and web servers still tick over at a
    /// fraction of a percent, so this cannot be zero.
    pub ddev_cpu_percent: f64,
    /// DDEV project names or session working directories that are never
    /// offered for freeing, however long they have been quiet.
    pub protected: Vec<String>,
}

impl Default for IdleConfig {
    fn default() -> Self {
        Self {
            after_minutes: 120.0,
            ddev_cpu_percent: 2.0,
            protected: Vec::new(),
        }
    }
}

/// Values the menubar app (or CLI flags) lay over the TOML file, so the
/// app can keep its own settings without ever writing the user's
/// hand-edited config back out.
#[derive(Debug, Clone, Default, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Overrides {
    pub idle_after_minutes: Option<f64>,
    pub protected: Option<Vec<String>>,
    /// Set after an action or a manual refresh: skip every probe cache
    /// (see `cache`) so the report reflects what just changed.
    pub fresh: Option<bool>,
}

impl Config {
    pub fn with_overrides(mut self, overrides: &Overrides) -> Self {
        if let Some(minutes) = overrides.idle_after_minutes {
            if valid_idle_minutes(minutes) {
                self.idle.after_minutes = minutes;
            }
        }
        if let Some(protected) = &overrides.protected {
            for entry in protected {
                if !self.idle.protected.contains(entry) {
                    self.idle.protected.push(entry.clone());
                }
            }
        }
        self
    }

    /// Protected entries match a DDEV project by name, or a session by
    /// its working directory. A leading `~` is expanded against `home`,
    /// since that is how people write paths in a config file.
    pub fn is_protected(&self, candidate: &str, home: Option<&str>) -> bool {
        self.idle.protected.iter().any(|entry| {
            let expanded = match (entry.strip_prefix('~'), home) {
                (Some(rest), Some(home)) => format!("{home}{rest}"),
                _ => entry.clone(),
            };
            let expanded = expanded.trim_end_matches('/');
            !expanded.is_empty() && expanded == candidate.trim_end_matches('/')
        })
    }
}

#[derive(Debug, Clone, Deserialize, Default, PartialEq)]
#[serde(default)]
pub struct RulesConfig {
    /// Rule names to suppress entirely. Raising a threshold could only
    /// ever mute rules that *have* one — `unmanaged_docker_containers`
    /// and friends had no way to be silenced at all, so a rule that
    /// misfires on one machine stayed permanently in the way.
    pub ignore: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Default, PartialEq)]
#[serde(default)]
pub struct WatchConfig {
    pub timemachine_exclusions: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Default, PartialEq)]
#[serde(default)]
pub struct IdeConfig {
    pub retired_versions: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(default)]
pub struct Thresholds {
    pub load_warn_factor: f64,
    pub load_critical_factor: f64,
    pub compressor_warn_gb: f64,
    pub uptime_warn_days: f64,
    pub stale_session_days: f64,
    pub changed_items_warn: u64,
    pub docker_reclaimable_warn_gb: f64,
    /// 700% = sustained across 7 full cores. Deliberately very high:
    /// legitimate heavy work (a `docker build`, video export, OrbStack
    /// itself under real container load) routinely sustains several
    /// cores' worth of CPU for a while — confirmed live during
    /// development, where a lower default flagged OrbStack's own helper
    /// process under normal DDEV usage. `ps`'s `%CPU` is already a
    /// lifetime average, not an instant snapshot, so a process only
    /// reads this high if it's genuinely been busy nearly the whole time
    /// it's been measured over.
    pub runaway_cpu_percent: f64,
    /// Paired with `runaway_cpu_percent` so a brief startup burst (e.g. a
    /// build tool maxing out cores for its first minute) doesn't count —
    /// only sustained load past this age does.
    pub runaway_min_minutes: f64,
    /// OrbStack's aggregate CPU above which `container_load` treats the
    /// container runtime as the thing driving high load. 200% = two full
    /// cores' worth.
    pub orbstack_cpu_percent: f64,
    /// CPU above which a `mutagen` process counts as actively syncing
    /// rather than idling in the background.
    pub mutagen_cpu_percent: f64,
    /// How many ACP agents may run before the count alone reads as a
    /// leak, independent of whether any is actually orphaned.
    pub acp_agent_warn_count: usize,
}

impl Default for Thresholds {
    fn default() -> Self {
        Self {
            load_warn_factor: 1.0,
            load_critical_factor: 1.5,
            compressor_warn_gb: 8.0,
            uptime_warn_days: 7.0,
            stale_session_days: 3.0,
            changed_items_warn: 20_000,
            docker_reclaimable_warn_gb: 5.0,
            runaway_cpu_percent: 700.0,
            runaway_min_minutes: 20.0,
            orbstack_cpu_percent: 200.0,
            mutagen_cpu_percent: 20.0,
            acp_agent_warn_count: 3,
        }
    }
}

#[derive(Debug, Clone, Deserialize, PartialEq)]
#[serde(default)]
pub struct ActionsConfig {
    pub require_confirmation: bool,
}

impl Default for ActionsConfig {
    fn default() -> Self {
        Self {
            require_confirmation: true,
        }
    }
}

pub fn load() -> Result<Config, VitalsError> {
    load_from(&default_path()?)
}

fn default_path() -> Result<PathBuf, VitalsError> {
    let home = std::env::var("HOME").map_err(|_| VitalsError::Io {
        path: "~/.vitals.toml".to_string(),
        source: std::io::Error::new(std::io::ErrorKind::NotFound, "HOME is not set"),
    })?;
    Ok(PathBuf::from(home).join(".vitals.toml"))
}

fn load_from(path: &Path) -> Result<Config, VitalsError> {
    match std::fs::read_to_string(path) {
        Ok(contents) => parse(&contents, path),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
        Err(err) => Err(VitalsError::Io {
            path: path.display().to_string(),
            source: err,
        }),
    }
}

/// A zero, negative or non-finite threshold would mark every item idle.
fn valid_idle_minutes(minutes: f64) -> bool {
    minutes.is_finite() && minutes > 0.0
}

fn parse(toml_str: &str, path: &Path) -> Result<Config, VitalsError> {
    let mut config: Config = toml::from_str(toml_str).map_err(|err| VitalsError::ConfigError {
        path: path.display().to_string(),
        reason: err.to_string(),
    })?;
    if !valid_idle_minutes(config.idle.after_minutes) {
        config.idle.after_minutes = IdleConfig::default().after_minutes;
    }
    Ok(config)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_input_yields_defaults() {
        let config = parse("", Path::new("test.toml")).unwrap();
        assert_eq!(config, Config::default());
    }

    /// Pins the TOML surface for the settings added alongside the rule
    /// ignore list — these key names are what users write by hand, so a
    /// rename is a breaking change and should fail loudly here.
    #[test]
    fn parses_rule_ignores_and_the_formerly_hardcoded_thresholds() {
        let toml_str = r#"
[rules]
ignore = ["unmanaged_docker_containers", "uptime_ballast"]

[thresholds]
orbstack_cpu_percent = 150
mutagen_cpu_percent = 5
acp_agent_warn_count = 6
"#;
        let config = parse(toml_str, Path::new("test.toml")).unwrap();

        assert_eq!(
            config.rules.ignore,
            vec![
                "unmanaged_docker_containers".to_string(),
                "uptime_ballast".to_string()
            ]
        );
        assert_eq!(config.thresholds.orbstack_cpu_percent, 150.0);
        assert_eq!(config.thresholds.mutagen_cpu_percent, 5.0);
        assert_eq!(config.thresholds.acp_agent_warn_count, 6);
        // Untouched thresholds must still fall back to their defaults.
        assert_eq!(
            config.thresholds.runaway_cpu_percent,
            Thresholds::default().runaway_cpu_percent
        );
    }

    #[test]
    fn parses_full_example_config() {
        let toml_str = r#"
[watch]
timemachine_exclusions = ["~/.orbstack", "~/.ddev"]

[ide]
retired_versions = ["PhpStorm2026.1"]

[thresholds]
load_warn_factor = 1.0
load_critical_factor = 1.5
compressor_warn_gb = 8
uptime_warn_days = 7
stale_session_days = 3
changed_items_warn = 20000
docker_reclaimable_warn_gb = 10
runaway_cpu_percent = 400
runaway_min_minutes = 15

[actions]
require_confirmation = true
"#;
        let config = parse(toml_str, Path::new("test.toml")).unwrap();
        assert_eq!(
            config.watch.timemachine_exclusions,
            vec!["~/.orbstack".to_string(), "~/.ddev".to_string()]
        );
        assert_eq!(
            config.ide.retired_versions,
            vec!["PhpStorm2026.1".to_string()]
        );
        assert_eq!(config.thresholds.changed_items_warn, 20_000);
        assert_eq!(config.thresholds.docker_reclaimable_warn_gb, 10.0);
        assert_eq!(config.thresholds.runaway_cpu_percent, 400.0);
        assert_eq!(config.thresholds.runaway_min_minutes, 15.0);
        assert!(config.actions.require_confirmation);
    }

    #[test]
    fn partial_config_falls_back_to_defaults_for_missing_fields() {
        let toml_str = r#"
[ide]
retired_versions = ["PhpStorm2025.3"]
"#;
        let config = parse(toml_str, Path::new("test.toml")).unwrap();
        assert_eq!(
            config.ide.retired_versions,
            vec!["PhpStorm2025.3".to_string()]
        );
        assert_eq!(config.thresholds, Thresholds::default());
        assert!(config.watch.timemachine_exclusions.is_empty());
    }

    #[test]
    fn parses_idle_section() {
        let toml_str = r#"
[idle]
after_minutes = 60
protected = ["witte", "~/Sites/vitals"]
"#;
        let config = parse(toml_str, Path::new("test.toml")).unwrap();
        assert_eq!(config.idle.after_minutes, 60.0);
        assert_eq!(
            config.idle.ddev_cpu_percent,
            IdleConfig::default().ddev_cpu_percent
        );
        assert_eq!(config.idle.protected, vec!["witte", "~/Sites/vitals"]);
    }

    #[test]
    fn nonsense_idle_minutes_in_the_file_fall_back_to_the_default() {
        for value in ["0", "-5", "nan", "inf"] {
            let config = parse(
                &format!("[idle]\nafter_minutes = {value}\n"),
                Path::new("test.toml"),
            )
            .unwrap();
            assert_eq!(config.idle.after_minutes, 120.0, "after_minutes = {value}");
        }
    }

    #[test]
    fn overridden_protection_adds_to_the_file_instead_of_replacing_it() {
        let mut config = Config::default();
        config.idle.protected = vec!["witte".to_string(), "verdi".to_string()];
        let config = config.with_overrides(&Overrides {
            idle_after_minutes: None,
            protected: Some(vec!["verdi".to_string(), "new".to_string()]),
            fresh: None,
        });
        assert_eq!(config.idle.protected, vec!["witte", "verdi", "new"]);

        let mut config = Config::default();
        config.idle.protected = vec!["witte".to_string()];
        let config = config.with_overrides(&Overrides {
            idle_after_minutes: None,
            protected: Some(Vec::new()),
            fresh: None,
        });
        assert_eq!(config.idle.protected, vec!["witte"]);
    }

    #[test]
    fn overrides_replace_idle_settings_but_ignore_nonsense_minutes() {
        let overrides = Overrides {
            idle_after_minutes: Some(0.0),
            protected: Some(vec!["verdi".to_string()]),
            fresh: None,
        };
        let config = Config::default().with_overrides(&overrides);
        assert_eq!(config.idle.after_minutes, 120.0);
        assert_eq!(config.idle.protected, vec!["verdi"]);

        let config = Config::default().with_overrides(&Overrides {
            idle_after_minutes: Some(30.0),
            protected: None,
            fresh: None,
        });
        assert_eq!(config.idle.after_minutes, 30.0);
    }

    #[test]
    fn protected_matches_names_and_home_relative_paths() {
        let mut config = Config::default();
        config.idle.protected = vec!["witte".to_string(), "~/Sites/vitals/".to_string()];
        assert!(config.is_protected("witte", None));
        assert!(config.is_protected("/Users/km/Sites/vitals", Some("/Users/km")));
        assert!(!config.is_protected("/Users/km/Sites/vitals-old", Some("/Users/km")));
        assert!(!config.is_protected("verdi", Some("/Users/km")));
    }

    #[test]
    fn overrides_parse_from_camel_case_json_as_sent_by_the_app() {
        let overrides: Overrides =
            serde_json::from_str(r#"{"idleAfterMinutes":90,"protected":["witte"]}"#).unwrap();
        assert_eq!(overrides.idle_after_minutes, Some(90.0));
        assert_eq!(overrides.protected, Some(vec!["witte".to_string()]));
    }

    #[test]
    fn rejects_malformed_toml() {
        let err = parse("not = [valid = toml", Path::new("test.toml")).unwrap_err();
        assert!(matches!(err, VitalsError::ConfigError { .. }));
    }

    #[test]
    fn missing_file_yields_defaults() {
        let config = load_from(Path::new("/nonexistent/path/vitals.toml")).unwrap();
        assert_eq!(config, Config::default());
    }

    #[test]
    fn existing_file_is_parsed() {
        let dir = std::env::temp_dir().join(format!("vitals-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("vitals.toml");
        std::fs::write(&path, "[ide]\nretired_versions = [\"Foo\"]\n").unwrap();

        let config = load_from(&path).unwrap();
        assert_eq!(config.ide.retired_versions, vec!["Foo".to_string()]);

        std::fs::remove_dir_all(&dir).unwrap();
    }
}
