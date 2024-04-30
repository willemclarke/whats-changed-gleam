import client/accordion
import client/api
import client/timer
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
    accordions_dict: dict.Dict(String, accordion.Model),
    input_value: String,
    toasts: List(#(toast.ToastType, String)),
  )
}

fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  #(
    Model(
      dependency_map: dict.new(),
      accordions_dict: dict.new(),
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
  AccordionNClicked(String, accordion.Msg)
  CloseToast(String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    OnInputChange(value) -> #(Model(..model, input_value: value), effect.none())
    OnSubmitClicked -> {
      let verified = verify_input(model.input_value)

      case verified {
        Ok(client_dependencies) -> {
          let toast_id = gluid.guidv4()

          #(
            with_toast(
              model,
              toast.Success("Processing dependencies"),
              toast_id,
            ),
            effect.batch([
              api.process_dependencies(GotDependencyMap, client_dependencies),
              timer.after(3000, CloseToast(toast_id)),
            ]),
          )
        }
        Error(error) -> {
          case error {
            EmptyInput -> {
              let toast_id = gluid.guidv4()
              #(
                with_toast(
                  model,
                  toast.Error("Input cannot be empty"),
                  toast_id,
                ),
                timer.after(3000, CloseToast(toast_id)),
              )
            }
            NotValidJson -> {
              let toast_id = gluid.guidv4()
              #(
                with_toast(
                  model,
                  toast.Error("Please provide valid json"),
                  toast_id,
                ),
                timer.after(3000, CloseToast(toast_id)),
              )
            }
          }
        }
      }
    }
    GotDependencyMap(Ok(map)) -> {
      // when we get the dependency_map back, we need to initialise N accordion models
      // for each dependency we get back, so if 10 keys we will get 10 models
      let accordions_dict =
        dict.keys(map)
        |> list.map(fn(_) { #(gluid.guidv4(), pair.first(accordion.init())) })
        |> dict.from_list

      #(
        Model(..model, dependency_map: map, accordions_dict: accordions_dict),
        effect.none(),
      )
    }
    GotDependencyMap(Error(_)) -> {
      #(model, effect.none())
    }
    AccordionNClicked(id, msg) -> {
      // when a given accordion is clicked, we need to update that accordion
      // inside the dict so that it has the new state/model for that given accordion (opening or
      // closing it)
      let assert Ok(accordion) =
        model.accordions_dict
        |> dict.to_list()
        |> list.find(fn(tuple) {
          let #(accordion_id, _) = tuple
          accordion_id == id
        })

      let #(id, accordion_model) = accordion
      let #(new_model, _) = accordion.update(accordion_model, msg)

      #(
        Model(
          ..model,
          accordions_dict: dict.update(model.accordions_dict, id, fn(_) {
            new_model
          }),
        ),
        effect.none(),
      )
    }
    CloseToast(toast_id) -> {
      let filtered_toasts =
        list.filter(model.toasts, fn(toast) { pair.second(toast) != toast_id })

      #(Model(..model, toasts: filtered_toasts), effect.none())
    }
  }
}

fn with_toast(model: Model, toast_type: toast.ToastType, id: String) -> Model {
  let new_toast = #(toast_type, id)
  Model(..model, toasts: list.append(model.toasts, [new_toast]))
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
  // todo: use element.keyed here
  let toasts =
    list.map(model.toasts, fn(toast) {
      let #(type_, id) = toast
      toast.view(type_, CloseToast(id))
    })

  let dependency_map_list = dict.to_list(model.dependency_map)
  let accordion_dict_list = dict.to_list(model.accordions_dict)

  let accordions =
    list.map2(
      accordion_dict_list,
      dependency_map_list,
      fn(accordion_pair, map_pair) {
        let #(id, accordion) = accordion_pair
        let #(dependency_name, _) = map_pair

        accordion.view(dependency_name, "some body", accordion)
        |> element.map(fn(msg) { AccordionNClicked(id, msg) })
      },
    )

  html.div(
    [
      attribute.class(
        "flex h-full w-full justify-center items-center flex-col gap-y-4",
      ),
    ],
    [
      toast.region(toasts),
      html.h3([attribute.class("text-2xl font-semibold my-2")], [
        html.text("whats-changed"),
      ]),
      html.div([attribute.class("flex h-full flex-row gap-x-4")], [
        html.div([attribute.class("flex flex-col gap-y-2")], [
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
        ]),
        html.div([], accordions),
      ]),
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
