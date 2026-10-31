// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink as the document described it, with the handle kept alongside when it
/// is one that holds something `global` has to flush.
priv struct Built {
  sink : &@moonlog.Sink
  file : @file.File?
  loki : @loki.Loki?
  mail : @mail.Mail?
}

///|
fn Built::of_console(console : @stdio.Console) -> Built {
  { sink: console, file: None, loki: None, mail: None, }
}

///|
fn Built::of_file(file : @file.File) -> Built {
  { sink: file, file: Some(file), loki: None, mail: None, }
}

///|
fn Built::of_loki(loki : @loki.Loki) -> Built {
  { sink: loki, file: None, loki: Some(loki), mail: None, }
}

///|
fn Built::of_mail(mail : @mail.Mail) -> Built {
  { sink: mail, file: None, loki: None, mail: Some(mail), }
}

///|
fn Built::of_memory(memory : @moonlog.Memory) -> Built {
  { sink: memory, file: None, loki: None, mail: None, }
}

///|
fn Built::of_discard(discard : @moonlog.Discard) -> Built {
  { sink: discard, file: None, loki: None, mail: None, }
}

///|
/// What to do with a setting that has to be there.
fn required(slot : @config.Slot, key : String) -> String raise @config.Refused {
  match slot.text(key) {
    Some(text) => text
    None =>
      raise @config.Refused::Refused(
        at="slots." + slot.name + "." + key,
        got="nothing",
        want="a string",
      )
  }
}

///|
/// A refusal that names the key it is about.
fn refused(at : String, got : String, want : String) -> @config.Refused {
  @config.Refused::Refused(at~, got~, want~)
}

///|
/// The sink one slot of a document asks for.
fn built_of(slot : @config.Slot) -> Built raise @config.Refused {
  let at = "slots." + slot.name
  match slot.kind {
    "stdio" => {
      let stream = match slot.text("stream") {
        Some(name) =>
          @moonlog.Stream::parse(name) catch {
            _ =>
              raise refused(
                at + ".stream",
                "`" + name + "`",
                "stdout, stderr or auto",
              )
          }
        None => @moonlog.Stream::Auto
      }
      let console = match slot.colour {
        Some(colour) => @stdio.Console::new(stream~, colour~)
        None => @stdio.Console::new(stream~)
      }
      Built::of_console(console)
    }
    "file" => Built::of_file(file_of(slot))
    "loki" => Built::of_loki(loki_of(slot))
    "mail" => Built::of_mail(mail_of(slot, at))
    "memory" =>
      Built::of_memory(
        @moonlog.Memory::new(
          size=match slot.count("size") {
            Some(size) => size
            None => 0
          },
        ),
      )
    _ => Built::of_discard(@moonlog.Discard::new())
  }
}

///|
/// The file sink a slot describes.
fn file_of(slot : @config.Slot) -> @file.File raise @config.Refused {
  let path = required(slot, "path")
  @file.File::new(
    path~,
    append=match slot.flag("append") {
      Some(append) => append
      None => true
    },
    perms=match slot.count("perms") {
      Some(perms) => perms
      None => 0o644
    },
    mkdir=match slot.flag("mkdir") {
      Some(mkdir) => mkdir
      None => false
    },
    rotation=@file.Rotation::new(
      size=match slot.size("max_size") {
        Some(size) => size
        None => 0L
      },
      every=match slot.span("every") {
        Some(span) => span
        None => 0L
      },
    ),
    limits=@file.Limits::new(
      keep=match slot.count("keep") {
        Some(keep) => keep
        None => 0
      },
      max_age=match slot.span("max_age") {
        Some(age) => age
        None => 0L
      },
      max_total=match slot.size("max_total") {
        Some(total) => total
        None => 0L
      },
    ),
    compress=match slot.flag("compress") {
      Some(compress) => compress
      None => false
    },
    buffer=match slot.count("buffer") {
      Some(buffer) => buffer
      None => 0
    },
  )
}

