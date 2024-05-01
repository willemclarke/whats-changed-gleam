import common
import gleam/dynamic.{type Dynamic}
import gleam/http.{Get}
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import server/error

// what we get back from npm api 
pub type NpmPackage {
  NpmPackage(repository: NpmRepository)
}

pub type NpmRepository {
  NpmRepository(type_: String, url: String)
}

// what we construct from the NpmPackage response.
// this information will be used to lookup the github releases api
pub type PackageMeta {
  PackageMeta(
    github_owner: String,
    github_name: String,
    version: String,
    dependency_name: String,
  )
}

// main fn of this module
pub fn get_package_meta(
  dependency: common.ClientDependency,
) -> Result(PackageMeta, error.Error) {
  fetch_package_details(dependency)
  |> result.map(fn(package) { extract_repository_meta(package, dependency) })
}

fn extract_repository_meta(
  package: NpmPackage,
  dependency: common.ClientDependency,
) -> PackageMeta {
  let split = string.split(package.repository.url, "/")

  let assert Ok(github_owner) = list.at(split, 3)
  let assert Ok(repository_name) = list.at(split, 4)
  let github_name = string.replace(repository_name, ".git", "")

  PackageMeta(
    github_owner,
    github_name: string.lowercase(github_name),
    dependency_name: dependency.name,
    version: dependency.version,
  )
}

fn fetch_package_details(
  dependency: common.ClientDependency,
) -> Result(NpmPackage, error.Error) {
  let assert Ok(response_) =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("registry.npmjs.org")
    |> request.set_path("/" <> dependency.name)
    |> request.set_header("Content-Type", "application/json")
    |> httpc.send()

  case response_.status {
    200 -> {
      response.try_map(response_, json.decode(_, decode_npm_package()))
      |> result.map(fn(res) { res.body })
      |> result.map_error(error.JsonDecodeError)
    }
    404 -> Error(error.http_not_found_error(dependency_name: dependency.name))
    code ->
      Error(error.http_unexpected_error(
        status_code: code,
        dependency_name: dependency.name,
      ))
  }
}

fn decode_npm_package() -> fn(Dynamic) ->
  Result(NpmPackage, List(dynamic.DecodeError)) {
  dynamic.decode1(
    NpmPackage,
    dynamic.field("repository", decode_npm_repository()),
  )
}

fn decode_npm_repository() -> fn(Dynamic) ->
  Result(NpmRepository, List(dynamic.DecodeError)) {
  dynamic.decode2(
    NpmRepository,
    dynamic.field("type", dynamic.string),
    dynamic.field("url", dynamic.string),
  )
}
