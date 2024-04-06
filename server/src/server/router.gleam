import wisp.{type Request}
import gleam/http.{Post}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result
import server/web
import server/github
import server/database
import server/npm
import common
import gleam/set

pub fn handle_request(
  req: Request,
  make_context: fn() -> web.Context,
) -> wisp.Response {
  let context = make_context()
  use request <- web.middleware(req)
  use <- wisp.require_method(req, Post)
  use json <- wisp.require_json(req)

  case wisp.path_segments(request) {
    ["releases"] -> get_releases_handler(request, json, context)
    _ -> wisp.not_found()
  }
}

fn get_releases_handler(
  _: Request,
  json: Dynamic,
  context: web.Context,
) -> wisp.Response {
  let decoded_deps = common.decode_dependencies(json)

  case decoded_deps {
    Ok(dependencies) -> get_releases(dependencies, context.db)
    Error(_) -> wisp.unprocessable_entity()
  }
}

fn get_releases(dependencies: List(common.Dependency), db: database.Connection) {
  let releases_from_cache = get_releases_from_cache(dependencies, db)
  let cache_keys =
    list.map(releases_from_cache, fn(release) { release.dependency_name })
    |> set.from_list

  let dependencies_not_in_cache =
    list.filter(dependencies, fn(dependency) {
      !set.contains(cache_keys, dependency.name)
    })

  case dependencies_not_in_cache {
    [] -> {
      wisp.json_response(github.encode_releases(releases_from_cache), 200)
    }

    rest_dependencies -> {
      let releases_from_github = get_releases_from_github(rest_dependencies)
      database.insert_releases(db, releases_from_github)

      let combined_releases =
        list.append(releases_from_cache, releases_from_github)
      wisp.json_response(github.encode_releases(combined_releases), 200)
    }
  }
}

// TODO: handle unwrapping the Error values and mapping them into a type
fn get_releases_from_github(
  dependencies: List(common.Dependency),
) -> List(github.Release) {
  let repositories =
    list.map(dependencies, npm.get_repository_meta)
    |> result.values()

  list.map(repositories, github.get_releases_for_repository)
  |> result.values
  |> list.flatten
}

fn get_releases_from_cache(
  dependencies: List(common.Dependency),
  db: database.Connection,
) -> List(github.Release) {
  dependencies
  |> list.try_map(fn(dependency) { database.get_releases(db, dependency) })
  |> result.unwrap([])
  |> list.flatten
  |> list.map(database.from_db_release)
}
