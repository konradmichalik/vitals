//! Groups the process table into the consumer groups the menubar app
//! shows ("DDEV", "AI agents", "PhpStorm", …), marks idle items, and
//! derives the quick wins from them.
//!
//! Memory figures are resident set sizes from `ps` (and `docker stats`
//! for containers). RSS counts shared pages once per process, so group
//! totals can add up to more than the physical memory in use; they are
//! good for ranking and for estimating what ending something returns,
//! not for an exact budget.

use std::collections::{HashMap, HashSet};

use crate::config::Config;
use crate::probes::processes::ProcessEntry;
use crate::rules;
use crate::types::{
    AcpAgent, ClaudeSession, ConsumerGroup, ConsumerItem, DdevProjectInfo, DockerContainer,
    ItemAction, QuickWin, VitalsReport,
};

const BROWSERS: &[(&str, &str)] = &[
    ("/Google Chrome.app/", "Google Chrome"),
    ("/Firefox.app/", "Firefox"),
    ("/Arc.app/", "Arc"),
    ("/Brave Browser.app/", "Brave"),
    ("/Microsoft Edge.app/", "Microsoft Edge"),
    ("/Zen.app/", "Zen"),
    ("/Vivaldi.app/", "Vivaldi"),
    ("/Opera.app/", "Opera"),
    ("/Safari.app/", "Safari"),
];

/// Apps whose memory is the container VM. Their RSS already contains
/// what `docker stats` reports per container, so they are shown as VM
/// overhead next to the containers, never as an app of their own.
const VM_HOSTS: &[&str] = &["/OrbStack.app/", "/Docker.app/"];

/// Quitting a terminal ends every shell and agent session inside it.
const TERMINALS: &[&str] = &[
    "Warp",
    "Terminal",
    "iTerm",
    "iTerm2",
    "Ghostty",
    "kitty",
    "Alacritty",
    "WezTerm",
];

/// Never offered for quitting: the system needs them or they are us.
const NEVER_QUIT: &[&str] = &[
    "Finder",
    "VitalsApp",
    "Dock",
    "SystemUIServer",
    "loginwindow",
];

const APPS_SHOWN: usize = 5;

pub struct Inputs<'a> {
    pub processes: &'a [ProcessEntry],
    pub sessions: &'a [ClaudeSession],
    pub acp_agents: &'a [AcpAgent],
    pub containers: &'a [DockerContainer],
    pub ddev_projects: &'a [DdevProjectInfo],
    pub config: &'a Config,
    pub home: Option<&'a str>,
}

/// PIDs of `root` and everything it started, using the `ppid` column.
pub fn tree_pids(processes: &[ProcessEntry], root: u32) -> Vec<u32> {
    let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
    for p in processes {
        if p.pid != p.ppid {
            children.entry(p.ppid).or_default().push(p.pid);
        }
    }
    let mut out = vec![root];
    let mut seen = HashSet::from([root]);
    let mut i = 0;
    while i < out.len() {
        if let Some(kids) = children.get(&out[i]) {
            for &kid in kids {
                if seen.insert(kid) {
                    out.push(kid);
                }
            }
        }
        i += 1;
    }
    out
}

pub fn tree_rss(processes: &[ProcessEntry], root: u32) -> u64 {
    let by_pid: HashMap<u32, &ProcessEntry> = processes.iter().map(|p| (p.pid, p)).collect();
    tree_pids(processes, root)
        .iter()
        .filter_map(|pid| by_pid.get(pid))
        .map(|p| p.rss_bytes)
        .sum()
}

pub fn human_duration(seconds: u64) -> String {
    match seconds {
        s if s < 3600 => format!("{} min", (s / 60).max(1)),
        s if s < 2 * 86400 => format!("{} h", s / 3600),
        s => format!("{} days", s / 86400),
    }
}

fn idle_after_seconds(config: &Config) -> u64 {
    (config.idle.after_minutes * 60.0) as u64
}

fn app_name(comm: &str) -> Option<&str> {
    let end = comm.find(".app/")?;
    let start = comm[..end].rfind('/').map_or(0, |i| i + 1);
    Some(&comm[start..end])
}

fn is_system_path(comm: &str) -> bool {
    !comm.starts_with('/')
        || [
            "/System/",
            "/usr/",
            "/sbin/",
            "/bin/",
            "/Library/Apple/",
            "/private/",
        ]
        .iter()
        .any(|prefix| comm.starts_with(prefix))
            && !comm.starts_with("/System/Applications/")
}

