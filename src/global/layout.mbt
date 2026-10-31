// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The layout a `SERLOG_FORMAT` value names.
///
/// `logfmt`, `pretty`, `json`, `json:<schema>`, `pattern:<spec>`, a pattern
/// written out in full, or one of the seven preset names. Nothing at all is the
/// profile's own pattern, which is what a deployment that says nothing gets.
pub fn layout_of(spec : String) -> &@moonlog.Layout raise @config.Refused {
  let at = "SERLOG_FORMAT"
  if spec == "" {
    raise @config.Refused::Refused(at~, got="nothing", want="a format")
  }
  if spec == "logfmt" {
    return @moonlog.Logfmt::new()
  }
  if spec == "pretty" {
    return @moonlog.Pretty::new()
  }
  if spec == "json" {
    return @moonlog.JsonLine::new(@moonlog.Schema::Serlog)
  }
  if spec.has_prefix("json:") {
    let name = spec[5:].to_owned()
    let schema = @moonlog.Schema::parse(name) catch {
      _ =>
        raise @config.Refused::Refused(
          at~,
          got="`" + name + "`",
          want="one of the ten schemas",
        )
    }
    return @moonlog.JsonLine::new(schema)
  }
  if spec.has_prefix("pattern:") {
    let source = spec[8:].to_owned()
    return @moonlog.Pattern::parse(source) catch {
      error =>
        raise @config.Refused::Refused(
          at~,
          got="`" + source + "`",
          want="a pattern: " + error.to_text(),
        )
    }
  }
  if spec.contains("{") {
    // A pattern written out, the way a slot in a document carries one.
    return @moonlog.Pattern::parse(spec) catch {
      error =>
        raise @config.Refused::Refused(
          at~,
          got="`" + spec + "`",
          want="a pattern: " + error.to_text(),
        )
    }
  }
  // A preset name, written as the profile that carries it.
  let profile = @moonlog.Profile::parse(spec) catch {
    _ =>
      raise @config.Refused::Refused(
        at~,
        got="`" + spec + "`",
        want="logfmt, pretty, json, json:<schema>, pattern:<spec>, or a preset name",
      )
  }
  return @moonlog.Pattern::parse(profile.pattern()) catch {
    error =>
      raise @config.Refused::Refused(
        at~,
        got="`" + profile.name().to_owned() + "`",
        want="a preset whose pattern parses: " + error.to_text(),
      )
  }
}
