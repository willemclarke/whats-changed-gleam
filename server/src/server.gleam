import wisp
import mist
import server/router
import gleam/erlang/process
import server/web
import dot_env
import dot_env/env
import server/database

pub fn main() {
  wisp.configure_logger()
  configure_env()

  let secret_key_base = wisp.random_string(64)
  let database_name = database_name()

  let make_context = fn() -> web.Context {
    let assert Ok(token) = env.get("GITHUB_TOKEN")
    let db = database.connect(database_name)
    web.Context(github_token: token, db: db)
  }

  let assert Ok(_) =
    wisp.mist_handler(router.handle_request(_, make_context), secret_key_base)
    |> mist.new()
    |> mist.port(8080)
    |> mist.start_http

  process.sleep_forever()
}

fn configure_env() -> Nil {
  dot_env.load_with_opts(dot_env.Opts(
    path: ".env",
    debug: False,
    capitalize: False,
  ))
}

fn database_name() {
  case env.get("DATABASE_PATH") {
    Ok(path) -> path
    Error(_) -> "./database.sqlite"
  }
}
