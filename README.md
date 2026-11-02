<p align="center">
  <img src="vitals.svg" width="96" alt="Vitals Logo">
</p>

<h1 align="center">Vitals</h1>

<p align="center">
  Vital signs of your local dev stack — a macOS tool that correlates system metrics with your dev toolchain and surfaces named diagnoses instead of another CPU graph.
</p>

<p align="center">
  <a href="https://github.com/konradmichalik/vitals/actions/workflows/ci.yml"><img src="https://github.com/konradmichalik/vitals/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

---

> **Why another monitor?**
> Stats, iStat Menus, and OrbStack's own UI show *metrics*. Vitals shows *attribution* — which part of your stack (DDEV, Docker, Time Machine, a stray IDE agent) is actually causing the slowdown, plus a one-shot fix for the ones that are safe to automate.

> [!NOTE]
> Early development — expect rough edges and breaking changes.

## ✨ Features

- **Rule engine** — 13 rules cover Time Machine scanning container data, unexcluded backup paths, container load, Mutagen activity, memory pressure, memory ballast, orphaned PhpStorm ACP agents, stale Claude Code sessions, DDEV projects stuck in a problem state, Docker containers running outside DDEV's management, reclaimable disk space, critical load average, and sustained runaway-CPU processes
- **Named diagnoses, not graphs** — every finding says which project/PID/path is responsible, not just a number
- **One-shot fixes**: stop a backup, stop a DDEV project, kill a stale session, a runaway process or any single process by `pid@started`, prune dangling images, always behind a confirmation
- **Verdict**: one sentence on top of the report, with the culprit and one suggested action
- **Top consumers**: CPU and memory grouped by toolchain: DDEV projects, Claude Code sessions, apps, single processes, OrbStack overhead
- **JSON contract** — `vitals --json` for scripting, with a full per-container CPU/memory breakdown tagged by DDEV project
- **Menubar app**: verdict, top consumers, metric history, toolchain tabs, activity log, snooze and quiet hours (see below)

## 🔥 Installation

### Homebrew

**CLI** — <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-version.json&style=flat-square&logo=homebrew" alt="Homebrew version"></a> <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-downloads.json&style=flat-square&logo=homebrew" alt="Homebrew downloads"></a>

```sh
brew install konradmichalik/tap/vitals
```

**Menubar app**: <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-app-version.json&style=flat-square&logo=homebrew" alt="Homebrew version"></a> <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-app-downloads.json&style=flat-square&logo=homebrew" alt="Homebrew downloads"></a>

```sh
brew install --cask konradmichalik/tap/vitals-app
```

### Requirements

- macOS 14+
- Rust toolchain (`cargo`)
- Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen) — only for the menubar app (below)

> Want to build from source instead? See below.

### Build from source

No Apple Developer account needed — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the ad-hoc signing setup.

```sh
cargo build --workspace
cargo test --workspace
```

## 💡 Usage

```sh
vitals            # human-readable report with findings
vitals --json     # machine-readable JSON (see schemaVersion in output)

# exit code reflects the highest-severity finding: 0 none/info, 1 warn, 2 critical
```

### Actions

```sh
vitals --fix stop_backup
vitals --fix stop_project --target witte
vitals --fix start_project --target witte
vitals --fix kill_process --target 90548@1730550000
vitals --fix kill_runaway_processes
vitals --fix prune_docker_images
vitals --fix kill_orphaned_agents --dry-run
```

Every action asks for confirmation unless `actions.require_confirmation = false` is set
in `~/.vitals.toml` — there is no bulk "kill all" by design; each fix targets one
project, PID, or resource at a time. `kill_process` takes `<pid>@<started_at>` (Unix
seconds, the `startedAt` shown in `vitals --json`) and refuses if that PID no longer
matches the start time.

> [!TIP]
> Add `--dry-run` to any `--fix` action to preview what it would do without running it.

> [!WARNING]
> Setting `actions.require_confirmation = false` skips the interactive prompt for
> every fix, not just one — not recommended outside of scripting.

## 🖥️ Menubar app

```sh
cd app
make build   # xcodegen generate + cargo build (vitals-ffi) + xcodebuild
make test
make lint
```

A traffic-light badge on the icon (hidden when green, square when critical) opens a popover:

- A verdict sentence, with the culprit and a one-click targeted action behind a confirmation
- Load, CPU, memory and swap tiles, each with a detail view and 15m and 1h history
- Top consumers grouped by DDEV project, Claude Code sessions, apps and processes
- Toolchain tabs for DDEV, Docker, Claude Code and Time Machine
- An activity log of findings and actions (7 days)
- Snooze per finding (1 hour, today, until restart) and quiet hours (19:00 to 08:00)
- Notification banners with "Show cause" and "Snooze 1 h"
- An optional value next to the icon (`CPU 87%`, `Mem Critical`) while a finding is critical

## 🧑‍💻 Contributing

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for workspace layout, adding a probe or
rule, and the JSON contract's versioning rules.

## 📜 License

MIT
