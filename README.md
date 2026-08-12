# Vitals

Vital signs of your local development stack — a macOS tool that correlates system
metrics with the state of your dev toolchain (Time Machine, DDEV, OrbStack, IDE
agent processes) and surfaces named diagnoses instead of another CPU graph.

Existing monitors (Stats, iStat Menus, OrbStack's own UI) show *metrics*. Vitals shows
*attribution*: which part of your stack is actually causing the slowdown.

## Status

Early development (v0.1–v0.3 — probes, rule engine, config, actions). Not yet
published or installable via Homebrew.

## Architecture

Single Cargo workspace:

- `core/` — `vitals-core`: probes, parsing, and the rule engine (macOS-only)
- `cli/` — the `vitals` binary
- `app/` — SwiftUI menubar app (planned, v0.4)

## Building

```sh
cargo build
cargo test
```

## Usage

```sh
vitals            # human-readable TTY report with findings
vitals --json     # machine-readable JSON (see schemaVersion in output)
vitals --no-color

# exit code reflects the highest-severity finding: 0 none/info, 1 warn, 2 critical
```

Findings come from the rule engine (8 rules — Time Machine scanning container data,
container load, Mutagen activity, memory ballast, orphaned PhpStorm ACP agents, stale
Claude Code sessions, DDEV projects in a problem state, and unexcluded backup paths).

### Actions

```sh
vitals --fix stop_backup                       # no target needed
vitals --fix stop_project --target witte       # DDEV project name
vitals --fix kill_session --target 90548       # a specific PID
vitals --fix kill_orphaned_agents --dry-run    # preview without running it
```

Every action asks for confirmation first unless `actions.require_confirmation = false`
is set in the config (not recommended) — see §9 of the concept doc. There is no bulk
"kill all" action by design.

## Configuration

`~/.vitals.toml` (optional, all fields optional). CLI arguments take precedence over
config values. See `docs/DEVELOPMENT.md` for the full schema.

## License

MIT
