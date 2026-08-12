use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::error::VitalsError;

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
const POLL_INTERVAL: Duration = Duration::from_millis(20);

/// Runs `command arg0 arg1 ...` with [`DEFAULT_TIMEOUT`] and returns its
/// captured stdout.
pub(crate) fn run(command: &str, args: &[&str]) -> Result<String, VitalsError> {
    run_with_timeout(command, args, DEFAULT_TIMEOUT)
}

/// Like [`run`], but with an explicit timeout — for commands like `ddev
/// list` that legitimately need longer than the default (it talks to
/// Docker per project) but must still fail fast instead of hanging the
/// whole tool if the backend stalls, discovered the hard way when
/// OrbStack stalled mid-development and `ddev list` hung for minutes.
///
/// stdout/stderr are drained on background threads while polling for
/// exit, not read after the child exits — `ps -eo` on a busy Mac can
/// produce output close to the OS pipe buffer size, and reading only
/// after `wait()` would deadlock: the child blocks writing to a full
/// pipe that nothing is draining.
pub(crate) fn run_with_timeout(
    command: &str,
    args: &[&str],
    timeout: Duration,
) -> Result<String, VitalsError> {
    let invocation = || format!("{command} {}", args.join(" "));

    let mut child = Command::new(command)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|source| VitalsError::CommandFailed {
            command: invocation(),
            source,
        })?;

    let mut stdout_pipe = child.stdout.take().expect("stdout was piped");
    let mut stderr_pipe = child.stderr.take().expect("stderr was piped");
    let stdout_handle = std::thread::spawn(move || {
        let mut buf = String::new();
        let _ = stdout_pipe.read_to_string(&mut buf);
        buf
    });
    let stderr_handle = std::thread::spawn(move || {
        let mut buf = String::new();
        let _ = stderr_pipe.read_to_string(&mut buf);
        buf
    });

    let start = Instant::now();
    let status = loop {
        if let Some(status) = child
            .try_wait()
            .map_err(|source| VitalsError::CommandFailed {
                command: invocation(),
                source,
            })?
        {
            break status;
        }
        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Err(VitalsError::Timeout {
                command: invocation(),
                seconds: timeout.as_secs(),
            });
        }
        std::thread::sleep(POLL_INTERVAL);
    };

    let stdout = stdout_handle.join().unwrap_or_default();
    let stderr = stderr_handle.join().unwrap_or_default();

    if !status.success() {
        return Err(VitalsError::CommandExitedWithError {
            command: invocation(),
            stderr,
        });
    }

    Ok(stdout)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_stdout_of_a_successful_command() {
        let output = run("echo", &["hello"]).unwrap();
        assert_eq!(output.trim(), "hello");
    }

    #[test]
    fn surfaces_non_zero_exit_as_an_error() {
        let err = run("sh", &["-c", "exit 1"]).unwrap_err();
        assert!(matches!(err, VitalsError::CommandExitedWithError { .. }));
    }

    #[test]
    fn kills_and_times_out_a_slow_command() {
        let start = Instant::now();
        let err = run_with_timeout("sleep", &["5"], Duration::from_millis(100)).unwrap_err();
        assert!(matches!(err, VitalsError::Timeout { .. }));
        assert!(start.elapsed() < Duration::from_secs(2));
    }

    #[test]
    fn drains_output_larger_than_a_pipe_buffer_without_deadlocking() {
        let output = run_with_timeout(
            "sh",
            &["-c", "yes x | head -c 200000"],
            Duration::from_secs(5),
        )
        .unwrap();
        assert_eq!(output.len(), 200_000);
    }
}
