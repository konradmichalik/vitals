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

fn parse(toml_str: &str, path: &Path) -> Result<Config, VitalsError> {
    toml::from_str(toml_str).map_err(|err| VitalsError::ConfigError {
        path: path.display().to_string(),
        reason: err.to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_input_yields_defaults() {
        let config = parse("", Path::new("test.toml")).unwrap();
        assert_eq!(config, Config::default());
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