pub fn groups(inputs: &Inputs) -> Vec<ConsumerGroup> {
    let mut claimed: HashSet<u32> = HashSet::new();
    let mut out = Vec::new();

    out.extend(ddev_group(inputs));
    out.extend(agents_group(inputs, &mut claimed));
    out.extend(phpstorm_group(inputs, &mut claimed));
    out.extend(containers_group(inputs, &mut claimed));
    out.extend(browser_group(inputs, &mut claimed));
    let (apps, system) = apps_and_system(inputs, &claimed);
    out.extend(apps);
    out.extend(system);

    out.sort_by_key(|a| std::cmp::Reverse(a.mem_bytes));
    out
}

fn group(id: &str, name: &str, items: Vec<ConsumerItem>) -> Option<ConsumerGroup> {
    if items.is_empty() {
        return None;
    }
    Some(ConsumerGroup {
        id: id.to_string(),
        name: name.to_string(),
        mem_bytes: items.iter().map(|i| i.mem_bytes).sum(),
        cpu_percent: items.iter().map(|i| i.cpu_percent).sum(),
        idle_bytes: items.iter().filter(|i| i.idle).map(|i| i.mem_bytes).sum(),
        items,
    })
}

fn action(name: &str, target: Option<String>, label: &str, confirm: bool) -> Option<ItemAction> {
    Some(ItemAction {
        action: name.to_string(),
        target,
        label: label.to_string(),
        confirm,
    })
}

fn ddev_group(inputs: &Inputs) -> Option<ConsumerGroup> {
    let after = idle_after_seconds(inputs.config);
    let mut items: Vec<ConsumerItem> = inputs
        .ddev_projects
        .iter()
        .filter(|p| p.status == "running")
        .map(|p| {
            let protected = inputs.config.is_protected(&p.name, inputs.home)
                || inputs.config.is_protected(&p.approot, inputs.home);
            let idle_seconds = p.idle_seconds;
            let idle = !protected && idle_seconds.is_some_and(|s| s >= after);
            let detail = match (protected, idle_seconds) {
                (true, _) => "protected".to_string(),
                (false, Some(s)) if s >= 60 => format!("no activity for {}", human_duration(s)),
                _ => "in use".to_string(),
            };
            ConsumerItem {
                id: format!("ddev:{}", p.name),
                name: p.name.clone(),
                detail,
                mem_bytes: p.mem_bytes,
                cpu_percent: p.cpu_percent,
                idle,
                idle_seconds,
                protected,
                action: action("stop_project", Some(p.name.clone()), "Stop", false),
            }
        })
        .collect();

    let shared: Vec<&DockerContainer> = inputs
        .containers
        .iter()
        .filter(|c| c.ddev_managed && c.ddev_project.is_none())
        .collect();
    if !shared.is_empty() {
        items.push(ConsumerItem {
            id: "ddev:shared".to_string(),
            name: "DDEV router".to_string(),
            detail: "shared by all projects".to_string(),
            mem_bytes: shared.iter().map(|c| c.mem_bytes).sum(),
            cpu_percent: shared.iter().map(|c| c.cpu_percent).sum(),
            idle: false,
            idle_seconds: None,
            protected: false,
            action: None,
        });
    }
    group("ddev", "DDEV", items)
}

fn session_label(session: &ClaudeSession) -> String {
    session
        .working_directory
        .as_deref()
        .and_then(|dir| dir.rsplit('/').find(|s| !s.is_empty()))
        .map_or_else(|| format!("v{}", session.version), str::to_string)
}

fn agents_group(inputs: &Inputs, claimed: &mut HashSet<u32>) -> Option<ConsumerGroup> {
    let after = idle_after_seconds(inputs.config);
    let items = inputs
        .sessions
        .iter()
        .map(|s| {
            claimed.extend(tree_pids(inputs.processes, s.pid));
            let protected = s
                .working_directory
                .as_deref()
                .is_some_and(|dir| inputs.config.is_protected(dir, inputs.home));
            let idle = !protected && s.idle_seconds.is_some_and(|i| i >= after);
            let detail = if protected {
                "protected".to_string()
            } else if let Some(i) = s.idle_seconds.filter(|i| *i >= after) {
                format!("no transcript write for {}", human_duration(i))
            } else {
                format!("working, running {}", human_duration(s.etime_seconds))
            };
            ConsumerItem {
                id: format!("session:{}", s.pid),
                name: session_label(s),
                detail,
                mem_bytes: s.tree_rss_bytes.max(s.rss_bytes),
                cpu_percent: s.cpu_percent,
                idle,
                idle_seconds: s.idle_seconds,
                protected,
                action: action("kill_session", Some(s.pid.to_string()), "End", !idle),
            }
        })
        .collect();
    group("agents", "AI agents", items)
}

