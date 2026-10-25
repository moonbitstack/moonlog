// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How a record is shown: whose vocabulary the level is written in, whether a
/// terminal takes colour, and who is writing.
pub(all) struct Scene {
  profile : Profile
  colour : Bool
  identity : Identity
}

///|
/// A plain scene: no colour, the default vocabulary, an identity that names
/// nobody.
pub fn Scene::new(
  identity~ : Identity = Identity::new(),
  profile~ : Profile = Profile::Serlog,
  colour~ : Bool = false,
) -> Scene {
  { profile, colour, identity, }
}

///|
/// The same scene at another profile.
pub fn Scene::at(self : Scene, profile : Profile) -> Scene {
  { profile, colour: self.colour, identity: self.identity, }
}

///|
/// The same scene with colour turned on or off.
pub fn Scene::coloured(self : Scene, colour : Bool) -> Scene {
  { profile: self.profile, colour, identity: self.identity, }
}
