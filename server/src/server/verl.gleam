// module to FFI with https://hexdocs.pm/verl/readme.html
// so I can work with semvar functions

pub type Version

pub type InvalidVersion

@external(erlang, "verl", "parse")
pub fn parse(version: String) -> Result(Version, InvalidVersion)

@external(erlang, "verl", "eq")
pub fn eq(version1: Version, version2: Version) -> Bool

@external(erlang, "verl", "gt")
pub fn gt(version1: Version, version2: Version) -> Bool

@external(erlang, "verl", "lt")
pub fn lt(version1: Version, version2: Version) -> Bool