fn phpstorm_group(inputs: &Inputs, claimed: &mut HashSet<u32>) -> Option<ConsumerGroup> {
    let mut items = Vec::new();

    let ide: Vec<&ProcessEntry> = inputs
        .processes
        .iter()
        .filter(|p| p.comm.contains("/PhpStorm.app/") && !claimed.contains(&p.pid))
        .collect();
    if !ide.is_empty() {
        let mut pids: HashSet<u32> = HashSet::new();
        for p in &ide {
            for pid in tree_pids(inputs.processes, p.pid) {
                if !claimed.contains(&pid) {
                    pids.insert(pid);
                }
            }
        }
        // Agents are listed separately below.
        for agent in inputs.acp_agents {
            for pid in tree_pids(inputs.processes, agent.pid) {
                pids.remove(&pid);
            }
        }
        let members: Vec<&ProcessEntry> = inputs
            .processes
            .iter()
            .filter(|p| pids.contains(&p.pid))
            .collect();
        let open_for = ide.iter().map(|p| p.etime_seconds).max().unwrap_or(0);
        claimed.extend(pids.iter().copied());
        items.push(ConsumerItem {
            id: "app:PhpStorm".to_string(),
            name: "PhpStorm".to_string(),
            detail: format!("IDE, open for {}", human_duration(open_for)),
            mem_bytes: members.iter().map(|p| p.rss_bytes).sum(),
            cpu_percent: members.iter().map(|p| p.cpu_percent).sum(),
            idle: false,
            idle_seconds: None,
            protected: false,
            action: action("restart_app", Some("PhpStorm".to_string()), "Restart", true),
        });
    }

    for agent in inputs.acp_agents {
        let pids = tree_pids(inputs.processes, agent.pid);
        claimed.extend(pids.iter().copied());
        let mem = tree_rss(inputs.processes, agent.pid);
        let detail = if agent.orphaned {
            format!("left behind, {}", agent.ide_version)
        } else {
            format!("agent of {}", agent.ide_version)
        };
        items.push(ConsumerItem {
            id: format!("acp:{}", agent.pid),
            name: "ACP agent".to_string(),
            detail,
            mem_bytes: mem,
            cpu_percent: 0.0,
            idle: agent.orphaned,
            idle_seconds: None,
            protected: false,
            action: action(
                "kill_session",
                Some(agent.pid.to_string()),
                "Quit",
                !agent.orphaned,
            ),
        });
    }
    group("phpstorm", "PhpStorm", items)
}

fn containers_group(inputs: &Inputs, claimed: &mut HashSet<u32>) -> Option<ConsumerGroup> {
    let mut by_project: HashMap<String, (u64, f64, usize)> = HashMap::new();
    for c in inputs.containers.iter().filter(|c| !c.ddev_managed) {
        let key = c.compose_project.clone().unwrap_or_else(|| c.name.clone());
        let entry = by_project.entry(key).or_insert((0, 0.0, 0));
        entry.0 += c.mem_bytes;
        entry.1 += c.cpu_percent;
        entry.2 += 1;
    }
    let mut items: Vec<ConsumerItem> = by_project
        .into_iter()
        .map(|(name, (mem, cpu, count))| ConsumerItem {
            id: format!("compose:{name}"),
            name,
            detail: format!("{count} container(s) outside DDEV"),
            mem_bytes: mem,
            cpu_percent: cpu,
            idle: false,
            idle_seconds: None,
            protected: false,
            action: None,
        })
        .collect();

    let vm: Vec<&ProcessEntry> = inputs
        .processes
        .iter()
        .filter(|p| VM_HOSTS.iter().any(|host| p.comm.contains(host)))
        .collect();
    claimed.extend(vm.iter().map(|p| p.pid));
    let vm_rss: u64 = vm.iter().map(|p| p.rss_bytes).sum();
    let in_containers: u64 = inputs.containers.iter().map(|c| c.mem_bytes).sum();
    if vm_rss > in_containers {
        let host = vm
            .iter()
            .find_map(|p| app_name(&p.comm))
            .unwrap_or("Container VM")
            .to_string();
        items.push(ConsumerItem {
            id: "vm".to_string(),
            name: format!("{host} VM"),
            detail: "Linux VM beyond what containers use".to_string(),
            mem_bytes: vm_rss - in_containers,
            cpu_percent: vm.iter().map(|p| p.cpu_percent).sum(),
            idle: false,
            idle_seconds: None,
            protected: false,
            action: None,
        });
    }
    items.sort_by_key(|a| std::cmp::Reverse(a.mem_bytes));
    group("containers", "Containers", items)
}

