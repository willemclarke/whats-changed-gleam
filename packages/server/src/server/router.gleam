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
    dependency_version: String,
    created_at: String,
    html_url: String,
    prerelease: Bool,
    draft: Bool,
  )
}

pub type Release {
  Release(
    tag_name: String,
    name: String,
    version: verl.Version,
    url: String,
    // body: String,
    created_at: String,
    dependency_name: String,
  )
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
        |> filter_github_releases()
        |> from_github_releases()
        |> io.debug()

      io.debug(list.length(of: releases))
      wisp.json_response(common.encode_dependencies(deps), 200)
    }
    Error(_) -> wisp.unprocessable_entity()
  }
}

pub fn get_releases_for_repository(
  repository: npm.RepositoryMeta,
) -> Result(List(GithubReleaseWithDependencyName), error.Error) {
  let github_releases = fetch_releases_from_github(repository)
  let with_dep_name = with_dependency_name(repository, github_releases)
  // todo: implement filtering of releases
}

fn bool_from_result(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn filter_github_releases(
  github_releases: List(GithubReleaseWithDependencyName),
) -> List(GithubReleaseWithDependencyName) {
  list.filter(github_releases, fn(release) {
    let is_valid_version =
      bool_from_result(verl.parse(release.dependency_version))

    bool.negate(release.draft)
    && bool.negate(release.prerelease)
    && is_valid_version
  })
}

pub fn get_newer_releases(
  releases: List(GithubRelease),
  current_version: verl.Version,
) -> List(GithubRelease) {
  todo
}

pub fn from_github_releases(
  github_releases: List(GithubReleaseWithDependencyName),
) -> List(Release) {
  list.map(github_releases, fn(release) {
    let assert Ok(version) = verl.parse(release.dependency_version)

    Release(
      tag_name: release.tag_name,
      name: release.name,
      version: version,
      created_at: release.created_at,
      url: release.html_url,
      dependency_name: release.dependency_name,
    )
  })
}

pub fn with_dependency_name(
  repository: npm.RepositoryMeta,
  github_releases: Result(List(GithubRelease), error.Error),
) -> Result(List(GithubReleaseWithDependencyName), error.Error) {
  result.map(github_releases, fn(releases) {
    list.map(releases, fn(release) {
      GithubReleaseWithDependencyName(
        tag_name: release.tag_name,
        name: release.name,
        dependency_name: repository.dependency_name,
        dependency_version: repository.version,
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
    |> request.set_header(
      "Authorization",
      "Bearer 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",
    )
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
          json.decode(response_.body, decode_releases())
          |> result.map_error(error.JsonDecodeError)
        }
        404 -> {
          Error(error.http_not_found_error(
            dependency_name: repository.dependency_name,
          ))
        }
        code ->
          Error(error.http_unexpected_error(
            status_code: code,
            dependency_name: repository.dependency_name,
          ))
      }
    }
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

pub fn decode_releases() -> fn(Dynamic) ->
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
