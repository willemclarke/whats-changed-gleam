import wisp
import mist
import server/router
import gleam/erlang/process
import server/web
import dot_env
import dot_env/env

pub fn main() {
  wisp.configure_logger()
  configure_env()

  let secret_key_base = wisp.random_string(64)

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

fn make_context() -> web.Context {
  let assert Ok(token) = env.get("GITHUB_TOKEN")
  web.Context(github_token: token)
}
