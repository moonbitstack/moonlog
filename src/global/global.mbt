// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A hub owned by the process, which is the one thing the rest of this
/// library refuses to do.
///
/// It lives here because an application — as opposed to a library — has
/// exactly one place to configure, and because `SERLOG_FILTER`,
/// `SERLOG_COMPAT` and `SERLOG_FORMAT` are useful only if something reads them
/// before the first line is written. A library still takes a `Logger` as a
/// parameter and never calls this. The state is kept in one value: the hub,
/// and the sinks behind it that hold something worth flushing.
priv struct State {
  hub : @moonlog.Hub
  files : Array[@file.File]
  lokis : Array[@loki.Loki]
  mails : Array[@mail.Mail]
}

///|
/// The hub this process writes to, once something has asked for it.
let state : @ref.Ref[State?] = @ref.Ref(None)

///|
/// The wall clock, in nanoseconds, which the root package refuses to read and
/// an application cannot do without.
fn now() -> Int64 {
  @env.now().reinterpret_as_int64() * 1_000_000L
}

///|
/// The profile `SERLOG_COMPAT` names, or the default one.
fn profile_from_env() -> @moonlog.Profile {
  match @env.get_env_var("SERLOG_COMPAT") {
    Some(name) =>
      if name == "" {
        @moonlog.Profile::Serlog
      } else {
        @moonlog.Profile::parse(name) catch {
          _ => @moonlog.Profile::Serlog
        }
      }
    None => @moonlog.Profile::Serlog
  }
}

///|
/// The filter this deployment asks for: `SERLOG_FILTER`, or else the variable
/// the profile itself would read, or else nothing at all.
fn filter_from_env(profile : @moonlog.Profile) -> String {
  match @env.get_env_var("SERLOG_FILTER") {
    Some(spec) => if spec != "" { spec } else { profile_filter(profile) }
    None => profile_filter(profile)
  }
}

///|
fn profile_filter(profile : @moonlog.Profile) -> String {
  for name in profile.env() {
    match @env.get_env_var(name) {
      Some(spec) => if spec != "" { return spec }
      None => ()
    }
  }
  ""
}

///|
/// The layout `SERLOG_FORMAT` asks for, or the profile's own pattern.
fn layout_from_env(
  profile : @moonlog.Profile,
) -> &@moonlog.Layout raise @config.Refused {
  let spec = match @env.get_env_var("SERLOG_FORMAT") {
    Some(spec) => spec
    None => ""
  }
  if spec == "" {
    let pattern : &@moonlog.Layout = @moonlog.Pattern::parse(profile.pattern()) catch {
      _ =>
        raise @config.Refused::Refused(
          at="SERLOG_FORMAT",
          got="nothing",
          want="a format",
        )
    }
    pattern
  } else {
    layout_of(spec)
  }
}

///|
/// Builds the hub for this process.
///
/// It is called `start` rather than `init` because MoonBit keeps `init` for the
/// module initialiser, which runs before the program has a chance to say
/// anything.
///
/// The document, when one is given, says everything: which profile, which
/// filter, which slots and what kind of sink each one is. Without one, a
/// console is set up at the profile's own stream and level, laid out by
/// `SERLOG_FORMAT` if it is set — which is what `init()` with nothing means,
/// and what an application gets the first time it asks for a logger.
///
/// `filter` and `profile` override the document, and `colour` overrides the
/// console's own decision, because a program may know better than a file.
pub fn start(
  config? : @config.Config,
  filter? : String,
  profile? : @moonlog.Profile,
  colour? : Bool,
) -> Unit raise @config.Refused {
  let chosen = match profile {
    Some(profile) => profile
    None =>
      match config {
        Some(config) => config.profile()
        None => profile_from_env()
      }
  }
  let spec = match filter {
    Some(spec) => spec
    None =>
      match config {
        Some(config) =>
          if config.filter() != "" {
            config.filter()
          } else {
            filter_from_env(chosen)
          }
        None => filter_from_env(chosen)
      }
  }
  let chosen_filter = @moonlog.Filter::parse(spec) catch {
    error =>
      raise @config.Refused::Refused(
        at="filter",
        got="`" + spec + "`",
        want="a filter: " + error.to_text(),
      )
  }
  let hub = @moonlog.Hub::new(
    identity=@moonlog.Identity::of(app=app_name()),
    profile=chosen,
    clock=now,
    filter=chosen_filter,
  )
  let files : Array[@file.File] = []
  let lokis : Array[@loki.Loki] = []
  let mails : Array[@mail.Mail] = []
  let alarm = match config {
    Some(config) =>
      match config.alarm() {
        Some(alarm) => Some(alarm.tiers())
        None => None
      }
    None => None
  }
  let slots = match config {
    Some(config) => config.slots()
    None => []
  }
  if slots.length() == 0 {
    let stream = chosen.stream()
    let console = match colour {
      Some(colour) => @stdio.Console::new(stream~, colour~)
      None => @stdio.Console::new(stream~)
    }
    let mut slot = console.slot(name="console")
    slot = slot.layout(layout_from_env(chosen))
    match alarm {
      Some(tiers) => slot = slot.on_fail(@moonlog.OnFail::Alarm(tiers))
      None => ()
    }
    add(hub, slot)
  } else {
    for described in slots {
      let built = built_of(described)
      match built.file {
        Some(file) => files.push(file)
        None => ()
      }
      match built.loki {
        Some(loki) => lokis.push(loki)
        None => ()
      }
      match built.mail {
        Some(mail) => mails.push(mail)
        None => ()
      }
      let mut slot = slot_of(built, described)
      match alarm {
        Some(tiers) => slot = slot.on_fail(@moonlog.OnFail::Alarm(tiers))
        None => ()
      }
      add(hub, slot)
    }
  }
  state.val = Some({ hub, files, lokis, mails, })
}

