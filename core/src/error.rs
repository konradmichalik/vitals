use thiserror::Error;

#[derive(Debug, Error)]
pub enum VitalsError {
    #[error("failed to run `{command}`: {source}")]
    CommandFailed {
        command: String,
        #[source]
        source: std::io::Error,
    },

    #[error("`{command}` exited with a non-zero status: {stderr}")]
    CommandExitedWithError { command: String, stderr: String },

    #[error("failed to parse output of `{command}`: {reason}")]
    ParseError { command: String, reason: String },

    #[error("probe not yet implemented: {0}")]
    NotImplemented(&'static str),

    #[error("failed to read `{path}`: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },

    #[error("failed to parse `{path}`: {reason}")]
    ConfigError { path: String, reason: String },

    #[error("`{command}` did not finish within {seconds}s")]
    Timeout { command: String, seconds: u64 },
}

impl VitalsError {
    pub(crate) fn parse(command: impl Into<String>, reason: impl Into<String>) -> Self {
        VitalsError::ParseError {
            command: command.into(),
            reason: reason.into(),
        }
    }
}
