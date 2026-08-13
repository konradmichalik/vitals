# Vitals

Vital signs of your local development stack — a macOS tool that correlates system
metrics with the state of your dev toolchain (Time Machine, DDEV, Docker/OrbStack, IDE
agent processes) and surfaces named diagnoses instead of another CPU graph.

Existing monitors (Stats, iStat Menus, OrbStack's own UI) show *metrics*. Vitals shows
*attribution*: which part of your stack is actually causing the slowdown.

## Status

Early development (v0.1–v0.4 — probes, rule engine, config, actions, menubar app). Not
yet published or installable via Homebrew.

## Architecture

Single Cargo workspace:

- `core/` — `vitals-core`: probes, parsing, and the rule engine (macOS-only)
- `cli/` — the `vitals` binary
- `app/` — SwiftUI menubar app, linking `vitals-core` via the `vitals-ffi` bridge
  (workspace member) rather than shelling out to the `vitals` binary

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

Findings come from the rule engine (10 rules — Time Machine scanning container data,
container load, Mutagen activity, memory ballast, orphaned PhpStorm ACP agents, stale
Claude Code sessions, DDEV projects in a problem state, unexcluded backup paths, Docker
containers running outside DDEV's management, and reclaimable disk space from unused
Docker images).

`vitals --json` also includes a full per-container CPU/memory breakdown under
`docker.containers` (all containers via `docker ps`/`docker stats`, not just DDEV's),
each tagged with `ddevManaged`, `ddevProject`, and `composeProject` for attribution.

### Actions

```sh
vitals --fix stop_backup                       # no target needed
vitals --fix stop_project --target witte       # DDEV project name
vitals --fix kill_session --target 90548       # a specific PID
vitals --fix kill_orphaned_agents --dry-run    # preview without running it
vitals --fix prune_docker_images               # docker image prune -f (dangling only, no -a)
vitals --fix kill_runaway_processes            # TERM, then KILL after a grace period if still alive
```

Every action asks for confirmation first unless `actions.require_confirmation = false`
is set in the config (not recommended) — see §9 of the concept doc. There is no bulk
"kill all" action by design.

## Configuration

`~/.vitals.toml` (optional, all fields optional). CLI arguments take precedence over
config values. See `docs/DEVELOPMENT.md` for the full schema.

## Menubar app

```sh
cd app
make build   # xcodegen generate + cargo build (vitals-ffi) + xcodebuild
make test    # Swift unit tests
make lint    # SwiftLint + cargo fmt/clippy for vitals-ffi
```

Traffic-light icon (green/yellow/red, from the highest-severity finding) with a
dropdown listing metrics and findings. Actions run through the installed `vitals`
binary (`Process` + `--fix <action> --yes`, after the app's own confirmation dialog) —
`core` never prompts or reads stdin; only the CLI does, and only without `--yes`. Only
target-less actions (`poweroff`, `stop_backup`, `add_exclusions`,
`kill_orphaned_agents`, `prune_docker_images`, `kill_runaway_processes`) get a "Run"
button; `stop_project`/`kill_session` need a target the JSON contract doesn't carry, so
they're shown as text only.

The gear icon opens Settings: launch-at-login (via `SMAppService`, no separate helper
app needed) and a toggle for system notifications when a finding newly becomes
critical — never while it merely stays critical across polls.

No Apple Developer account is required to build or run this app; it's ad-hoc signed
(see `docs/DEVELOPMENT.md`).

## License

MIT
