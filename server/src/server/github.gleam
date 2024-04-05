import gleam/httpc
import gleam/http/request
import gleam/http/response
import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/list
import gleam/io
import gleam/result
import server/error
import server/npm
import server/verl
import gleam/bool
import gleam/string
import gleam/int
import gleam/option.{type Option, Some}
import dot_env/env

// what we get back from githubs api
pub type GithubRelease {
  GithubRelease(
    tag_name: String,
    name: Option(String),
    created_at: String,
    html_url: String,
    prerelease: Bool,
    draft: Bool,
    dependency_name: Option(String),
  )
}

// what we construct from github to pass around and use
pub type Release {
  Release(
    tag_name: String,
    dependency_name: String,
    name: Option(String),
    url: String,
    created_at: String,
    version: verl.Version,
    display_version: String,
  )
}

// main fn of module: given a npm package, fetch ALL releases for it
// from githubs api
pub fn get_releases_for_repository(
  repository: npm.RepositoryMeta,
) -> Result(List(Release), error.Error) {
  let current_version = verl.parse(repository.version)

  case current_version {
    Ok(version) -> {
      let releases =
        paginate_github_releases(
          repository: repository,
          stop_predicate: fn(release) {
            version_from_tag_name(release.tag_name)
            |> verl.parse
            |> result.map(fn(release_version) {
              verl.lt(release_version, version)
            })
            |> result.unwrap(False)
          },
        )

      releases
      |> set_dependency_name(repository)
      |> result.map(fn(releases) { filter_github_releases(releases, version) })
      |> result.map(from_github_releases)
    }

    Error(_) ->
      Error(error.invalid_semver_version_error(
        dependency_name: repository.dependency_name,
        version: repository.version,
      ))
  }
}

fn paginate_github_releases(
  repository repo: npm.RepositoryMeta,
  stop_predicate stop_pred: fn(GithubRelease) -> Bool,
) -> Result(List(GithubRelease), error.Error) {
  let url = craft_github_request_url(repo)
  let initial_response = fetch_releases_from_github(url, repo)

  case initial_response {
    Ok(response) -> {
      let should_stop = list.any(response.body, stop_pred)

      case should_stop {
        True -> {
          io.debug(
            #(
              "Stopped paginating older version encountered: dependency, version",
              [repo.dependency_name, repo.version],
            ),
          )

          Ok(response.body)
        }
        False -> {
          let next_page_url = get_next_page_url(response)
          paginate_helper(repo, response.body, stop_pred, next_page_url)
        }
      }
    }
    Error(err) -> Error(err)
  }
}

fn paginate_helper(
  repository: npm.RepositoryMeta,
  releases: List(GithubRelease),
  stop_predicate: fn(GithubRelease) -> Bool,
  next_page_url: Result(String, Nil),
) -> Result(List(GithubRelease), error.Error) {
  let should_stop = list.any(releases, stop_predicate)

  case should_stop {
    True -> {
      io.debug(
        #("Stopped paginating older version encountered: dependency, version", [
          repository.dependency_name,
          repository.version,
        ]),
      )
      Ok(releases)
    }
    False -> {
      case next_page_url {
        Error(_) -> Ok(releases)
        Ok(url) -> {
          let next_response = fetch_releases_from_github(url, repository)

          case next_response {
            Ok(res) -> {
              let next_page = get_next_page_url(res)
              let combined = list.append(releases, res.body)

              paginate_helper(repository, combined, stop_predicate, next_page)
            }
            Error(err) -> Error(err)
          }
        }
      }
    }
  }
}

