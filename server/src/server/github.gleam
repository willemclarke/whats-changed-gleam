import common
import dot_env/env
import gleam/dynamic.{type Dynamic}
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/regex
import gleam/result
import gleam/string
import gleam/string_builder.{type StringBuilder}
import kirala/bbmarkdown/html_renderer
import server/error
import server/npm
import server/verl

// what we get back from githubs api
pub type GithubRelease {
  GithubRelease(
    tag_name: String,
    name: Option(String),
    created_at: String,
    html_url: String,
    prerelease: Bool,
    draft: Bool,
    body: Option(String),
    dependency_name: Option(String),
  )
}

// main fn of module: given a npm package, fetch ALL releases for it
// from githubs api
pub fn get_releases_for_npm_package(
  package: npm.PackageMeta,
) -> Result(List(common.Release), error.Error) {
  let current_version = verl.parse(package.version)

  case current_version {
    Ok(version) -> {
      let releases =
        paginate_github_releases(package: package, stop_predicate: fn(release) {
          stop_predicate_fn(release, version)
        })

      releases
      |> set_dependency_name(package)
      |> result.map(fn(releases) { filter_github_releases(releases, version) })
      |> result.map(from_github_releases)
    }

    Error(_) ->
      Error(error.invalid_semver_version_error(
        dependency_name: package.dependency_name,
        version: package.version,
      ))
  }
}

// if we encounter a release.version that is < our current version (package.json)
// we want to tell the paginate function to stop
fn stop_predicate_fn(
  release: GithubRelease,
  current_version: verl.Version,
) -> Bool {
  let release_version = version_from_tag_name(release.tag_name)

  case release_version {
    Ok(release_version_) -> {
      release_version_
      |> verl.parse
      |> result.map(fn(version) { verl.lt(version, current_version) })
      |> result.unwrap(False)
    }
    Error(_) -> False
  }
}

fn paginate_github_releases(
  package pkg: npm.PackageMeta,
  stop_predicate stop_pred: fn(GithubRelease) -> Bool,
) -> Result(List(GithubRelease), error.Error) {
  let url = craft_github_request_url(pkg)
  let initial_response = fetch_releases_from_github(url, pkg)

  case initial_response {
    Ok(response) -> {
      case response.body {
        [] -> Ok(response.body)

        _ -> {
          let should_stop = list.any(response.body, stop_pred)

          case should_stop {
            True -> {
              io.debug(
                #(
                  "Stopped paginating older version encountered: dependency, version",
                  [pkg.dependency_name, pkg.version],
                ),
              )

              Ok(response.body)
            }
            False -> {
              let next_page_url = get_next_page_url(response)
              paginate_helper(pkg, response.body, stop_pred, next_page_url)
            }
          }
        }
      }
    }
    Error(err) -> Error(err)
  }
}

fn paginate_helper(
  repository: npm.PackageMeta,
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
  repository: npm.PackageMeta,
) -> Result(response.Response(List(GithubRelease)), error.Error) {
  let assert Ok(token) = env.get("GITHUB_TOKEN")

  let assert Ok(request_) = request.to(url)
  let assert Ok(response_) =
    request.set_header(request_, "User-Agent", "gleam-whats-changed-app")
    |> request.set_header("Content-Type", "application/json")
    |> request.set_header("Authorization", "Bearer " <> token)
    |> httpc.send()

  let assert Ok(rate_limit_remaining) =
    response.get_header(response_, "x-ratelimit-remaining")

  case rate_limit_remaining {
    "0" ->
      Error(error.http_rate_limit_exceeded(
        dependency_name: repository.dependency_name,
      ))

    _ -> {
      case response_.status {
        200 -> {
          response.try_map(response_, json.decode(_, decode_github_releases()))
          |> result.map_error(error.JsonDecodeError)
        }
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

fn filter_github_releases(
  github_releases: List(GithubRelease),
  current_version: verl.Version,
) -> List(GithubRelease) {
  github_releases
  |> list.filter(fn(github_release) {
    let to_version = version_from_tag_name(github_release.tag_name)
    case to_version {
      Ok(version) -> {
        version
        |> verl.parse()
        |> result.map(fn(release_version) {
          !github_release.draft
          && !github_release.prerelease
          && verl.gt(release_version, current_version)
        })
        |> result.unwrap(False)
      }
      Error(_) -> False
    }
  })
}

fn from_github_releases(
  github_releases: List(GithubRelease),
) -> List(common.Release) {
  list.map(github_releases, fn(release) {
    let assert Ok(version) = version_from_tag_name(release.tag_name)
    let html_body = html_renderer.convert(option.unwrap(release.body, ""))

    common.Release(
      tag_name: release.tag_name,
      dependency_name: option.unwrap(release.dependency_name, ""),
      name: release.name,
      created_at: release.created_at,
      url: release.html_url,
      version: version,
      body: option.Some(html_body),
    )
  })
}

fn set_dependency_name(
  github_releases: Result(List(GithubRelease), error.Error),
  repository: npm.PackageMeta,
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

fn craft_github_request_url(repository: npm.PackageMeta) -> String {
  "https://api.github.com/repos/"
  <> repository.github_owner
  <> "/"
  <> repository.github_name
  <> "/releases"
  <> "?per_page=30"
  <> "&page=1"
}

// see tests
pub fn version_from_tag_name(tag_name) -> Result(String, Nil) {
  let assert Ok(regexp) = regex.from_string("[0-9]+\\.[0-9]+\\.[0-9]+")
  let matches = regex.scan(regexp, tag_name)

  list.first(matches)
  |> result.map(fn(match) { match.content })
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

pub fn encode_releases(releases: List(common.Release)) -> StringBuilder {
  json.array(releases, fn(release) {
    json.object([
      #("tag_name", json.string(release.tag_name)),
      #("dependency_name", json.string(release.dependency_name)),
      #("name", json.nullable(release.name, json.string)),
      #("url", json.string(release.url)),
      #("version", json.string(release.version)),
      #("created_at", json.string(release.created_at)),
    ])
  })
  |> json.to_string_builder
}

fn decode_github_releases() -> fn(Dynamic) ->
  Result(List(GithubRelease), List(dynamic.DecodeError)) {
  let release_decoder =
    dynamic.decode8(
      GithubRelease,
      dynamic.field("tag_name", dynamic.string),
      dynamic.field("name", dynamic.optional(dynamic.string)),
      dynamic.field("created_at", dynamic.string),
      dynamic.field("html_url", dynamic.string),
      dynamic.field("prerelease", dynamic.bool),
      dynamic.field("draft", dynamic.bool),
      dynamic.field("body", dynamic.optional(dynamic.string)),
      dynamic.optional_field("dependency_name", dynamic.string),
    )

  dynamic.list(release_decoder)
}
