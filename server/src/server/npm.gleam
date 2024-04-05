import common
import server/error
import gleam/dynamic.{type Dynamic}
import gleam/http.{Get}
import gleam/httpc
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/string
import gleam/list

// what we get back from npm api 
pub type NpmPackage {
  NpmPackage(repository: NpmRepository)
}

pub type NpmRepository {
  NpmRepository(type_: String, url: String)
}

// what we construct from the NpmPackage response.
// this information will be used to lookup the github releases api
pub type RepositoryMeta {
  RepositoryMeta(
    github_owner: String,
    github_name: String,
    version: String,
    dependency_name: String,
  )
}

// main fn of this module
pub fn get_repository_meta(
  dependency: common.Dependency,
) -> Result(RepositoryMeta, error.Error) {
  let package_details = fetch_package_details(dependency)

  case package_details {
    Ok(package) -> Ok(extract_repository_meta(package, dependency))
    Error(err) -> Error(err)
  }
}

pub fn extract_repository_meta(
  package: NpmPackage,
  dependency: common.Dependency,
) -> RepositoryMeta {
  let split = string.split(package.repository.url, "/")

  let assert Ok(github_owner) = list.at(split, 3)
  let assert Ok(repository_name) = list.at(split, 4)
  let github_name = string.replace(repository_name, ".git", "")

  RepositoryMeta(
    github_owner,
    github_name: string.lowercase(github_name),
    dependency_name: dependency.name,
    version: dependency.version,
  )
}

pub fn fetch_package_details(
  dependency: common.Dependency,
) -> Result(NpmPackage, error.Error) {
  let assert Ok(response_) =
    request.new()
    |> request.set_method(Get)
    |> request.set_host("registry.npmjs.org")
    |> request.set_path("/" <> dependency.name)
    |> request.set_header("Content-Type", "application/json")
    |> httpc.send()

  let decoded =
    response.try_map(response_, json.decode(_, decode_npm_package()))

  case decoded {
    Ok(resp) -> {
      case resp.status {
        200 -> Ok(resp.body)
        404 ->
          Error(error.http_not_found_error(dependency_name: dependency.name))
        code ->
          Error(error.http_unexpected_error(
            status_code: code,
            dependency_name: dependency.name,
          ))
      }
    }
    Error(err) -> Error(error.JsonDecodeError(err))
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
