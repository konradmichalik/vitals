//! C-compatible FFI surface exposing `vitals-core`'s report + rule engine
//! to the SwiftUI menubar app (see concept doc §3 — the app links
//! `vitals-core` directly rather than shelling out to the `vitals`
//! binary, avoiding double parsing and binary path resolution).
//!
//! Actions stay CLI-side (§11.2): this crate is read-only. The app
//! invokes the installed `vitals` binary via `Process` for `--fix`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use vitals_core::config::Overrides;

/// Collects the current report, evaluates the rule engine, and returns
/// the result as a JSON string with the same shape as `vitals --json`
/// (including an `{"schemaVersion":...,"error":...}` fallback on
/// failure, so the Swift side never has to special-case a null return).
///
/// # Safety
/// The caller must free the returned pointer with `vitals_free_string`.
#[no_mangle]
pub extern "C" fn vitals_collect() -> *mut c_char {
    into_raw(collect_json(&Overrides::default()))
}

/// Like `vitals_collect`, with the app's own settings (idle threshold,
/// protected items) laid over `~/.vitals.toml`. `overrides_json` is a
/// camelCase JSON object, e.g. `{"idleAfterMinutes":120,"protected":["witte"]}`.
/// Null or unparsable input falls back to no overrides.
///
/// # Safety
/// `overrides_json` must be null or a valid NUL-terminated C string. The
/// caller must free the returned pointer with `vitals_free_string`.
#[no_mangle]
pub unsafe extern "C" fn vitals_collect_with(overrides_json: *const c_char) -> *mut c_char {
    let overrides = if overrides_json.is_null() {
        Overrides::default()
    } else {
        let raw = unsafe { CStr::from_ptr(overrides_json) };
        parse_overrides(&raw.to_string_lossy())
    };
    into_raw(collect_json(&overrides))
}

fn parse_overrides(raw: &str) -> Overrides {
    serde_json::from_str(raw).unwrap_or_default()
}

fn into_raw(json: String) -> *mut c_char {
    match CString::new(json) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string previously returned by `vitals_collect`.
///
/// # Safety
/// `ptr` must be a pointer previously returned by this library, or null.
#[no_mangle]
pub unsafe extern "C" fn vitals_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

fn collect_json(overrides: &Overrides) -> String {
    if overrides.fresh == Some(true) {
        vitals_core::cache::invalidate_all();
    }
    let config = match vitals_core::config::load() {
        Ok(config) => config.with_overrides(overrides),
        Err(err) => return error_json(&err.to_string()),
    };

    match vitals_core::report::collect(&config) {
        Ok((mut report, processes)) => {
            report.findings = vitals_core::rules::evaluate(&report, &processes, &config);
            serde_json::to_string(&report).unwrap_or_else(|err| error_json(&err.to_string()))
        }
        Err(err) => error_json(&err.to_string()),
    }
}

fn error_json(message: &str) -> String {
    serde_json::json!({
        "schemaVersion": vitals_core::types::SCHEMA_VERSION,
        "error": message,
    })
    .to_string()
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {
    use super::*;

    #[test]
    fn error_json_includes_schema_version_and_message() {
        let json = error_json("something went wrong");
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(value["schemaVersion"], vitals_core::types::SCHEMA_VERSION);
        assert_eq!(value["error"], "something went wrong");
    }

    #[test]
    fn parse_overrides_reads_app_settings_and_ignores_garbage() {
        let overrides = parse_overrides(r#"{"idleAfterMinutes":45,"protected":["witte"]}"#);
        assert_eq!(overrides.idle_after_minutes, Some(45.0));
        assert_eq!(overrides.protected, Some(vec!["witte".to_string()]));
        assert_eq!(parse_overrides("not json"), Overrides::default());
        assert_eq!(parse_overrides(r#"{"fresh":true}"#).fresh, Some(true));
    }

    #[test]
    fn vitals_free_string_is_a_no_op_on_null() {
        unsafe {
            vitals_free_string(std::ptr::null_mut());
        }
    }
}
