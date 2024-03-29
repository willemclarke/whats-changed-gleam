import gleam/json

pub type Error {
  Http(HttpClientError)
  JsonDecodeError(json.DecodeError)
  Semvar(SemvarParseError)
  Releases(ReleasesError)
}

pub type SemvarParseError {
  InvlalidVersion(dependency_name: String, version: String)
}

pub type HttpClientError {
  NotFound(status: Int, dependency_name: String)
  UnexpectedError(status: Int, dependency_name: String)
  RateLimitExceeded(status: Int, dependency_name: String)
}

pub type ReleasesError {
  NoReleasesFound(dependency_name: String)
}

pub fn http_not_found_error(dependency_name name: String) -> Error {
  Http(NotFound(404, name))
}

pub fn http_unexpected_error(
  status_code code: Int,
  dependency_name name: String,
) -> Error {
  Http(UnexpectedError(code, name))
}

pub fn http_rate_limit_exceeded(dependency_name name: String) -> Error {
  Http(RateLimitExceeded(429, name))
}

pub fn invalid_semver_version_error(
  dependency_name name: String,
  version ver: String,
) -> Error {
  Semvar(InvlalidVersion(name, ver))
}

pub fn releases_not_found_error(dependency_name name: String) -> Error {
  Releases(NoReleasesFound(name))
}
