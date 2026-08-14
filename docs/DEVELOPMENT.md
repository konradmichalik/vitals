# Development

## Workspace layout

- `core/` — `vitals-core`, macOS-only. Probes shell out to system commands
  (`sysctl`, `vm_stat`, `tmutil`, `ps`, `ddev`, `docker`); parsing pitfalls are
  documented in each probe module's doc comment.
- `cli/` — the `vitals` binary. Flag parsing and output formatting only; no probe
  logic lives here.
- `app/` — SwiftUI menubar shell (v0.4). `app/vitals-ffi` (a root-workspace Cargo
  member) links `vitals-core` directly and exposes it to Swift via a C ABI, rather than
  shelling out to the `vitals` binary — avoids double parsing and binary path
  resolution. `app/VitalsApp` is the SwiftUI target; `app/VitalsAppTests` its XCTest
  target. `app/project.yml` is the XcodeGen source of truth — never hand-edit
  `VitalsApp.xcodeproj`, regenerate it with `xcodegen generate` (or `make xcode`).

## Commands

```sh
cargo build --workspace
cargo test --workspace
cargo clippy --workspace --all-targets
cargo fmt --all
```

## Adding a probe

1. Add the raw parsing logic in `core/src/probes/<name>.rs`, matching an existing
   stub's shape (a small local struct for probe-specific raw data, a `pub fn` that
   returns `Result<T, VitalsError>`).
2. Write the fixture-based unit test first — capture real command output as a fixture
   rather than mocking the shell call.
3. Wire the result into the relevant `core/src/types.rs` JSON-contract struct once the
   probe is implemented.

