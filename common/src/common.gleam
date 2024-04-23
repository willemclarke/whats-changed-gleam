import gleam/dynamic
import gleam/json
import gleam/option.{type Option}
import gleam/list
import gleam/dict
import gleam/string_builder.{type StringBuilder}
import gleam/io

// ---- ClientDependency type represents data sent from Client -> Server ----
pub type ClientDependency {
  ClientDependency(name: String, version: String)
}

pub fn decode_dependency() -> fn(dynamic.Dynamic) ->
  Result(ClientDependency, List(dynamic.DecodeError)) {
  dynamic.decode2(
    ClientDependency,
    dynamic.field("name", dynamic.string),
    dynamic.field("version", dynamic.string),
  )
}

pub fn decode_dependencies(
  json: dynamic.Dynamic,
) -> Result(List(ClientDependency), dynamic.DecodeErrors) {
  let decoder = dynamic.list(of: decode_dependency())
  decoder(json)
}

pub fn encode_dependencies(dependencies: List(ClientDependency)) {
  json.array(dependencies, fn(dependency) {
    json.object([
      #("name", json.string(dependency.name)),
      #("version", json.string(dependency.version)),
    ])
  })
  |> json.to_string_builder()
}

// ---- This type represents what we send from Server -> Client ----

pub type DependencyMap =
  dict.Dict(String, ProcessedDependency)

pub opaque type ProcessedDependency {
  HasReleases(kind: String, dependency_name: String, releases: List(Release))
  NotFound(kind: String, dependency_name: String)
  NoReleases(kind: String, dependency_name: String)
}

pub type Release {
  Release(
    tag_name: String,
    dependency_name: String,
    name: Option(String),
    url: String,
    created_at: String,
    version: String,
  )
}

pub fn dependency_map_from_processed_dependencies(
  deps: List(ProcessedDependency),
) -> DependencyMap {
  let pairs =
    list.map(deps, fn(processed_dep) {
      case processed_dep {
        HasReleases(_, name, releases) -> #(
          name,
          as_has_releases(name, releases),
        )
        NoReleases(_, name) -> #(name, as_no_releases(name))
        NotFound(_, name) -> #(name, as_not_found(name))
      }
    })

  dict.from_list(pairs)
}

pub fn dependency_map_from_releases(releases: List(Release)) -> DependencyMap {
  list.group(releases, fn(release) { release.dependency_name })
  |> dict.map_values(fn(key, value) {
    as_has_releases(dependency_name: key, releases: value)
  })
}

pub fn releases_from_processed_dependency(
  dependencies: List(ProcessedDependency),
) -> List(Release) {
  dependencies
  |> list.map(get_releases_from_dependency)
  |> list.flatten
}

pub fn get_releases_from_dependency(
  dependency: ProcessedDependency,
) -> List(Release) {
  case dependency {
    HasReleases(_, _, releases) -> releases
    _ -> []
  }
}

// functions to construct variants of the opaque ProcessedDependency type
pub fn as_has_releases(
  dependency_name name: String,
  releases items: List(Release),
) -> ProcessedDependency {
  HasReleases(kind: "has_releases", dependency_name: name, releases: items)
}

pub fn as_not_found(dependency_name: String) -> ProcessedDependency {
  NotFound(kind: "not_found", dependency_name: dependency_name)
}

pub fn as_no_releases(dependency_name: String) -> ProcessedDependency {
  NoReleases(kind: "no_releases", dependency_name: dependency_name)
}

// ---- decoders ----

pub fn decode_dependency_map(json: dynamic.Dynamic) {
  dynamic.dict(dynamic.string, decode_processed_dependency)(json)
}

fn decode_kind(
  data: dynamic.Dynamic,
) -> Result(String, List(dynamic.DecodeError)) {
  dynamic.field("kind", dynamic.string)(data)
}