fn browser_group(inputs: &Inputs, claimed: &mut HashSet<u32>) -> Option<ConsumerGroup> {
    let items = BROWSERS
        .iter()
        .filter_map(|(marker, name)| {
            let procs: Vec<&ProcessEntry> = inputs
                .processes
                .iter()
                .filter(|p| p.comm.contains(marker) && !claimed.contains(&p.pid))
                .collect();
            if procs.is_empty() {
                return None;
            }
            claimed.extend(procs.iter().map(|p| p.pid));
            Some(ConsumerItem {
                id: format!("app:{name}"),
                name: name.to_string(),
                detail: format!("{} processes", procs.len()),
                mem_bytes: procs.iter().map(|p| p.rss_bytes).sum(),
                cpu_percent: procs.iter().map(|p| p.cpu_percent).sum(),
                idle: false,
                idle_seconds: None,
                protected: false,
                action: action("quit_app", Some(name.to_string()), "Quit", true),
            })
        })
        .collect();
    group("browser", "Browser", items)
}

fn apps_and_system(
    inputs: &Inputs,
    claimed: &HashSet<u32>,
) -> (Option<ConsumerGroup>, Option<ConsumerGroup>) {
    let mut apps: HashMap<String, (u64, f64, usize, bool)> = HashMap::new();
    let (mut sys_mem, mut sys_cpu) = (0u64, 0f64);

    for p in inputs
        .processes
        .iter()
        .filter(|p| !claimed.contains(&p.pid))
    {
        if let Some(name) = app_name(&p.comm).filter(|_| !p.comm.starts_with("/System/Library/")) {
            let entry = apps.entry(name.to_string()).or_insert((0, 0.0, 0, true));
            entry.0 += p.rss_bytes;
            entry.1 += p.cpu_percent;
            entry.2 += 1;
        } else if is_system_path(&p.comm) {
            sys_mem += p.rss_bytes;
            sys_cpu += p.cpu_percent;
        } else {
            let name = p.comm.rsplit('/').next().unwrap_or(&p.comm).to_string();
            let entry = apps.entry(name).or_insert((0, 0.0, 0, false));
            entry.0 += p.rss_bytes;
            entry.1 += p.cpu_percent;
            entry.2 += 1;
        }
    }

    let mut sorted: Vec<(String, (u64, f64, usize, bool))> = apps.into_iter().collect();
    sorted.sort_by(|a, b| b.1 .0.cmp(&a.1 .0).then_with(|| a.0.cmp(&b.0)));
    let rest = sorted.split_off(sorted.len().min(APPS_SHOWN));

    let mut items: Vec<ConsumerItem> = sorted
        .into_iter()
        .map(|(name, (mem, cpu, count, is_app))| {
            let terminal = TERMINALS.contains(&name.as_str());
            let detail = if terminal {
                "hosts your terminal sessions".to_string()
            } else if is_app {
                format!("{count} process(es)")
            } else {
                "command line".to_string()
            };
            let quit = is_app && !terminal && !NEVER_QUIT.contains(&name.as_str());
            ConsumerItem {
                id: format!("app:{name}"),
                detail,
                mem_bytes: mem,
                cpu_percent: cpu,
                idle: false,
                idle_seconds: None,
                protected: false,
                action: if quit {
                    action("quit_app", Some(name.clone()), "Quit", true)
                } else {
                    None
                },
                name,
            }
        })
        .collect();
    if !rest.is_empty() {
        items.push(ConsumerItem {
            id: "app:rest".to_string(),
            name: format!("{} more", rest.len()),
            detail: "smaller apps and tools".to_string(),
            mem_bytes: rest.iter().map(|r| r.1 .0).sum(),
            cpu_percent: rest.iter().map(|r| r.1 .1).sum(),
            idle: false,
            idle_seconds: None,
            protected: false,
            action: None,
        });
    }

    let system = (sys_mem > 0).then(|| ConsumerItem {
        id: "system".to_string(),
        name: "macOS".to_string(),
        detail: "kernel, WindowServer and services".to_string(),
        mem_bytes: sys_mem,
        cpu_percent: sys_cpu,
        idle: false,
        idle_seconds: None,
        protected: false,
        action: None,
    });

    (
        group("apps", "Other apps", items),
        group("system", "System", system.into_iter().collect()),
    )
}

