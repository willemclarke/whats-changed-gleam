import dot_env
import dot_env/env
import gleam/erlang/process
import mist
import server/database
import server/router
import server/web
import wisp

pub fn main() {
  wisp.configure_logger()
  configure_env()

  let secret_key_base = wisp.random_string(64)

  // Initialisation that is run per-request
  let make_context = fn() -> web.Context {
    let assert Ok(token) = env.get("GITHUB_TOKEN")
    let assert Ok(environment) = env.get("ENVIRONMENT")
    let assert Ok(priv) = wisp.priv_directory("server")

    let static_directory = priv <> "/static"
    let database_name = database_name(static_directory)
    let db = database.connect(database_name)

    web.Context(
      github_token: token,
      environment: environment,
      static_directory: static_directory,
      db: db,
    )
  }

  let assert Ok(_) =
    router.handle_request(_, make_context)
    |> wisp.mist_handler(secret_key_base)
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

fn database_name(static_directory: String) {
  case env.get("DATABASE_PATH") {
    Ok(path) -> path
    Error(_) -> static_directory <> "/database.sqlite"
  }
}