fn decode_processed_dependency(
  json: dynamic.Dynamic,
) -> Result(ProcessedDependency, List(dynamic.DecodeError)) {
  case decode_kind(json) {
    Ok("has_releases") -> decode_has_releases()(json)
    Ok("not_found") -> decode_not_found()(json)
    Ok("no_releases") -> decode_no_releases()(json)
    _ -> error()
  }
}

fn error() -> Result(ProcessedDependency, List(dynamic.DecodeError)) {
  Error([
    dynamic.DecodeError(
      expected: "has_releases/not_found/no_releases",
      found: "",
      path: [],
    ),
  ])
}

fn decode_not_found() -> fn(dynamic.Dynamic) ->
  Result(ProcessedDependency, List(dynamic.DecodeError)) {
  dynamic.decode2(
    NotFound,
    dynamic.field("kind", dynamic.string),
    dynamic.field("dependency_name", dynamic.string),
  )
}

fn decode_no_releases() -> fn(dynamic.Dynamic) ->
  Result(ProcessedDependency, List(dynamic.DecodeError)) {
  dynamic.decode2(
    NoReleases,
    dynamic.field("kind", dynamic.string),
    dynamic.field("dependency_name", dynamic.string),
  )
}

fn decode_has_releases() -> fn(dynamic.Dynamic) ->
  Result(ProcessedDependency, List(dynamic.DecodeError)) {
  dynamic.decode3(
    HasReleases,
    dynamic.field("kind", dynamic.string),
    dynamic.field("dependency_name", dynamic.string),
    dynamic.field("releases", decode_releases),
  )
}

fn decode_releases(json: dynamic.Dynamic) {
  dynamic.list(of: dynamic.decode6(
    Release,
    dynamic.field("tag_name", dynamic.string),
    dynamic.field("dependency_name", dynamic.string),
    dynamic.field("name", dynamic.optional(dynamic.string)),
    dynamic.field("url", dynamic.string),
    dynamic.field("created_at", dynamic.string),
    dynamic.field("version", dynamic.string),
  ))(json)
}

// --- encoders ----
pub fn encode_dependency_map(dependency_map: DependencyMap) -> StringBuilder {
  dict.to_list(dependency_map)
  |> list.map(fn(pair) {
    let #(key, processed_dep) = pair
    #(key, encode_processed_dependency(processed_dep))
  })
  |> json.object
  |> json.to_string_builder()
}

pub fn encode_dependency_map_json(dependency_map: DependencyMap) -> json.Json {
  dict.to_list(dependency_map)
  |> list.map(fn(pair) {
    let #(key, processed_dep) = pair
    #(key, encode_processed_dependency(processed_dep))
  })
  |> json.object
}

fn encode_processed_dependency(processed_dep: ProcessedDependency) -> json.Json {
  case processed_dep {
    HasReleases(_, name, releases) -> encode_has_releases(name, releases)
    NoReleases(_, name) -> encode_no_releases(name)
    NotFound(_, name) -> encode_not_found(name)
  }
}

fn encode_no_releases(dependency_name: String) -> json.Json {
  json.object([
    #("kind", json.string("no_releases")),
    #("dependency_name", json.string(dependency_name)),
  ])
}

fn encode_not_found(dependency_name: String) -> json.Json {
  json.object([
    #("kind", json.string("not_found")),
    #("dependency_name", json.string(dependency_name)),
  ])
}

fn encode_has_releases(
  dependency_name: String,
  releases: List(Release),
) -> json.Json {
  json.object([
    #("kind", json.string("has_releases")),
    #("dependency_name", json.string(dependency_name)),
    #("releases", encode_releases(releases)),
  ])
}

fn encode_releases(releases: List(Release)) -> json.Json {
  json.array(releases, fn(release) {
    json.object([
      #("tag_name", json.string(release.tag_name)),
      #("dependency_name", json.string(release.dependency_name)),
      #("name", json.nullable(release.name, json.string)),
      #("url", json.string(release.url)),
      #("created_at", json.string(release.created_at)),
      #("version", json.string(release.version)),
    ])
  })
}