///|
/// Registers a slot, turning the hub's refusal into one a document reader can
/// act on: the document is where the name came from.
fn add(hub : @moonlog.Hub, slot : @moonlog.Slot) -> Unit raise @config.Refused {
  try {
    let _ = hub.add(slot)
  } catch {
    error =>
      raise @config.Refused::Refused(
        at="slots",
        got=error.to_text(),
        want="a name no other slot has",
      )
  }
}

///|
/// The name this program goes by, for the `app` field: the environment's
/// `MOONLOG_APP`, else the executable's own name is not available here, so a
/// plain `app`.
fn app_name() -> String {
  match @env.get_env_var("MOONLOG_APP") {
    Some(name) => if name == "" { "app" } else { name }
    None => "app"
  }
}

///|
/// The hub, starting a zero-config one first if nothing has asked yet.
fn ensure() -> @moonlog.Hub {
  match state.val {
    Some(state) => state.hub
    None => {
      start() catch {
        _ => ()
      }
      match state.val {
        Some(state) => state.hub
        None => @moonlog.Hub::new(clock=now)
      }
    }
  }
}

///|
/// The process hub, for an application that wants to add a slot of its own.
pub fn hub() -> @moonlog.Hub {
  ensure()
}

///|
/// A logger writing to the process hub. The first call sets the hub up if
/// nothing has.
pub fn logger(target : String) -> @moonlog.Logger {
  ensure().logger(target)
}

///|
/// Replaces the filter in force, for a `SIGUSR1` handler or a reload.
pub fn set_filter(spec : String) -> Unit raise @moonlog.Refused {
  ensure().set_filter(@moonlog.Filter::parse(spec))
}

///|
/// Lets `level` and above through, for every target.
pub fn set_level(level : @moonlog.Level) -> Unit {
  ensure().set_level(level)
}

///|
/// Writes what every queue holds and every file buffers, which is what a
/// program does before it exits.
pub fn flush() -> Unit {
  match state.val {
    Some(state) => {
      state.hub.flush()
      for file in state.files {
        match file.flush() {
          Ok(_) => ()
          Err(_) => ()
        }
      }
    }
    None => ()
  }
}

///|
/// Pushes one round of network traffic: every Loki sink ships what it holds,
/// and every mail sink sends a batch that is due.
///
/// There is no background task in this library, so this is the loop an
/// application runs on its own runtime — `while true { drain(); sleep }` — and
/// the retries a busy Loki asks for are that loop's to make.
pub async fn drain() -> Unit {
  match state.val {
    Some(state) => {
      for loki in state.lokis {
        ignore(loki.push())
      }
      for mail in state.mails {
        if mail.due(now()) {
          ignore(mail.send())
        }
      }
    }
    None => ()
  }
}

///|
/// Flushes, closes what can be closed, and forgets the hub. A program that
/// calls this and then asks for a logger gets a fresh zero-config one.
pub fn shutdown() -> Unit {
  flush()
  match state.val {
    Some(state) =>
      for file in state.files {
        file.close()
      }
    None => ()
  }
  state.val = None
}

///|
/// How every slot stands, which is what a health endpoint reports.
pub fn status() -> Array[@moonlog.Status] {
  ensure().status()
}
