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

// what comes back from githubs releases api
pub type GithubRelease {
  GithubRelease(
    tag_name: String,
    name: String,
    // body: String,
    created_at: String,
    html_url: String,
    prerelease: Bool,
    draft: Bool,
  )
}

pub type GithubReleaseWithDependencyName {
  GithubReleaseWithDependencyName(
    tag_name: String,
    name: String,
    dependency_name: String,
    created_at: String,
    html_url: String,
    prerelease: Bool,
    draft: Bool,
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

pub fn handle_request(req: Request) -> wisp.Response {
  use request <- web.middleware(req)
  use <- wisp.require_method(req, Post)
  use json <- wisp.require_json(req)

  case wisp.path_segments(request) {
    ["dependencies"] -> dependencies(request, json)
    _ -> wisp.not_found()
  }
}

fn dependencies(_: Request, json: Dynamic) -> wisp.Response {
  let decoded_deps = common.decode_dependencies(json)

  case decoded_deps {
    Ok(deps) -> {
      let repositories =
        list.map(deps, npm.get_repository_meta_from_npm)
        |> result.values()

      let releases =
        list.map(repositories, get_releases_for_repository)
        |> result.values()
        |> list.flatten()
        |> io.debug()

      io.debug(list.length(of: releases))

      wisp.json_response(common.encode_dependencies(deps), 200)
    }
    Error(_) -> wisp.unprocessable_entity()
  }
}

pub fn get_releases_for_repository(
  repository: npm.RepositoryMeta,
) -> Result(List(Release), error.Error) {
  let current_version = verl.parse(repository.version)

  let github_releases =
    fetch_releases_from_github(repository)
    |> with_dependency_name(repository)
    |> result.map(filter_github_releases)
    |> result.map(from_github_releases)

  case current_version {
    Ok(version) -> {
      case github_releases {
        Ok(releases) -> Ok(get_newer_releases(releases, version))
        Error(_) ->
          Error(error.releases_not_found_error(
            dependency_name: repository.dependency_name,
          ))
      }
    }
    Error(_) ->
      Error(error.invalid_semver_version_error(
        dependency_name: repository.dependency_name,
        version: repository.version,
      ))
  }
}

// e.g. v1.4.3 -> 1.4.3, plugin-legacy@5.3.1 -> 5.3.1
pub fn version_from_tag_name(tag_name: String) {
  string.split(tag_name, "")
  |> list.filter(fn(char) { bool_from_result(int.parse(char)) })
  |> string.join(".")
  |> verl.parse()
}

pub fn get_newer_releases(
  releases: List(Release),
  current_version: verl.Version,
) -> List(Release) {
  list.filter(releases, fn(release) {
    verl.gt(release.version, current_version)
  })
}

pub fn filter_github_releases(
  github_releases: List(GithubReleaseWithDependencyName),
) -> List(GithubReleaseWithDependencyName) {
  list.filter(github_releases, fn(github_release) {
    let is_valid_version =
      bool_from_result(version_from_tag_name(github_release.tag_name))

    bool.negate(github_release.draft)
    && bool.negate(github_release.prerelease)
    && is_valid_version
  })
}

pub fn from_github_releases(
  github_releases: List(GithubReleaseWithDependencyName),
) -> List(Release) {
  list.map(github_releases, fn(release) {
    let assert Ok(version) = version_from_tag_name(release.tag_name)

    Release(
      tag_name: release.tag_name,
      dependency_name: release.dependency_name,
      name: release.name,
      created_at: release.created_at,
      url: release.html_url,
      version: version,
    )
  })
}

pub fn with_dependency_name(
  github_releases: Result(List(GithubRelease), error.Error),
  repository: npm.RepositoryMeta,
) -> Result(List(GithubReleaseWithDependencyName), error.Error) {
  result.map(github_releases, fn(releases) {
    list.map(releases, fn(release) {
      GithubReleaseWithDependencyName(
        tag_name: release.tag_name,
        name: release.name,
        dependency_name: repository.dependency_name,
        created_at: release.created_at,
        html_url: release.html_url,
        prerelease: release.prerelease,
        draft: release.draft,
      )
    })
  })
}

pub fn fetch_releases_from_github(
  repository: npm.RepositoryMeta,
) -> Result(List(GithubRelease), error.Error) {
  let path = craft_github_request_path(repository)

  let assert Ok(response_) =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("api.github.com")
    |> request.set_path(path)
    |> request.set_header("User-Agent", "gleam-whats-changed-app")
    |> request.set_header("Content-Type", "application/json")
    // todo: create a new github PAT before making repo public
    // and pull from env
    |> request.set_header(
      "Authorization",
      "Bearer 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",
    )
    |> httpc.send()

  // lift the type of response.body from String -> List(GithubRelease)
  let decoded =
    response.try_map(response_, json.decode(_, decode_github_releases()))

  // TODO: understand how to paginate via link header
  // let assert Ok(link_header) =
  //   response.get_header(response_, "link")
  //   |> io.debug()

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
            200 -> Ok(resp.body)
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

pub fn craft_github_request_path(repository: npm.RepositoryMeta) -> String {
  "/repos/"
  <> repository.github_owner
  <> "/"
  <> repository.github_name
  <> "/releases"
  <> "?per_page=100"
}

pub fn decode_github_releases() -> fn(Dynamic) ->
  Result(List(GithubRelease), List(dynamic.DecodeError)) {
  let release_decoder =
    dynamic.decode6(
      GithubRelease,
      dynamic.field("tag_name", dynamic.string),
      dynamic.field("name", dynamic.string),
      dynamic.field("created_at", dynamic.string),
      dynamic.field("html_url", dynamic.string),
      dynamic.field("prerelease", dynamic.bool),
      dynamic.field("draft", dynamic.bool),
    )

  dynamic.list(release_decoder)
}
