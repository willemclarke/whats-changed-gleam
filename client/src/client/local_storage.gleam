import lustre/effect

pub fn get_key(
  key: String,
  to_msg: fn(Result(String, Nil)) -> msg,
) -> effect.Effect(msg) {
  effect.from(fn(dispatch) {
    do_read(key)
    |> to_msg
    |> dispatch
  })
}

pub fn set_key(key: String, value: String) -> effect.Effect(msg) {
  effect.from(fn(_) { do_write(key, value) })
}

@external(javascript, "../ffi.mjs", "get_key")
fn do_read(key: String) -> Result(String, Nil)

@external(javascript, "../ffi.mjs", "set_key")
fn do_write(key: String, value: String) -> Nil {
  Nil
}