///|
/// The Loki sink a slot describes.
fn loki_of(slot : @config.Slot) -> @loki.Loki raise @config.Refused {
  let url = required(slot, "url")
  let labels = match slot.pairs("labels") {
    Some(labels) => labels
    None => []
  }
  let limits = @loki.Limits::new(
    capacity=match slot.count("capacity") {
      Some(capacity) => capacity
      None => 8_192
    },
    batch=match slot.count("batch") {
      Some(batch) => batch
      None => 512
    },
    timeout=match slot.span("timeout") {
      Some(span) => (span / 1_000_000_000L).to_int()
      None => 10
    },
  )
  match (slot.text("tenant"), slot.text("username"), slot.text("password")) {
    (Some(tenant), Some(user), Some(password)) =>
      @loki.Loki::new(url~, labels~, tenant~, auth=(user, password), limits~)
    (Some(tenant), _, _) => @loki.Loki::new(url~, labels~, tenant~, limits~)
    (None, Some(user), Some(password)) =>
      @loki.Loki::new(url~, labels~, auth=(user, password), limits~)
    (None, _, _) => @loki.Loki::new(url~, labels~, limits~)
  }
}

///|
/// The mail sink a slot describes.
fn mail_of(
  slot : @config.Slot,
  at : String,
) -> @mail.Mail raise @config.Refused {
  let host = required(slot, "host")
  let from = required(slot, "from")
  let to = match slot.texts("to") {
    Some(to) => to
    None => raise refused(at + ".to", "nothing", "a list of addresses")
  }
  let level = match slot.text("level") {
    Some(name) =>
      @moonlog.Level::parse(name) catch {
        _ => raise refused(at + ".level", "`" + name + "`", "a level")
      }
    None => @moonlog.error
  }
  let window = match slot.span("window") {
    Some(span) => span
    None => @mail.window_default
  }
  let at_most = match slot.count("at_most") {
    Some(count) => count
    None => @mail.at_most_default
  }
  let auth = match (slot.text("username"), slot.text("password")) {
    (Some(user), Some(password)) => Some((user, password))
    _ => None
  }
  match (slot.count("port"), auth) {
    (Some(port), Some((user, password))) =>
      @mail.Mail::new(
        host~,
        from~,
        to~,
        port~,
        auth=(user, password),
        level~,
        window~,
        at_most~,
      )
    (Some(port), None) =>
      @mail.Mail::new(host~, from~, to~, port~, level~, window~, at_most~)
    (None, Some((user, password))) =>
      @mail.Mail::new(
        host~,
        from~,
        to~,
        auth=(user, password),
        level~,
        window~,
        at_most~,
      )
    (None, None) =>
      @mail.Mail::new(host~, from~, to~, level~, window~, at_most~)
  }
}

///|
/// The slot the document describes, around the sink it asked for.
fn slot_of(
  built : Built,
  described : @config.Slot,
) -> @moonlog.Slot raise @config.Refused {
  let at = "slots." + described.name
  let mut slot = @moonlog.Slot::new(built.sink, name=described.name).kind(
    described.kind,
  )
  match described.filter {
    Some(spec) =>
      slot = slot.filter(
        @moonlog.Filter::parse(spec) catch {
          error =>
            raise refused(
              at + ".filter",
              "`" + spec + "`",
              "a filter: " + error.to_text(),
            )
        },
      )
    None => ()
  }
  match described.layout {
    Some(spec) => slot = slot.layout(layout_of(spec))
    None => ()
  }
  match described.colour {
    Some(colour) => slot = slot.coloured(colour)
    None => ()
  }
  match described.queue {
    Some(queue) =>
      slot = slot.queue(
        @moonlog.Queue::new(size=queue.size)
        .batch(queue.batch)
        .wait(queue.wait)
        .full(queue.full),
      )
    None => ()
  }
  match described.retries {
    Some(retries) => slot = slot.retries(retries)
    None => ()
  }
  match described.probe {
    Some(probe) => slot = slot.probe(probe)
    None => ()
  }
  slot
}
