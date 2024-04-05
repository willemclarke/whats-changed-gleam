import wisp.{type Request}
import gleam/http.{Post}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/result
import server/web
import server/github
import server/npm
import common

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
        list.map(deps, npm.get_repository_meta)
        |> result.values()

      let _ = list.map(repositories, github.get_releases_for_repository)

      wisp.json_response(common.encode_dependencies(deps), 200)
    }
    Error(_) -> wisp.unprocessable_entity()
  }
}
