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
- **One-shot fixes** — stop a backup, stop a DDEV project, kill a stale session or a runaway process, prune dangling images — always behind a confirmation
- **JSON contract** — `vitals --json` for scripting, with a full per-container CPU/memory breakdown tagged by DDEV project
- **Menubar app** — load/CPU/RAM history as sparklines, a top-CPU-processes list, and live DDEV projects and Claude Code sessions, each with their own resource attribution

## 🔥 Installation

### Homebrew

**CLI** — <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-version.json&style=flat-square&logo=homebrew" alt="Homebrew version"></a> <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-downloads.json&style=flat-square&logo=homebrew" alt="Homebrew downloads"></a>

```sh
brew install konradmichalik/tap/vitals
```

**Menubar app** — <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-app-version.json&style=flat-square&logo=homebrew" alt="Homebrew version"></a> <a href="https://github.com/konradmichalik/homebrew-tap"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fkonradmichalik.github.io%2Fhomebrew-tap%2Fbadges%2Fvitals-app-downloads.json&style=flat-square&logo=homebrew" alt="Homebrew downloads"></a>

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
vitals --fix kill_session --target 90548
vitals --fix kill_runaway_processes
vitals --fix prune_docker_images
vitals --fix kill_orphaned_agents --dry-run

# free everything idle: idle DDEV projects, idle Claude sessions, orphaned agents
vitals --fix free_idle --dry-run
vitals --fix free_idle --scope ddev,orphans --protect witte --idle-minutes 60

vitals --fix stop_project --target verdi,pagetree   # several targets at once
vitals --fix start_project --target verdi
vitals --fix quit_app --target "Google Chrome"
vitals --fix restart_app --target PhpStorm
```

Every action asks for confirmation unless `actions.require_confirmation = false` is set
in `~/.vitals.toml`. There is no "kill all": `free_idle` only touches items that count as
idle under `[idle]` (no transcript write or container activity for `after_minutes`) and
never anything listed in `idle.protected`. The TTY report lists these as quick wins with
the exact command to run.

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

The menu bar shows how full memory is, and the free memory (or CPU) once macOS reports
pressure. The popover leads with one sentence about the state of the Mac, four vital
signs with their recent trend (memory, CPU, swap, disk), quick wins with the memory each
one gives back, and the top consumers grouped as DDEV, AI agents, PhpStorm, containers,
browser, other apps and system. A tap opens the items of a group, the history of a metric
(with the pressure level macOS reported), or the activity log with memory incidents read
from macOS' JetsamEvent reports.

Idle items are freed without asking and can be started again from the toast; anything
that interrupts work (quitting an app, ending an active session) asks first. Guard, off by
default, frees idle items on its own once memory pressure reaches the chosen level.
Actions run through the installed `vitals` CLI.

After pulling changes that add or remove Swift files, regenerate the project with
`make -C app xcode`.

## 🧑‍💻 Contributing

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for workspace layout, adding a probe or
rule, and the JSON contract's versioning rules.

## 📜 License

MIT
