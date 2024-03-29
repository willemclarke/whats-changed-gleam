// module to FFI with https://hexdocs.pm/verl/readme.html
// so I can work with semvar functions

pub type Version

pub type InvalidVersion

@external(erlang, "verl", "parse")
pub fn parse(version: String) -> Result(Version, InvalidVersion)

@external(erlang, "verl", "eq")
pub fn eq(version: Version) -> Result(Bool, InvalidVersion)

@external(erlang, "verl", "gt")
pub fn gt(version: Version) -> Result(Bool, InvalidVersion)

@external(erlang, "verl", "gte")
pub fn gte(version: Version) -> Result(Bool, InvalidVersion)
