import lustre/effect.{type Effect}

type Timer

pub fn after(delay: Int, msg: msg) -> Effect(msg) {
  use dispatch <- effect.from
  let _ = set_timeout(delay, fn() { dispatch(msg) })

  Nil
}

@external(javascript, "../ffi.mjs", "set_timeout")
fn set_timeout(delay: Int, cb: fn() -> Nil) -> Timer
