import gleam/http
import server/database
import wisp

pub type Context {
  Context(
    github_token: String,
    environment: String,
    static_directory: String,
    db: database.Connection,
  )
}

pub fn middleware(
  req: wisp.Request,
  context: Context,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use req <- cors(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(
    req,
    under: "/static",
    from: context.static_directory,
  )

  handle_request(req)
}

pub fn cors(
  req: wisp.Request,
  handle_request: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  case req.method {
    http.Options ->
      wisp.ok()
      |> wisp.set_header("access-control-allow-origin", "*")
      |> wisp.set_header("access-control-allow-headers", "content-type")
      |> wisp.set_header(
        "access-control-allow-method",
        "POST,GET,PUT,PATCH,DELETE",
      )
    _ ->
      handle_request(req)
      |> wisp.set_header("access-control-allow-origin", "*")
      |> wisp.set_header("access-control-allow-headers", "content-type")
      |> wisp.set_header(
        "access-control-allow-method",
        "POST,GET,PUT,PATCH,DELETE",
      )
  }
}
