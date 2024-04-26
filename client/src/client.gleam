import client/accordion
import client/api
import common
import gleam/dict
import gleam/io
import gleam/list
import gleam/pair
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import lustre_http

// hardcoding for now
const dependencies: List(common.ClientDependency) = [
  common.ClientDependency(name: "idb", version: "8.0.0"),
  common.ClientDependency(name: "typescript", version: "4.1.1"),
  common.ClientDependency(name: "react-query", version: "3.5.1"),
  common.ClientDependency(name: "woopdeedoo", version: "1.2.3"),
]

// -- Model --
pub type Model {
  Model(dependency_map: common.DependencyMap, accordion1: accordion.Model)
}

fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  #(
    Model(dependency_map: dict.new(), accordion1: pair.first(accordion.init())),
    effect.none(),
  )
}

// -- Update --
pub type Msg {
  OnSubmitClicked
  GotDependencyMap(Result(common.DependencyMap, lustre_http.HttpError))
  Accordion1(accordion.Msg)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    OnSubmitClicked -> #(
      model,
      api.process_dependencies(GotDependencyMap, dependencies),
    )
    GotDependencyMap(Ok(map)) -> {
      #(Model(..model, dependency_map: map), effect.none())
    }
    GotDependencyMap(Error(err)) -> {
      io.debug(err)
      #(model, effect.none())
    }
    Accordion1(msg_) -> {
      let #(accordion, cmd) = accordion.update(model.accordion1, msg_)
      #(Model(..model, accordion1: accordion), effect.map(cmd, Accordion1))
    }
  }
}

// -- View --

pub fn view(model: Model) -> element.Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex bg-slate-50 h-full w-full justify-center items-center flex-col gap-y-4",
      ),
    ],
    [
      html.h3([attribute.class("text-xl font-semibold")], [
        html.text("whats-changed"),
      ]),
      html.div([attribute.class("w-96")], [
        accordion.view(model.accordion1)
        |> element.map(Accordion1),
      ]),
      html.textarea(
        [
          attribute.class("h-2/3 w-80"),
          attribute.placeholder("paste package.json here"),
        ],
        "hello",
      ),
      html.button(
        [
          attribute.class(
            "bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded",
          ),
          event.on_click(OnSubmitClicked),
        ],
        [html.text("Submit")],
      ),
      html.div(
        [],
        dict.to_list(model.dependency_map)
          |> list.map(fn(pair) {
          let #(name, _) = pair
          html.div([], [html.text(name)])
        }),
      ),
    ],
  )
}

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
