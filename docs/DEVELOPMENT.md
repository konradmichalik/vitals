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

Schema 4 adds `processes.topByMemory` (5 entries, highest `rssBytes` first), per-process
`label` (from `classify::command_label`), `rssBytes` and `startedAt` (Unix seconds, now
minus `ps` elapsed time) on every `TopProcess`, and `ddev.projects` (`name` and `status`
for every DDEV project, including stopped ones), plus the top-level `consumers` list and
`verdict` object (see below). `classify::command_label` keeps the program (or the script
for interpreters) plus at most two long flags matching `--[A-Za-z0-9][A-Za-z0-9-]*`. Every
other token is dropped, including flags glued to a value by `=`, `:`, `,` or `@`, since argv
can carry secrets.

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

## Verdict

`core/src/verdict.rs` condenses findings and consumers into the one verdict the menubar
hero shows: `severity`, `headline`, `detail`, an optional `culprit` and one suggested
`action`. `derive(report, processes, config)` runs after `rules::evaluate` (CLI and `vitals-ffi`), so
`report::collect` only fills `Verdict::calm()` as a placeholder. Only findings at `warn` or
above count. The highest severity wins, and on a tie `load_status` beats
`runaway_processes`, which beats `memory_pressure`. A CPU verdict says "is running away" only
for the busiest process `rules::is_runaway` flags, found through its own `process` consumer.
Without one, the load verdict names the consumer with the most CPU ("uses the most CPU") and
the runaway verdict names no culprit. Memory verdicts name the largest DDEV project (else the
largest consumer), and the action is that consumer's own action. The TTY report prints headline and detail as its
first line.

## Consumers

`core/src/consumers.rs` builds `VitalsReport.consumers`, the "Top consumers" list.
`consumers::build(report, processes, config, now)` runs in `report::collect` with the same
`now` as `top_processes_by`. Every process or container lands in exactly one group:
`ddevProject` (containers per project), `claudeCli` (sessions), `app` (processes of one app
bundle), `process` (a single other process) and `orbstackOverhead`. Groups below the minimum CPU
(1%) and memory thresholds are dropped, the rest are sorted by memory and capped at 12. Runaway processes are exempt from the cap
and stay their own `process` group even inside an app bundle (labelled with the executable
name), so the verdict can always name them. Processes with `OrbStack.app/` in their command and Claude session PIDs are left out
of the `app` and `process` groups. Each consumer carries `children` and an optional
`SuggestedAction` (`stop_project`, `kill_process`). `kill_process` is only offered where
`actions::is_killable` allows it: a PID above 1 that is neither Vitals itself nor its parent
process, and whose command does not start with `/System/`, `/usr/sbin/`, `/usr/libexec/` or
`/sbin/`.

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

`kill_process` takes `--target <pid>@<started_at>` (Unix seconds, the `startedAt` the report
shows). `build_action` calls `actions::verify_identity` before the action exists: the CLI
re-reads the process list (`probes::processes::list`) and compares that PID's start time
(`now - etime`) with `started_at`, allowing a 2 second tolerance (`IDENTITY_TOLERANCE_SECONDS`).
A PID that is gone aborts with "process <pid> is no longer running". A start time that differs
by more than the tolerance aborts with "process <pid> is no longer the one shown, refresh and
try again". `verify_identity` also applies `is_killable` to the process it found, so a protected
process aborts with "process <pid> cannot be stopped" whoever built the target. PIDs 0 and 1
are refused when the target is parsed. There is no bare-PID form.

The check runs before the interactive y/N prompt (or the menubar app's own dialog, which
passes `--yes`) for an early error, and `Action::execute` runs it again on a fresh process
list right before the signal, so a PID reused while the prompt was open is not killed. It
then sends `SIGTERM`, waits 2 seconds and sends `SIGKILL` only if the PID is still alive.

`start_project` takes `--target <project-name>` and runs `ddev start <name>` through
`run_with_timeout` (600 s). It is the counterpart of `stop_project`: the DDEV tab offers
Start for projects whose status is `stopped` or `paused`, and Stop for `running` ones.

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
- `Models/Verdict.swift`, `Models/Consumer.swift`: `Codable` mirrors of the core's
  `verdict` and `consumers` fields.

