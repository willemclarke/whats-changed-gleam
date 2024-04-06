import gleam/dynamic
import gleam/json

// Dependency type represents data sent from outside world (client -> server)
pub type Dependency {
  Dependency(name: String, version: String)
}

pub fn decode_dependency() -> fn(dynamic.Dynamic) ->
  Result(Dependency, List(dynamic.DecodeError)) {
  dynamic.decode2(
    Dependency,
    dynamic.field("name", dynamic.string),
    dynamic.field("version", dynamic.string),
  )
}

pub fn decode_dependencies(
  json: dynamic.Dynamic,
) -> Result(List(Dependency), dynamic.DecodeErrors) {
  let decoder = dynamic.list(of: decode_dependency())
  decoder(json)
}

// curl request
//  curl -v -X POST -H "Content-Type: application/json" -d '[{"name": "typescript", "version": "5.3.2"}, {"name": "zod", "version": "3.7.0"},  {"name": "idb", "version": "8.0.0"}, {"name": "pooweebumpoolick", "version": "8.0.0"}]' http://localhost:8080/dependencies
//  curl -v -X POST -H "Content-Type: application/json" -d '[{"name": "idb", "version": "8.0.0"}]' http://localhost:8080/dependencies
pub fn encode_dependencies(dependencies: List(Dependency)) {
  json.array(dependencies, fn(dependency) {
    json.object([
      #("name", json.string(dependency.name)),
      #("version", json.string(dependency.version)),
    ])
  })
  |> json.to_string_builder()
}
