// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where a console writes.
pub(all) enum Stream {
  Stdout
  Stderr
  Auto
} derive(Eq, Debug)

///|
pub extend Stream with Debug::{to_repr}

///|
pub extend Stream with Eq::{equal, not_equal}

///|
/// The name used in configuration files.
pub fn Stream::name(self : Stream) -> StringView {
  match self {
    Stdout => "stdout"
    Stderr => "stderr"
    Auto => "auto"
  }
}

///|
/// `stdout`, `stderr` or `auto`.
pub fn Stream::parse(name : StringView) -> Stream raise Refused {
  match name {
    "stdout" => Stdout
    "stderr" => Stderr
    "auto" => Auto
    _ => raise refuse(0, name.to_owned(), "stdout, stderr or auto")
  }
}

///|
/// Another logger whose defaults an application can take on.
///
/// A profile changes four things at once — the default line, the stream a
/// console writes to, the level it starts at, and the variables a filter is
/// read from — because those four are what a deployment already expects when
/// it moves from one logger to another.
pub(all) enum Profile {
  Serlog
  Tracing
  EnvLogger
  Python
  Logback
  Slog
  Pino
} derive(Eq, Debug)

///|
pub extend Profile with Debug::{to_repr}

///|
pub extend Profile with Eq::{equal, not_equal}

///|
/// The name used in configuration files.
pub fn Profile::name(self : Profile) -> StringView {
  match self {
    Serlog => "serlog"
    Tracing => "tracing"
    EnvLogger => "env_logger"
    Python => "python"
    Logback => "logback"
    Slog => "slog"
    Pino => "pino"
  }
}

///|
/// A profile by its lower-case name: `serlog`, `tracing`, `env_logger`,
/// `python`, `logback` (or `log4j`), `slog` or `pino`.
pub fn Profile::parse(name : StringView) -> Profile raise Refused {
  match name {
    "serlog" => Serlog
    "tracing" => Tracing
    "env_logger" => EnvLogger
    "python" => Python
    "logback" | "log4j" => Logback
    "slog" => Slog
    "pino" => Pino
    _ => raise refuse(0, name.to_owned(), "a profile name")
  }
}

///|
/// The pattern this profile's logger writes by default.
pub fn Profile::pattern(self : Profile) -> StringView {
  match self {
    Serlog => "{time} {level:<5} {target}: {msg}{fields}"
    Tracing => "{time:rfc3339} {level:>5} {spans}{target}: {msg}{fields}"
    EnvLogger => "[{time:utc} {level:<5} {target}] {msg}"
    Python => "{level}:{target}:{msg}"
    Logback => "{time:%H:%M:%S%.3f} [{thread}] {level:<5} {target:~36} - {msg}"
    Slog =>
      "time={time:%Y-%m-%dT%H:%M:%S%.3f%:z} level={level} msg={msg:q}{fields:q}"
    Pino => "[{time:%H:%M:%S%.3f}] {level} ({pid}): {msg}{fields}"
  }
}

///|
/// Where this profile's console writes.
pub fn Profile::stream(self : Profile) -> Stream {
  match self {
    EnvLogger | Python => Stderr
    _ => Stdout
  }
}

///|
/// The level this profile starts at.
pub fn Profile::level(self : Profile) -> Level {
  match self {
    EnvLogger => error
    Python => warn
    Logback => debug
    _ => info
  }
}

///|
/// The variables this profile reads a filter from, first one set wins.
pub fn Profile::env(self : Profile) -> Array[String] {
  match self {
    Serlog => ["SERLOG_FILTER"]
    Tracing | EnvLogger => ["RUST_LOG"]
    _ => []
  }
}