/// Idle items per kind, as the targets `--fix free_idle` acts on.
#[derive(Debug, Default, PartialEq)]
pub struct IdleTargets {
    pub ddev_projects: Vec<String>,
    pub session_pids: Vec<u32>,
    pub orphaned_agent_pids: Vec<u32>,
    pub bytes: u64,
}

pub fn idle_targets(groups: &[ConsumerGroup]) -> IdleTargets {
    let mut targets = IdleTargets::default();
    for item in groups
        .iter()
        .flat_map(|g| g.items.iter())
        .filter(|i| i.idle && !i.protected)
    {
        let target = item.action.as_ref().and_then(|a| a.target.clone());
        if let Some(name) = item.id.strip_prefix("ddev:").and(target.clone()) {
            targets.ddev_projects.push(name);
        } else if item.id.starts_with("session:") {
            targets
                .session_pids
                .extend(target.and_then(|t| t.parse::<u32>().ok()));
        } else if item.id.starts_with("acp:") {
            targets
                .orphaned_agent_pids
                .extend(target.and_then(|t| t.parse::<u32>().ok()));
        } else {
            continue;
        }
        targets.bytes += item.mem_bytes;
    }
    targets
}

fn plural(n: usize, word: &str) -> String {
    format!("{n} {word}{}", if n == 1 { "" } else { "s" })
}