Every pure function above (`decode`, `pollInterval`, `buildArguments`,
`locateVitalsBinary`, `TrafficLight.from`, `Severity`'s `Comparable` conformance) has a
matching XCTest in `VitalsAppTests/`, written and run RED-first the same way as the
Rust side — write the test against a stubbed body, confirm it fails for the right
reason, then implement. `xcodebuild -project VitalsApp.xcodeproj -scheme VitalsApp test`
(or `make test`) runs the suite; a plain build does not.

`Support/FindingAlertTransition.swift` tracks a *severity per rule* between polls
(`alertingSeverities(in:)` → `[String: Severity]`, `newlyAlerting(previous:current:)` —
pure, tested); `AppState` notifies on the transition into warn *or* critical, never while
one persists across the 10s alert-interval poll, and always updates its tracked map even
with notifications turned off (otherwise re-enabling them later would treat every
already-alerting finding as new). Severity is tracked rather than plain set membership
because a rule escalating warn → critical is already in the previous set, so a
membership-only diff would silently swallow the louder second notification. Info stays
silent by design. `Support/AppNotifier.swift` is the untested `UNUserNotificationCenter`
pass-through (real side effects, same rationale as `LaunchAtLogin`) and owns the
`alertStorageKey` `@AppStorage` key; `Support/AppDelegate.swift` owns the permission
request and delegate registration.

### Navigation

`Views/PopoverScreen.swift` defines the screens the popover shell (`Views/PopoverShell.swift`)
switches between: `overview`, `detail(MetricKind)` (cpu, memory, load, swap),
`toolchain(ToolTab)` (ddev, docker, claude, backup), `activity` and `settings`. The header
icons for activity and settings are toggles (`toggled(_:)`): pressing one on its own screen
returns to the overview. Views live in `Views/Overview/` (verdict hero, metric tiles,
toolchain chips, consumers, findings), `Views/Detail/` (metric detail with a `HistoryChart`,
15m and 1h ranges) and `Views/Toolchain/` (one tab per tool). The `Settings` scene in
`VitalsApp.swift` is intentionally empty, settings are a popover screen.

### Stores

| Data | Location | Limits |
| --- | --- | --- |
| Metric history (`MetricHistoryStore`) | `UserDefaults` key `metricHistory` | up to 360 samples, restored samples older than 1 h are dropped |
| Snoozes (`SnoozeStore`) | `UserDefaults` key `snoozes` | expired snoozes are pruned on launch and on change |
| Activity log (`ActivityLogStore`) | `~/Library/Application Support/Vitals/activity.json` | 7 days, at most 500 entries, oldest dropped first |
| Quiet hours | `UserDefaults` key `quietHours` | fixed window from 19:00 to 08:00 |
| Menubar value | `UserDefaults` key `menubarValue` | on by default |
| Alert notifications | `UserDefaults` key `notifyOnAlerts` | on by default |

A snooze is `1 h`, `today` or `until restart`. The last one stores the boot time and
expires when it changes. A snoozed rule is hidden from the findings list and from
notifications, while the traffic light and status pill still count it. A corrupt or
outdated store loads as empty instead of blocking launch.

### Action outcome

`Support/ActionOutcome.swift` tracks one action from click to effect. `reduce(_:_:)` is
pure, every timestamp comes in as an argument. States: `idle`, `running`, `checking` and
`failed`. `started` moves to `running`. A successful `finished` moves to `checking`, a failed
one to `failed` with the runner's message and the finish time. `checking` returns to `idle`
when a report timestamped after the action finished arrives, or after `displayTimeout` (60 s)
as a fallback if polling stalls. `failed` returns to `idle` after the same 60 s, so a failure
does not stay pinned under later verdicts. A tick before the stored time (the clock stepped
back) expires both states at once. Every finished action is also written to the
activity log.

Refreshes can overlap (poll loop, the refresh after an action, the footer button).
`AppState` numbers each refresh as it starts (`Support/RefreshOrder.swift`, a counter rather
than the wall clock, which can step back) and drops a result whose refresh started before the
last accepted one. An older measurement never replaces a newer one or feeds the activity diff,
history and notifications, and an older success cannot clear a newer failure's error.

### Notifications and menubar

Finding banners carry two actions (`Support/NotificationResponse.swift`, pure and tested):
"Show cause" (also the default tap) opens the overview, "Snooze 1 h" snoozes that rule for
one hour. A notification fires on the transition into warn or critical only, and not at all
during quiet hours. The menubar item shows a dot badge next to the icon, hidden when green
and square instead of round when critical (`TrafficLight.badgeCornerRadius`). With
`menubarValue` on, `MenubarLabel.text` adds a value only while a critical finding exists:
`CPU <n>%` for `load_status`, `Mem <pressure>` for `memory_pressure`.

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
