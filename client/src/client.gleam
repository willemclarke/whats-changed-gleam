import client/accordion
import client/api
import client/toast
import common
import gleam/dict
import gleam/dynamic
import gleam/io
import gleam/json
import gleam/list
import gleam/pair
import gleam/result
import gleam/string
import gluid
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import lustre_http
import tardis

// -- Model --
pub type Model {
  Model(
    dependency_map: common.DependencyMap,
    accordion1: accordion.Model,
    input_value: String,
    toasts: List(#(toast.ToastType, String)),
  )
}

fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  #(
    Model(
      dependency_map: dict.new(),
      accordion1: pair.first(accordion.init()),
      input_value: "",
      toasts: [],
    ),
    effect.none(),
  )
}

// -- Update --
pub type Msg {
  OnInputChange(String)
  OnSubmitClicked
  GotDependencyMap(Result(common.DependencyMap, lustre_http.HttpError))
  Accordion1(accordion.Msg)
  CloseToast(String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    OnInputChange(value) -> #(Model(..model, input_value: value), effect.none())
    OnSubmitClicked -> {
      let verified = verify_input(model.input_value)

      case verified {
        Ok(client_dependencies) -> {
          #(
            show_toast(model, toast.Success("Processing dependencies")),
            api.process_dependencies(GotDependencyMap, client_dependencies),
          )
        }

        Error(error) -> {
          case error {
            EmptyInput -> #(
              show_toast(model, toast.Error("Input cannot be empty")),
              effect.none(),
            )

            NotValidJson -> #(
              show_toast(model, toast.Error("Please provide valid json")),
              effect.none(),
            )
          }
        }
      }
    }
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
    CloseToast(toast_id) -> {
      let filtered_toasts =
        list.filter(model.toasts, fn(toast) { pair.second(toast) != toast_id })

      #(Model(..model, toasts: filtered_toasts), effect.none())
    }
  }
}

fn show_toast(model: Model, toast_type: toast.ToastType) -> Model {
  let new_toast = #(toast_type, gluid.guidv4())
  Model(..model, toasts: [new_toast, ..model.toasts])
}

type Error {
  EmptyInput
  NotValidJson
}

type JsonDependencies {
  JsonDependencies(
    dependencies: JsonDependency,
    dev_dependencies: JsonDependency,
  )
}

type JsonDependency =
  dict.Dict(String, String)

fn verify_input(
  input_value: String,
) -> Result(List(common.ClientDependency), Error) {
  case string.is_empty(input_value) {
    True -> Error(EmptyInput)
    False -> {
      json.decode(input_value, extract_client_dependencies)
      |> result.replace_error(NotValidJson)
    }
  }
}

fn extract_client_dependencies(
  json: dynamic.Dynamic,
) -> Result(List(common.ClientDependency), List(dynamic.DecodeError)) {
  decode_json_dependecies(json)
  |> result.map(fn(json_deps) {
    list.append(
      to_client_dependency(json_deps.dependencies),
      to_client_dependency(json_deps.dev_dependencies),
    )
    |> fold_client_dependencies
  })
}

fn fold_client_dependencies(
  dependencies: List(common.ClientDependency),
) -> List(common.ClientDependency) {
  list.fold(dependencies, [], fn(acc, dependency) {
    let is_unsupported = is_unsupported_version(dependency.version)
    let is_types_dep = is_types_dependency(dependency.name)

    case is_unsupported, is_types_dep {
      True, True -> acc
      True, False -> acc
      False, True -> acc
      False, False -> [clean_version(dependency), ..acc]
    }
  })
}

fn clean_version(dependency: common.ClientDependency) -> common.ClientDependency {
  let cleaned_version =
    dependency.version
    |> string.replace("^", "")
    |> string.replace("~", "")

  common.ClientDependency(..dependency, version: cleaned_version)
}

fn is_unsupported_version(version: String) -> Bool {
  case version {
    "latest" -> True
    "workspace:*" -> True
    _ -> False
  }
}

fn is_types_dependency(name: String) -> Bool {
  string.starts_with(name, "@types/")
}

fn to_client_dependency(
  json_dependency: JsonDependency,
) -> List(common.ClientDependency) {
  dict.to_list(json_dependency)
  |> list.map(fn(pair) {
    let #(name, version) = pair
    common.ClientDependency(name, version)
  })
}

fn decode_json_dependecies(
  json: dynamic.Dynamic,
) -> Result(JsonDependencies, List(dynamic.DecodeError)) {
  dynamic.decode2(
    JsonDependencies,
    dynamic.field("dependencies", dynamic.dict(dynamic.string, dynamic.string)),
    dynamic.field(
      "devDependencies",
      dynamic.dict(dynamic.string, dynamic.string),
    ),
  )(json)
}

// -- View --

pub fn view(model: Model) -> element.Element(Msg) {
  let toasts =
    list.map(model.toasts, fn(toast) {
      let #(type_, id) = toast
      toast.view(type_, CloseToast(id))
    })

  html.div(
    [
      attribute.class(
        "flex h-full w-full justify-center items-center flex-col gap-y-4",
      ),
    ],
    [
      toast.region(toasts),
      html.h3([attribute.class("text-2xl font-semibold")], [
        html.text("whats-changed"),
      ]),
      // html.div([attribute.class("w-96")], [
      //   accordion.view(model.accordion1)
      //   |> element.map(Accordion1),
      // ]),
      html.textarea(
        [
          attribute.class(
            "h-2/3 w-80 p-2 border border-gray-300 rounded-lg hover:border-gray-500 focus:border-gray-700 focus:outline-0 focus:ring focus:ring-slate-300",
          ),
          event.on_input(OnInputChange),
          attribute.placeholder("paste package.json here"),
        ],
        model.input_value,
      ),
      html.button(
        [
          attribute.class(
            "py-2 px-4 bg-black text-white shadow hover:shadow-md focus:ring focus:ring-slate-300 rounded-md transition ease-in-out hover:-translate-y-0.5 duration-300",
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
  let assert Ok(main) = tardis.single("main")

  lustre.application(init, update, view)
  |> tardis.wrap(with: main)
  |> lustre.start("#app", Nil)
  |> tardis.activate(with: main)

  Nil
}