If the data source can be slow or hang (talks to Docker, queries a backend service),
use `probes::shell::run_with_timeout` with an explicit timeout rather than the default
`run` — see `ddev.rs`/`docker.rs`. A monitoring tool that can hang forever is broken by
design; this was discovered the hard way when `ddev list` hung for minutes with a
stalled OrbStack backend. If a probe needs two commands joined by ID (`docker.rs`'s
`ps`+`stats`, `processes.rs`'s two `ps` calls), parse each into its own small struct and
merge afterwards rather than combining columns in one invocation.

Don't assume one Docker subcommand's size format applies to another: `docker stats`
labels sizes with proper IEC units (`MiB`/`GiB`), but `docker images`/`docker system df`
use go-units' decimal-looking `MB`/`GB` labels with the *same* 1024 multiplier under the
hood — two different suffix tables (`parse_docker_size` vs `parse_image_size` in
`docker.rs`), not one shared parser.

## JSON contract

`vitals --json` output is versioned via `SCHEMA_VERSION` in `core/src/types.rs`. Bump
it on any breaking field change — the menubar app and any other consumer depend on
this shape.

## Rule engine

Rules live in `core/src/rules.rs`. `evaluate(report, processes, config)` calls one
function per rule (each `fn rule_name(...) -> Option<Finding>`) and collects whatever
fires. `processes` carries the raw process table alongside the curated report because
some rules (e.g. detecting an active Mutagen sync) need data that never makes it into
the persisted §6 JSON contract. Add a new rule by writing another `fn -> Option<Finding>`,
adding it to the array in `evaluate`, and a fixture-based test in the same file.

`runaway_processes` scans that raw table for anything sustaining unusually high CPU
(`thresholds.runaway_cpu_percent`/`runaway_min_minutes`, both deliberately high — `ps`'s
`%CPU` is already a lifetime average, so a brief burst can't trigger it, but legitimately
heavy tools like a `docker build` or video export still can; expect to tune these from
real experience rather than trust the defaults blindly). Its classification predicate,
`rules::is_runaway`, is `pub` and reused by the CLI's `--fix kill_runaway_processes`
action-building (`cli/src/main.rs`) so a fresh process snapshot is re-classified with the
exact same rule the finding used, rather than trusting a possibly-stale PID list.

## Config

`core/src/config.rs` loads `~/.vitals.toml`. All sections have `#[serde(default)]`, so
a partial or missing file falls back to sane defaults (`Config::default()`) — never add
a field without a default.

## Actions

`core/src/actions.rs` defines the `Action` enum from §9 and its `describe()` (pure,
used for `--dry-run` and confirmation prompts) and `execute()` (shells out for real).
`ACTION_NAMES` in the same module is the canonical list of names `--fix` accepts; it
backs both the CLI's unknown-action error message and a `rules.rs` contract test
asserting no rule can advertise an action that doesn't exist (two once did, so following
the tool's own advice failed with "unknown action"). Add a name there when adding a
variant.
The CLI (`cli/src/main.rs`) owns confirmation and `--target` parsing; `core` never
prompts or reads stdin. `vitals --fix <action> --yes` skips the interactive y/N prompt
— used by the menubar app after its own native confirmation dialog.

## Menubar app (app/)

`app/vitals-ffi/src/lib.rs` exposes exactly two `#[no_mangle] extern "C"` functions:
`vitals_collect()` (runs `report::collect` + `rules::evaluate`, returns the same JSON
shape as `vitals --json`, including the `{"schemaVersion":...,"error":...}` failure
form) and `vitals_free_string()` (the caller must free every string `vitals_collect`
returns). `build.rs` runs `cbindgen` on every build, writing the header straight to
`VitalsApp/Bridge/vitals.h` — generated, gitignored, excluded from SwiftLint, never
hand-edited.

Swift-side structure:
- `Models/VitalsReport.swift` — `Codable` structs mirroring the JSON contract 1:1
  (property names match the JSON's camelCase keys, so no `CodingKeys` needed).
- `Bridge/VitalsBridge.swift` — `collect()` calls the FFI; `decode(_:)` is the pure,
  independently-testable JSON-handling half (tries `VitalsReport` first, falls back to
  the API-error shape, then `.malformed`).
- `Models/AppState.swift` — polls on an adaptive interval (`pollInterval(for:)`, pure:
  30s green / 10s once any rule has fired, per §4's sampling notes). `@MainActor` on
  the whole class means its pure static members must be marked `nonisolated` or Swift 6
  strict concurrency won't let synchronous test code call them.
- `Support/ActionRunner.swift` — `buildArguments(action:target:)` is pure (always
  appends `--yes`); `run()` shells out to the located `vitals` binary via `Process`.
- `Support/TrafficLight.swift` — `from(findings:)` derives the icon color from the
  highest-severity finding (green when none fire).

Every pure function above (`decode`, `pollInterval`, `buildArguments`,
`locateVitalsBinary`, `TrafficLight.from`, `Severity`'s `Comparable` conformance) has a
matching XCTest in `VitalsAppTests/`, written and run RED-first the same way as the
Rust side — write the test against a stubbed body, confirm it fails for the right
reason, then implement. `xcodebuild -project VitalsApp.xcodeproj -scheme VitalsApp test`
(or `make test`) runs the suite; a plain build does not.

`Support/CriticalFindingTransition.swift` tracks which rule names are critical between
polls (`newlyCritical(previous:current:)`, both `Set<String>` — pure, tested); `AppState`
notifies only on the transition *into* critical, never while it persists across the 10s
alert-interval poll, and always updates its tracked set even with notifications turned
off (otherwise re-enabling them later would treat every already-critical finding as new).
`Support/CriticalFindingNotifier.swift` is the untested `UNUserNotificationCenter`
pass-through (real side effects, same rationale as `LaunchAtLogin`); `Support/AppDelegate.swift`
owns the permission request and delegate registration.

### Code signing without an Apple Developer account

This project has no Apple ID and will ship via Homebrew, not the App Store — mirroring
`cc-usage-bar`/Spark's approach, which ships ad-hoc signed with no `DEVELOPMENT_TEAM` at
all. `app/project.yml` sets `CODE_SIGN_IDENTITY: "-"` and `CODE_SIGNING_REQUIRED: NO`
explicitly rather than relying on Xcode's automatic per-machine signing (which requires a
signed-in Apple ID to mint a certificate).

Two gotchas discovered getting `UNUserNotificationCenter` working under this setup:

- Xcode's Debug-only "build the app as a dylib behind a stub executor" optimization
  (faster incremental builds) breaks `UNUserNotificationCenter`'s bundle-identity
  resolution — it crashed on every launch with "could not determine bundleIdentifier"
  even though an identically ad-hoc-signed **Release** build ran fine. Set via
  `ENABLE_DEBUG_DYLIB: NO` in `project.yml`.
- Separately, `xcodebuild test` hosts the app in a process that still can't resolve a
  bundle identity for `UNUserNotificationCenter`, regardless of the above — confirmed a
  test-runner-only artifact by launching the same Debug/Release builds directly via
  `open`, which never crashed. `AppDelegate` checks
  `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil` and skips
  notification setup entirely under test, rather than working around the crash some
  other way.
