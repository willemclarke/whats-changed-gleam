import { Ok, Error } from "./gleam.mjs";

export function set_timeout(delay, cb) {
  return window.setTimeout(cb, delay)
}


export function get_key(key) {
  const value = window.localStorage.getItem(key);
  return value ? new Ok(value) : new Error(undefined);
}


export function set_key(key, value) {
  window.localStorage.setItem(key, value)
}