fn fetch_releases_from_github(
  url: String,
  repository: npm.RepositoryMeta,
) -> Result(response.Response(List(GithubRelease)), error.Error) {
  let assert Ok(token) = env.get("GITHUB_TOKEN")

  let assert Ok(request_) = request.to(url)
  let assert Ok(response_) =
    request.set_header(request_, "User-Agent", "gleam-whats-changed-app")
    |> request.set_header("Content-Type", "application/json")
    |> request.set_header("Authorization", "Bearer " <> token)
    |> httpc.send()

  let decoded =
    response.try_map(response_, json.decode(_, decode_github_releases()))

  case decoded {
    Ok(resp) -> {
      let assert Ok(rate_limit_remaining) =
        response.get_header(resp, "x-ratelimit-remaining")

      case rate_limit_remaining {
        "0" ->
          Error(error.http_rate_limit_exceeded(
            dependency_name: repository.dependency_name,
          ))
        _ -> {
          case resp.status {
            200 -> Ok(resp)
            404 ->
              Error(error.http_not_found_error(
                dependency_name: repository.dependency_name,
              ))

            code ->
              Error(error.http_unexpected_error(
                status_code: code,
                dependency_name: repository.dependency_name,
              ))
          }
        }
      }
    }
    Error(err) -> Error(error.JsonDecodeError(err))
  }
}

fn filter_github_releases(
  github_releases: List(GithubRelease),
  current_version: verl.Version,
) -> List(GithubRelease) {
  list.filter(github_releases, fn(github_release) {
    let version =
      github_release.tag_name
      |> version_from_tag_name()
      |> verl.parse()

    case version {
      Ok(valid_version) -> {
        bool.negate(github_release.draft)
        && bool.negate(github_release.prerelease)
        && verl.gt(valid_version, current_version)
      }
      Error(_) -> False
    }
  })
}

fn from_github_releases(github_releases: List(GithubRelease)) -> List(Release) {
  list.map(github_releases, fn(release) {
    let display_version = version_from_tag_name(release.tag_name)
    let assert Ok(version) = verl.parse(display_version)

    Release(
      tag_name: release.tag_name,
      dependency_name: option.unwrap(release.dependency_name, ""),
      name: release.name,
      created_at: release.created_at,
      url: release.html_url,
      version: version,
      display_version: display_version,
    )
  })
}

fn set_dependency_name(
  github_releases: Result(List(GithubRelease), error.Error),
  repository: npm.RepositoryMeta,
) -> Result(List(GithubRelease), error.Error) {
  result.map(github_releases, fn(releases) {
    list.map(releases, fn(release) {
      GithubRelease(
        ..release,
        dependency_name: Some(repository.dependency_name),
      )
    })
  })
}

// ---- utilities ----

fn bool_from_result(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn craft_github_request_url(repository: npm.RepositoryMeta) -> String {
  "https://api.github.com/repos/"
  <> repository.github_owner
  <> "/"
  <> repository.github_name
  <> "/releases"
  <> "?per_page=100"
  <> "&page=1"
}

// e.g. v1.4.3 -> 1.4.3, plugin-legacy@5.3.1 -> 5.3.1
fn version_from_tag_name(tag_name: String) {
  string.split(tag_name, "")
  |> list.filter(fn(char) { bool_from_result(int.parse(char)) })
  |> string.join(".")
}

// see server_test
fn get_next_page_url(res: response.Response(a)) -> Result(String, Nil) {
  let link_header = response.get_header(res, "link")
  result.try(link_header, url_from_link_header)
}

pub fn url_from_link_header(link_header: String) -> Result(String, Nil) {
  let split_header = string.split(link_header, ",")
  let next_segment =
    list.find(split_header, fn(str) { string.contains(str, "rel=\"next\"") })

  let raw_page_url =
    result.map(next_segment, fn(url) {
      string.split(url, ";")
      |> list.at(0)
      |> result.unwrap("")
      |> string.replace("<", "")
      |> string.replace(">", "")
      |> string.trim()
    })

  result.try(raw_page_url, fn(url) {
    case url {
      "" -> Error(Nil)
      str -> Ok(str)
    }
  })
}

fn decode_github_releases() -> fn(Dynamic) ->
  Result(List(GithubRelease), List(dynamic.DecodeError)) {
  let release_decoder =
    dynamic.decode7(
      GithubRelease,
      dynamic.field("tag_name", dynamic.string),
      dynamic.field("name", dynamic.optional(dynamic.string)),
      dynamic.field("created_at", dynamic.string),
      dynamic.field("html_url", dynamic.string),
      dynamic.field("prerelease", dynamic.bool),
      dynamic.field("draft", dynamic.bool),
      dynamic.optional_field("dependency_name", dynamic.string),
    )

  dynamic.list(release_decoder)
}
