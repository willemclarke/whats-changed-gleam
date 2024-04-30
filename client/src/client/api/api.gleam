import common
import gleam/json
import lustre/effect
import lustre_http

pub fn process_dependencies(
  msg: fn(Result(common.DependencyMap, lustre_http.HttpError)) -> msg,
  dependencies: List(common.ClientDependency),
) -> effect.Effect(msg) {
  let decoder = common.decode_dependency_map
  let expect = lustre_http.expect_json(decoder, msg)
  let body = to_body(dependencies)

  lustre_http.post("http://localhost:8080/process", body, expect)
}

fn to_body(dependencies: List(common.ClientDependency)) {
  json.array(dependencies, fn(dep) {
    json.object([
      #("name", json.string(dep.name)),
      #("version", json.string(dep.version)),
    ])
  })
}
