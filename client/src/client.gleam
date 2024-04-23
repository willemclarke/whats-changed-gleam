import gleam/dynamic
import gleam/int
import gleam/list
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import lustre_http
import common
import gleam/dict
import gleam/json
import gleam/io

// -- Model --
pub type Model {
  Model(count: Int, dependency_map: common.DependencyMap)
}

fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  #(Model(0, dict.new()), effect.none())
}

// -- Update --
pub type Msg {
  Increment
  Decrement
  GotDependencyMap(Result(common.DependencyMap, lustre_http.HttpError))
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    Increment -> #(Model(..model, count: model.count + 1), get_dependencies())
    Decrement -> #(Model(..model, count: model.count - 1), effect.none())
    GotDependencyMap(Ok(map)) -> {
      io.debug(#("model", model))
      #(
        Model(..model, dependency_map: dict.merge(model.dependency_map, map)),
        effect.none(),
      )
    }
    GotDependencyMap(Error(err)) -> {
      io.debug(err)
      #(model, effect.none())
    }
  }
}

fn get_dependencies() -> effect.Effect(Msg) {
  let decoder = common.decode_dependency_map
  let expect = lustre_http.expect_json(decoder, GotDependencyMap)

  let body = fn(client_deps: List(common.ClientDependency)) {
    json.array(client_deps, fn(dep) {
      json.object([
        #("name", json.string(dep.name)),
        #("version", json.string(dep.version)),
      ])
    })
  }

  let dependencies = [
    common.ClientDependency(name: "idb", version: "8.0.0"),
    common.ClientDependency(name: "typescript", version: "4.1.1"),
    common.ClientDependency(name: "react-query", version: "3.5.1"),
    common.ClientDependency(name: "woopdeedoo", version: "1.2.3"),
  ]

  lustre_http.post("http://localhost:8080/process", body(dependencies), expect)
}

// -- View --

pub fn view(model: Model) -> element.Element(Msg) {
  let count = int.to_string(model.count)

  html.div([], [
    html.button([event.on_click(Increment)], [element.text("+")]),
    element.text(count),
    html.button([event.on_click(Decrement)], [element.text("-")]),
    html.textarea([], "hello"),
    html.div(
      [],
      dict.to_list(model.dependency_map)
        |> list.map(fn(pair) {
          let #(name, _) = pair
          html.div([], [html.text(name)])
        }),
    ),
  ])
}

pub fn main() {
  lustre.application(init, update, view)
}
