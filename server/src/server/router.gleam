import wisp.{type Request}
import server/web
import gleam/http.{Get, Post}
import gleam/httpc
import gleam/http/request
import gleam/http/response
import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/list
import gleam/io
import gleam/result
import server/error
import common
import server/npm
import server/verl
import gleam/bool
import gleam/string
import gleam/int
import gleam/option.{type Option, Some}
import dot_env/env

// dependency_name doesn't exist from github, so we optionally decode
// and se the field later
pub type GithubRelease {
  GithubRelease(
    tag_name: String,
    name: String,
    created_at: String,
    html_url: String,
    prerelease: Bool,
    draft: Bool,
    dependency_name: Option(String),
  )
}

pub type Release {
  Release(
    tag_name: String,
    dependency_name: String,
    name: String,
    url: String,
    created_at: String,
    version: verl.Version,
  )
}

fn bool_from_result(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn handle_request(
  req: Request,
  make_context: fn() -> web.Context,
) -> wisp.Response {
  let context = make_context()
  use request <- web.middleware(req)
  use <- wisp.require_method(req, Post)
  use json <- wisp.require_json(req)

  case wisp.path_segments(request) {
    ["dependencies"] -> dependencies(request, json, context)
    _ -> wisp.not_found()
  }
}

fn dependencies(_: Request, json: Dynamic, _: web.Context) -> wisp.Response {
  let decoded_deps = common.decode_dependencies(json)

  case decoded_deps {
    Ok(deps) -> {
      let repositories =
        list.map(deps, npm.get_repository_meta_from_npm)
        |> result.values()

      let _ = list.map(repositories, get_releases_for_repository)

      wisp.json_response(common.encode_dependencies(deps), 200)
    }
    Error(_) -> wisp.unprocessable_entity()
  }
}

pub fn get_releases_for_repository(
  repository: npm.RepositoryMeta,
) -> Result(List(Release), error.Error) {
  let current_version = verl.parse(repository.version)

  case current_version {
    Ok(version) -> {
      paginate_github_releases(
        repository: repository,
        stop_predicate: fn(release) {
          version_from_tag_name(release.tag_name)
          |> result.map(fn(release_version) {
            verl.lt(release_version, version)
          })
          |> result.unwrap(False)
        },
      )
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

// e.g. v1.4.3 -> 1.4.3, plugin-legacy@5.3.1 -> 5.3.1
// then parsed into semvar
pub fn version_from_tag_name(tag_name: String) {
  string.split(tag_name, "")
  |> list.filter(fn(char) { bool_from_result(int.parse(char)) })
  |> string.join(".")
  |> verl.parse()
}

pub fn filter_github_releases(
  github_releases: List(GithubRelease),
  current_version: verl.Version,
) -> List(GithubRelease) {
  list.filter(github_releases, fn(github_release) {
    case version_from_tag_name(github_release.tag_name) {
      Ok(valid_version) -> {
        bool.negate(github_release.draft)
        && bool.negate(github_release.prerelease)
        && verl.gt(valid_version, current_version)
      }
      Error(_) -> False
    }
  })
}

pub fn from_github_releases(
  github_releases: List(GithubRelease),
) -> List(Release) {
  list.map(github_releases, fn(release) {
    let assert Ok(version) = version_from_tag_name(release.tag_name)

    Release(
      tag_name: release.tag_name,
      dependency_name: option.unwrap(release.dependency_name, ""),
      name: release.name,
      created_at: release.created_at,
      url: release.html_url,
      version: version,
    )
  })
}

pub fn set_dependency_name(
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

pub fn paginate_github_releases(
  repository repo: npm.RepositoryMeta,
  stop_predicate stop_pred: fn(GithubRelease) -> Bool,
) -> Result(List(GithubRelease), error.Error) {
  let url = craft_github_request_url(repo)
  let initial_response = fetch_releases_from_github(url, repo)

  case initial_response {
    Ok(response) -> {
      let should_stop = list.any(response.body, stop_pred)

      case should_stop {
        True -> Ok(response.body)
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

// "<https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"next\", <https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\""
// pull the url out from the rel="next" block
pub fn get_next_page_url(res: response.Response(a)) -> Result(String, Nil) {
  let link_header = response.get_header(res, "link")

  case link_header {
    Error(err) -> Error(err)
    Ok(header) -> {
      let split_header = string.split(header, ",")
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
  }
}

pub fn fetch_releases_from_github(
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

pub fn craft_github_request_url(repository: npm.RepositoryMeta) -> String {
  "https://api.github.com/repos/"
  <> repository.github_owner
  <> "/"
  <> repository.github_name
  <> "/releases"
  <> "?per_page=100"
  <> "&page=1"
}

pub fn decode_github_releases() -> fn(Dynamic) ->
  Result(List(GithubRelease), List(dynamic.DecodeError)) {
  let release_decoder =
    dynamic.decode7(
      GithubRelease,
      dynamic.field("tag_name", dynamic.string),
      dynamic.field("name", dynamic.string),
      dynamic.field("created_at", dynamic.string),
      dynamic.field("html_url", dynamic.string),
      dynamic.field("prerelease", dynamic.bool),
      dynamic.field("draft", dynamic.bool),
      dynamic.optional_field("dependency_name", dynamic.string),
    )

  dynamic.list(release_decoder)
}
