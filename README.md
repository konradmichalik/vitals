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
> Early development (v0.1–v0.4). Not yet published or installable via Homebrew — build from source (below).

## Features

- **Rule engine** — 13 rules cover Time Machine scanning container data, unexcluded backup paths, container load, Mutagen activity, memory pressure, memory ballast, orphaned PhpStorm ACP agents, stale Claude Code sessions, DDEV projects stuck in a problem state, Docker containers running outside DDEV's management, reclaimable disk space, critical load average, and sustained runaway-CPU processes
- **Named diagnoses, not graphs** — every finding says which project/PID/path is responsible, not just a number
- **One-shot fixes** — stop a backup, stop a DDEV project, kill a stale session or a runaway process, prune dangling images — always behind a confirmation
- **JSON contract** — `vitals --json` for scripting, with a full per-container CPU/memory breakdown tagged by DDEV project
- **Menubar app** — load/CPU/RAM history as sparklines, a top-CPU-processes list, and live DDEV projects and Claude Code sessions, each with their own resource attribution

## Building

No Apple Developer account needed — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the ad-hoc signing setup.

```sh
cargo build --workspace
cargo test --workspace
```

## Usage

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
vitals --fix kill_orphaned_agents --dry-run   # preview without running it
```

Every action asks for confirmation unless `actions.require_confirmation = false` is set
in `~/.vitals.toml` (not recommended) — there is no bulk "kill all" by design.

## Menubar app

```sh
cd app
make build   # xcodegen generate + cargo build (vitals-ffi) + xcodebuild
make test
make lint
```

A traffic-light icon (from the highest-severity finding) with a dropdown showing load
average, CPU/memory trends, running DDEV projects and Claude Code sessions (with their
CPU share), the current top processes by CPU, and any findings — each backed by the
same confirmation dialog before running a fix.

## Contributing

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for workspace layout, adding a probe or
rule, and the JSON contract's versioning rules.

## License

MIT
