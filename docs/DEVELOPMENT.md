# Development

## Workspace layout

- `core/` — `vitals-core`, macOS-only. Probes shell out to system commands
  (`sysctl`, `vm_stat`, `tmutil`, `ps`, `ddev`); parsing pitfalls are documented in
  each probe module's doc comment.
- `cli/` — the `vitals` binary. Flag parsing and output formatting only; no probe
  logic lives here.
- `app/` — SwiftUI menubar shell, added at v0.4. Links `vitals-core` via an FFI
  bridge rather than shelling out to the `vitals` binary.

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

## JSON contract

`vitals --json` output is versioned via `SCHEMA_VERSION` in `core/src/types.rs`. Bump
it on any breaking field change — the menubar app and any other consumer depend on
this shape.

## Rule engine

Rules live in `core/src/rules.rs` as a single `evaluate(report, processes, config)`
function — condition over probe data → named `Finding` (with severity and suggested
actions). `processes` carries the raw process table alongside the curated report
because some rules (e.g. detecting an active Mutagen sync) need data that never makes
it into the persisted §6 JSON contract. Add a new rule by appending another `if`/`push`
block and a fixture-based test in the same file.

## Config

`core/src/config.rs` loads `~/.vitals.toml`. All sections have `#[serde(default)]`, so
a partial or missing file falls back to sane defaults (`Config::default()`) — never add
a field without a default.

## Actions

`core/src/actions.rs` defines the `Action` enum from §9 and its `describe()` (pure,
used for `--dry-run` and confirmation prompts) and `execute()` (shells out for real).
The CLI (`cli/src/main.rs`) owns confirmation and `--target` parsing; `core` never
prompts or reads stdin.