pub fn quick_wins(
    groups: &[ConsumerGroup],
    report: &VitalsReport,
    processes: &[ProcessEntry],
    config: &Config,
) -> Vec<QuickWin> {
    let idle_items = |group_id: &str| -> Vec<&ConsumerItem> {
        groups
            .iter()
            .filter(|g| g.id == group_id)
            .flat_map(|g| g.items.iter())
            .filter(|i| i.idle && !i.protected)
            .collect()
    };
    let target = |item: &ConsumerItem| item.action.as_ref().and_then(|a| a.target.clone());

    let mut memory_wins = Vec::new();

    let ddev = idle_items("ddev");
    if !ddev.is_empty() {
        memory_wins.push(QuickWin {
            id: "stop_idle_ddev".to_string(),
            title: format!("Stop {}", plural(ddev.len(), "idle DDEV project")),
            detail: ddev
                .iter()
                .map(|i| i.name.as_str())
                .collect::<Vec<_>>()
                .join(", "),
            reclaimable_bytes: ddev.iter().map(|i| i.mem_bytes).sum(),
            action: "stop_project".to_string(),
            targets: ddev.iter().filter_map(|i| target(i)).collect(),
            label: "Stop".to_string(),
            confirm: false,
            undo_action: Some("start_project".to_string()),
        });
    }

    let sessions: Vec<&ConsumerItem> = idle_items("agents");
    if !sessions.is_empty() {
        let shortest = sessions
            .iter()
            .filter_map(|i| i.idle_seconds)
            .min()
            .unwrap_or(0);
        memory_wins.push(QuickWin {
            id: "end_idle_sessions".to_string(),
            title: format!("End {}", plural(sessions.len(), "idle agent session")),
            detail: format!("No transcript write for {}+", human_duration(shortest)),
            reclaimable_bytes: sessions.iter().map(|i| i.mem_bytes).sum(),
            action: "kill_session".to_string(),
            targets: sessions.iter().filter_map(|i| target(i)).collect(),
            label: "End".to_string(),
            confirm: false,
            undo_action: None,
        });
    }

    let orphans: Vec<&ConsumerItem> = idle_items("phpstorm");
    if !orphans.is_empty() {
        memory_wins.push(QuickWin {
            id: "quit_orphaned_agents".to_string(),
            title: format!("Quit {}", plural(orphans.len(), "orphaned agent")),
            detail: "Left behind by a closed or retired IDE".to_string(),
            reclaimable_bytes: orphans.iter().map(|i| i.mem_bytes).sum(),
            action: "kill_session".to_string(),
            targets: orphans.iter().filter_map(|i| target(i)).collect(),
            label: "Quit".to_string(),
            confirm: false,
            undo_action: None,
        });
    }
    memory_wins.sort_by_key(|a| std::cmp::Reverse(a.reclaimable_bytes));

    let mut other_wins = Vec::new();
    let runaway: Vec<&ProcessEntry> = processes
        .iter()
        .filter(|p| rules::is_runaway(p, config))
        .collect();
    if !runaway.is_empty() {
        let names: Vec<String> = runaway
            .iter()
            .map(|p| p.comm.rsplit('/').next().unwrap_or(&p.comm).to_string())
            .collect();
        other_wins.push(QuickWin {
            id: "quit_runaway".to_string(),
            title: format!(
                "Quit {}",
                plural(runaway.len(), "runaway process").replace("processs", "processes")
            ),
            detail: format!("{} · asks first", names.join(", ")),
            reclaimable_bytes: 0,
            action: "kill_runaway_processes".to_string(),
            targets: Vec::new(),
            label: "Quit".to_string(),
            confirm: true,
            undo_action: None,
        });
    }

    let changed = report.time_machine.changed_item_count.unwrap_or(0);
    if report.time_machine.running && changed > config.thresholds.changed_items_warn {
        other_wins.push(QuickWin {
            id: "stop_backup".to_string(),
            title: "Stop the running backup".to_string(),
            detail: format!("Time Machine is scanning {changed} changed items"),
            reclaimable_bytes: 0,
            action: "stop_backup".to_string(),
            targets: Vec::new(),
            label: "Stop".to_string(),
            confirm: false,
            undo_action: None,
        });
    }

    let included: Vec<&str> = report
        .time_machine
        .exclusions
        .iter()
        .filter(|e| !e.excluded)
        .map(|e| e.path.as_str())
        .collect();
    if !included.is_empty() {
        other_wins.push(QuickWin {
            id: "add_exclusions".to_string(),
            title: format!("Skip {} in backups", included.join(", ")),
            detail: "Container data changes on every start".to_string(),
            reclaimable_bytes: 0,
            action: "add_exclusions".to_string(),
            targets: Vec::new(),
            label: "Exclude".to_string(),
            confirm: false,
            undo_action: None,
        });
    }

    memory_wins.extend(other_wins);
    memory_wins
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(pid: u32, ppid: u32, comm: &str, rss_mb: u64, cpu: f64) -> ProcessEntry {
        ProcessEntry {
            pid,
            ppid,
            etime_seconds: 3600,
            cpu_percent: cpu,
            rss_bytes: rss_mb * 1024 * 1024,
            comm: comm.to_string(),
            command: comm.to_string(),
        }
    }

    const MB: u64 = 1024 * 1024;

    fn session(pid: u32, dir: &str, idle: Option<u64>, tree_mb: u64) -> ClaudeSession {
        ClaudeSession {
            pid,
            etime_seconds: 7200,
            cpu_percent: 1.0,
            rss_bytes: 100 * MB,
            kind: "cli".to_string(),
            version: "2.1.228".to_string(),
            working_directory: Some(dir.to_string()),
            tree_rss_bytes: tree_mb * MB,
            idle_seconds: idle,
        }
    }

    fn project(name: &str, idle: Option<u64>, mem_mb: u64) -> DdevProjectInfo {
        DdevProjectInfo {
            name: name.to_string(),
            status: "running".to_string(),
            approot: format!("/Users/km/Sites/{name}"),
            mem_bytes: mem_mb * MB,
            cpu_percent: 0.5,
            idle_seconds: idle,
        }
    }

    fn container(name: &str, ddev: Option<&str>, managed: bool, mem_mb: u64) -> DockerContainer {
        DockerContainer {
            id: name.to_string(),
            name: name.to_string(),
            image: "img".to_string(),
            cpu_percent: 0.1,
            mem_bytes: mem_mb * MB,
            ddev_managed: managed,
            ddev_project: ddev.map(str::to_string),
            compose_project: None,
        }
    }

    type Fixture = (
        Vec<ProcessEntry>,
        Vec<ClaudeSession>,
        Vec<AcpAgent>,
        Vec<DockerContainer>,
        Vec<DdevProjectInfo>,
    );

    fn fixture() -> Fixture {
        let processes = vec![
            p(1, 0, "/sbin/launchd", 20, 0.1),
            p(100, 1, "/System/Library/CoreServices/WindowServer", 500, 5.0),
            p(200, 1, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", 800, 2.0),
            p(201, 200, "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", 400, 1.0),
            p(300, 1, "/Applications/Warp.app/Contents/MacOS/stable", 700, 3.0),
            p(301, 300, "claude", 300, 1.0),
            p(302, 301, "/opt/homebrew/bin/node", 200, 0.5),
            p(310, 300, "claude", 250, 0.2),
            p(400, 1, "/Applications/PhpStorm.app/Contents/MacOS/phpstorm", 2000, 4.0),
            p(401, 400, "/Applications/PhpStorm.app/Contents/bin/fsnotifier", 10, 0.0),
            p(500, 1, "node", 150, 0.0),
            p(600, 1, "/Applications/OrbStack.app/Contents/Frameworks/OrbStack Helper.app/Contents/MacOS/OrbStack Helper", 5000, 30.0),
            p(700, 1, "/Applications/Slack.app/Contents/MacOS/Slack", 600, 1.0),
            p(800, 300, "/opt/homebrew/bin/node", 900, 80.0),
        ];
        let sessions = vec![
            session(301, "/Users/km/Sites/vitals", Some(600), 500),
            session(310, "/Users/km/Sites/old", Some(5 * 3600), 250),
        ];
        let agents = vec![AcpAgent {
            pid: 500,
            etime_seconds: 86400,
            ide_version: "PhpStorm2026.1".to_string(),
            orphaned: true,
        }];
        let containers = vec![
            container("ddev-witte-db", Some("witte"), true, 1500),
            container("ddev-verdi-db", Some("verdi"), true, 1200),
            container("ddev-router", None, true, 50),
            container("shop-postgres", None, false, 400),
        ];
        let projects = vec![
            project("witte", Some(60), 3100),
            project("verdi", Some(3 * 3600), 1400),
        ];
        (processes, sessions, agents, containers, projects)
    }

    fn build(config: &Config) -> Vec<ConsumerGroup> {
        let (processes, sessions, agents, containers, projects) = fixture();
        groups(&Inputs {
            processes: &processes,
            sessions: &sessions,
            acp_agents: &agents,
            containers: &containers,
            ddev_projects: &projects,
            config,
            home: Some("/Users/km"),
        })
    }

    fn find<'a>(groups: &'a [ConsumerGroup], id: &str) -> &'a ConsumerGroup {
        groups
            .iter()
            .find(|g| g.id == id)
            .unwrap_or_else(|| panic!("no group {id}"))
    }

    #[test]
    fn tree_rss_includes_descendants_once() {
        let (processes, ..) = fixture();
        assert_eq!(tree_rss(&processes, 301), 500 * MB);
        assert_eq!(tree_pids(&processes, 300).len(), 5);
    }

    #[test]
    fn idle_ddev_project_is_marked_and_in_use_one_is_not() {
        let groups = build(&Config::default());
        let ddev = find(&groups, "ddev");
        let verdi = ddev.items.iter().find(|i| i.name == "verdi").unwrap();
        let witte = ddev.items.iter().find(|i| i.name == "witte").unwrap();
        assert!(verdi.idle);
        assert_eq!(verdi.detail, "no activity for 3 h");
        assert!(!witte.idle);
        assert_eq!(ddev.idle_bytes, 1400 * MB);
        assert!(ddev
            .items
            .iter()
            .any(|i| i.name == "DDEV router" && i.action.is_none()));
    }

    #[test]
    fn protected_items_are_never_idle() {
        let mut config = Config::default();
        config.idle.protected = vec!["verdi".to_string(), "~/Sites/old".to_string()];
        let groups = build(&config);
        assert_eq!(find(&groups, "ddev").idle_bytes, 0);
        assert_eq!(find(&groups, "agents").idle_bytes, 0);
        assert!(find(&groups, "agents")
            .items
            .iter()
            .any(|i| i.protected && i.detail == "protected"));
    }

    #[test]
    fn sessions_claim_their_child_processes_and_idle_ones_end_without_asking() {
        let groups = build(&Config::default());
        let agents = find(&groups, "agents");
        let old = agents.items.iter().find(|i| i.name == "old").unwrap();
        let vitals = agents.items.iter().find(|i| i.name == "vitals").unwrap();
        assert!(old.idle);
        assert_eq!(old.action.as_ref().map(|a| a.confirm), Some(false));
        assert_eq!(vitals.mem_bytes, 500 * MB);
        assert_eq!(vitals.action.as_ref().map(|a| a.confirm), Some(true));
        assert!(vitals.detail.starts_with("working"));
    }

    #[test]
    fn phpstorm_group_holds_the_ide_and_orphaned_agents() {
        let groups = build(&Config::default());
        let ide = find(&groups, "phpstorm");
        let app = ide.items.iter().find(|i| i.id == "app:PhpStorm").unwrap();
        assert_eq!(app.mem_bytes, 2010 * MB);
        assert_eq!(
            app.action.as_ref().map(|a| a.action.as_str()),
            Some("restart_app")
        );
        let agent = ide.items.iter().find(|i| i.id == "acp:500").unwrap();
        assert!(agent.idle);
    }

    #[test]
    fn vm_host_is_shown_as_overhead_not_as_an_app() {
        let groups = build(&Config::default());
        let containers = find(&groups, "containers");
        let vm = containers.items.iter().find(|i| i.id == "vm").unwrap();
        assert_eq!(vm.name, "OrbStack VM");
        assert_eq!(vm.mem_bytes, (5000 - 1500 - 1200 - 50 - 400) * MB);
        assert!(containers.items.iter().any(|i| i.name == "shop-postgres"));
        let apps = find(&groups, "apps");
        assert!(!apps.items.iter().any(|i| i.name == "OrbStack"));
    }

    #[test]
    fn browsers_and_apps_group_by_bundle_and_terminals_cannot_be_quit() {
        let groups = build(&Config::default());
        let chrome = &find(&groups, "browser").items[0];
        assert_eq!(chrome.name, "Google Chrome");
        assert_eq!(chrome.mem_bytes, 1200 * MB);
        let apps = find(&groups, "apps");
        let warp = apps.items.iter().find(|i| i.name == "Warp").unwrap();
        assert!(warp.action.is_none());
        let slack = apps.items.iter().find(|i| i.name == "Slack").unwrap();
        assert_eq!(slack.action.as_ref().map(|a| a.confirm), Some(true));
        let node = apps.items.iter().find(|i| i.name == "node").unwrap();
        assert_eq!(node.detail, "command line");
        assert!(node.action.is_none());
        assert_eq!(find(&groups, "system").items[0].mem_bytes, 520 * MB);
    }

    #[test]
    fn groups_are_sorted_by_memory() {
        let groups = build(&Config::default());
        assert!(groups.windows(2).all(|w| w[0].mem_bytes >= w[1].mem_bytes));
    }

    #[test]
    fn idle_targets_collects_every_kind() {
        let groups = build(&Config::default());
        let targets = idle_targets(&groups);
        assert_eq!(targets.ddev_projects, vec!["verdi"]);
        assert_eq!(targets.session_pids, vec![310]);
        assert_eq!(targets.orphaned_agent_pids, vec![500]);
        assert_eq!(targets.bytes, (1400 + 250 + 150) * MB);
    }

    #[test]
    fn quick_wins_list_memory_gains_first_largest_first() {
        let groups = build(&Config::default());
        let mut report = crate::rules::tests::base_report();
        report.time_machine.exclusions = vec![crate::types::TmExclusion {
            path: "~/.orbstack".to_string(),
            excluded: false,
        }];
        let (processes, ..) = fixture();
        let wins = quick_wins(&groups, &report, &processes, &Config::default());
        let ids: Vec<&str> = wins.iter().map(|w| w.id.as_str()).collect();
        assert_eq!(
            ids,
            vec![
                "stop_idle_ddev",
                "end_idle_sessions",
                "quit_orphaned_agents",
                "add_exclusions"
            ]
        );
        assert_eq!(wins[0].targets, vec!["verdi"]);
        assert_eq!(wins[0].undo_action.as_deref(), Some("start_project"));
        assert_eq!(wins[1].targets, vec!["310"]);
    }

    #[test]
    fn human_duration_reads_naturally() {
        assert_eq!(human_duration(30), "1 min");
        assert_eq!(human_duration(42 * 60), "42 min");
        assert_eq!(human_duration(5 * 3600), "5 h");
        assert_eq!(human_duration(4 * 86400), "4 days");
    }
}
