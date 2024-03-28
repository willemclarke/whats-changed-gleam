import wisp.{type Request}
import server/web
import gleam/http.{Get, Post}
import gleam/httpc
import gleam/http/request
import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/list
import gleam/io
import gleam/string
import gleam/result
import server/error
import common

pub type NpmPackage {
  NpmPackage(repository: NpmRepository)
}

pub type NpmRepository {
  NpmRepository(type_: String, url: String)
}

pub type Repository {
  Repository(
    github_owner: String,
    github_name: String,
    version: String,
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
      let x =
        list.map(deps, get_repository_details_from_npm)
        |> io.debug()

      wisp.json_response(common.encode_dependencies(deps), 200)
    }
    Error(_) -> wisp.unprocessable_entity()
  }
}

pub fn get_repository_details_from_npm(
  dependency: common.Dependency,
) -> Result(Repository, error.Error) {
  let package_details = get_package_details(dependency)

  case package_details {
    Ok(package) -> Ok(extract_repository_details(package, dependency))
    Error(err) -> Error(err)
  }
}

pub fn extract_repository_details(
  package: NpmPackage,
  dependency: common.Dependency,
) -> Repository {
  let split = string.split(package.repository.url, "/")

  let assert Ok(github_owner) = list.at(split, 3)
  let assert Ok(repository_name) = list.at(split, 4)
  let github_name = string.replace(repository_name, ".git", "")

  Repository(
    github_name,
    github_owner,
    dependency_name: dependency.name,
    version: dependency.version,
  )
}

fn get_package_details(
  dependency: common.Dependency,
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
      json.decode(response_.body, decode_npm_package())
      |> result.map_error(error.JsonDecodeError)
    }
    404 -> {
      Error(error.http_not_found_error(dependency_name: dependency.name))
    }
    _ -> Error(error.http_unexpected_error(dependency_name: dependency.name))
  }
}

pub fn decode_npm_package() -> fn(Dynamic) ->
  Result(NpmPackage, List(dynamic.DecodeError)) {
  dynamic.decode1(NpmPackage, dynamic.field("repository", decode_repository()))
}

pub fn decode_repository() -> fn(Dynamic) ->
  Result(NpmRepository, List(dynamic.DecodeError)) {
  dynamic.decode2(
    NpmRepository,
    dynamic.field("type", dynamic.string),
    dynamic.field("url", dynamic.string),
  )
}
// fn decode_dependency() -> fn(Dynamic) ->
//   Result(Dependency, List(dynamic.DecodeError)) {
//   dynamic.decode2(
//     Dependency,
//     dynamic.field("name", dynamic.string),
//     dynamic.field("version", dynamic.string),
//   )
// }

// fn decode_dependencies(
//   json: Dynamic,
// ) -> Result(List(Dependency), dynamic.DecodeErrors) {
//   let decoder = dynamic.list(of: decode_dependency())
//   decoder(json)
// }

// // curl request
// //  curl -v -X POST -H "Content-Type: application/json" -d '[{"name": "typescript", "version": "5.3.2"}, {"name": "zod", "version": "3.7.0"},  {"name": "idb", "version": "8.0.0"}]' http://localhost:8080/dependencies
// fn encode_dependencies(dependencies: List(Dependency)) {
//   json.array(dependencies, fn(dependency) {
//     json.object([
//       #("name", json.string(dependency.name)),
//       #("version", json.string(dependency.version)),
//     ])
//   })
//   |> json.to_string_builder()
// }
