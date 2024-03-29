import gleam/json

pub type Error {
  HttpError(HttpClientError)
  JsonDecodeError(json.DecodeError)
}

pub type HttpClientError {
  NotFound(status: Int, dependency_name: String)
  UnexpectedError(status: Int, dependency_name: String)
  RateLimitExceeded(status: Int, dependency_name: String)
}

pub fn http_not_found_error(dependency_name name: String) -> Error {
  HttpError(NotFound(404, name))
}

pub fn http_unexpected_error(
  status_code code: Int,
  dependency_name name: String,
) -> Error {
  HttpError(UnexpectedError(code, name))
}

pub fn http_rate_limit_exceeded(dependency_name name: String) -> Error {
  HttpError(RateLimitExceeded(429, name))
}
