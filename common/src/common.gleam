import gleam/dynamic
import gleam/json
import gleam/option.{type Option}
import gleam/list
import gleam/dict
import gleam/string_builder.{type StringBuilder}

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
  HasReleases(dependency_name: String, releases: List(Release))
  NotFound(dependency_name: String)
  NoReleases(dependency_name: String)
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
        HasReleases(name, releases) -> #(name, as_has_releases(name, releases))
        NoReleases(name) -> #(name, as_no_releases(name))
        NotFound(name) -> #(name, as_not_found(name))
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
    HasReleases(_, releases) -> releases
    _ -> []
  }
}

// functions to construct variants of the opaque ProcessedDependency type
pub fn as_has_releases(
  dependency_name name: String,
  releases items: List(Release),
) -> ProcessedDependency {
  HasReleases(name, items)
}

pub fn as_not_found(dependency_name: String) -> ProcessedDependency {
  NotFound(dependency_name)
}

pub fn as_no_releases(dependency_name: String) -> ProcessedDependency {
  NoReleases(dependency_name)
}

// ---- encoders ----

pub fn encode_dependency_map(dependency_map: DependencyMap) -> StringBuilder {
  let list_pairs = dict.to_list(dependency_map)
  let mapped =
    list.map(list_pairs, fn(pair) {
      let #(key, processed_dep) = pair
      #(key, encode_processed_dependency(processed_dep))
    })

  json.object(mapped)
  |> json.to_string_builder()
}

fn encode_processed_dependency(processed_dep: ProcessedDependency) -> json.Json {
  case processed_dep {
    HasReleases(name, releases) -> encode_has_releases(name, releases)
    NoReleases(name) -> encode_no_releases(name)
    NotFound(name) -> encode_not_found(name)
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
      #("version", json.string(release.created_at)),
    ])
  })
}
