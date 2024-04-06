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
import gleam/io
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
    ["dependencies"] -> dependencies(request, json, context)
    _ -> wisp.not_found()
  }
}

fn dependencies(
  _: Request,
  json: Dynamic,
  context: web.Context,
) -> wisp.Response {
  let decoded_deps = common.decode_dependencies(json)

  case decoded_deps {
    Error(_) -> wisp.unprocessable_entity()
    Ok(deps) -> {
      io.debug(#("deps", deps))
      let releases_from_cache = get_releases_from_cache(deps, context.db)
      let cache_keys =
        releases_from_cache
        |> list.map(fn(release) { release.dependency_name })
        |> set.from_list

      let dependencies_not_in_cache =
        list.filter(deps, fn(dependency) {
          !set.contains(cache_keys, dependency.name)
        })

      io.debug(#("deps_not_in_cache", dependencies_not_in_cache))

      case dependencies_not_in_cache {
        [] -> {
          io.print("all dependencies were in cache")
          wisp.json_response(github.encode_releases(releases_from_cache), 200)
        }
        _ -> {
          io.print("have to fetch from npm/github ")
          let repositories =
            list.map(dependencies_not_in_cache, npm.get_repository_meta)
            |> result.values()

          let releases_from_github =
            list.map(repositories, github.get_releases_for_repository)
            |> result.values
            |> list.flatten

          // update database with any releases we had to fetch from github
          list.each(releases_from_github, fn(release) {
            database.insert_release(context.db, release)
          })

          // join both cache releases + those we just fetched back to client
          let combined = list.append(releases_from_cache, releases_from_github)
          wisp.json_response(github.encode_releases(combined), 200)
        }
      }
    }
  }
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
