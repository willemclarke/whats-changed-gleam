import client/api/api
import client/components/accordion
import client/components/badge
import client/components/icon
import client/components/toast
import client/html_extra
import client/local_storage
import client/timer
import common
import gleam/dict
import gleam/dynamic
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/string
import gluid
import lustre
import lustre/attribute.{class}
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_http
import tardis

// -- Model --
pub type Model {
  Model(
    dependency_map: common.DependencyMap,
    accordions_dict: AccordionsDict,
    input_value: String,
    toasts: Toasts,
    last_searched: option.Option(String),
    is_loading: Bool,
    is_input_hidden: Bool,
  )
}

type AccordionsDict =
  dict.Dict(String, Bool)

type Toasts =
  List(#(toast.ToastType, String))

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

fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  #(
    Model(
      dependency_map: dict.new(),
      accordions_dict: dict.new(),
      input_value: "",
      toasts: [],
      last_searched: option.None,
      is_input_hidden: False,
      is_loading: False,
    ),
    effect.batch([
      local_storage.get_key("dependency_map", GotDependencyMapFromLocalStorage),
      local_storage.get_key("last_searched", GotLastSearchedFromLocalStorage),
    ]),
  )
}

// -- Update --
pub type Msg {
  OnInputChange(String)
  OnSubmitClicked
  GotDependencyMap(Result(common.DependencyMap, lustre_http.HttpError))
  AccordionNClicked(String, Bool)
  CloseToast(String)
  GotDependencyMapFromLocalStorage(Result(String, Nil))
  GotLastSearchedFromLocalStorage(Result(String, Nil))
  OnSearchAgainClicked
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
            Model(
              ..with_toast(
                model,
                toast.Success("Processing dependencies.."),
                toast_id,
              ),
              is_loading: True,
            ),
            effect.batch([
              api.process_dependencies(GotDependencyMap, client_dependencies),
              timer.after(3000, CloseToast(toast_id)),
              local_storage.set_key("last_searched", model.input_value),
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
    GotDependencyMap(Ok(dependency_map)) -> {
      #(
        Model(
          ..model,
          dependency_map: dependency_map,
          accordions_dict: set_accordions_dict(dependency_map),
          is_loading: False,
          is_input_hidden: True,
        ),
        local_storage.set_key(
          "dependency_map",
          common.encode_dependency_map_to_string(dependency_map),
        ),
      )
    }
    GotDependencyMap(Error(_)) -> {
      #(model, effect.none())
    }
    GotDependencyMapFromLocalStorage(Ok(string)) -> {
      let decoded = json.decode(string, common.decode_dependency_map)

      case decoded {
        Ok(dependency_map) -> {
          #(
            Model(
              ..model,
              dependency_map: dependency_map,
              accordions_dict: set_accordions_dict(dependency_map),
              is_input_hidden: True,
            ),
            effect.none(),
          )
        }
        Error(_) -> {
          let toast_id = gluid.guidv4()
          #(
            with_toast(
              model,
              toast.Error("Unable to decode value from local storage"),
              toast_id,
            ),
            effect.none(),
          )
        }
      }
    }
    GotDependencyMapFromLocalStorage(Error(_)) -> #(model, effect.none())
    GotLastSearchedFromLocalStorage(Ok(last_searched)) -> {
      #(
        Model(..model, last_searched: option.Some(last_searched)),
        effect.none(),
      )
    }
    GotLastSearchedFromLocalStorage(Error(_)) -> {
      #(model, effect.none())
    }
    AccordionNClicked(id, is_open) -> {
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

      let accordion_id = pair.first(accordion)

      #(
        Model(
          ..model,
          accordions_dict: dict.update(
            model.accordions_dict,
            accordion_id,
            fn(_) { !is_open },
          ),
        ),
        effect.none(),
      )
    }
    OnSearchAgainClicked -> {
      #(Model(..model, is_input_hidden: False), effect.none())
    }
    CloseToast(toast_id) -> {
      let filtered_toasts =
        list.filter(model.toasts, fn(toast) { pair.second(toast) != toast_id })

      #(Model(..model, toasts: filtered_toasts), effect.none())
    }
  }
}

// when we get the dependency_map back from either BE or localstorage, 
// we need to initialise N accordion models for each dependency we get back, 
// so if 10 keys we will get 10 models
fn set_accordions_dict(dependency_map: common.DependencyMap) -> AccordionsDict {
  dependency_map
  |> dict.keys()
  |> list.map(fn(_) { #(gluid.guidv4(), False) })
  |> dict.from_list
}

fn with_toast(model: Model, toast_type: toast.ToastType, id: String) -> Model {
  let new_toast = #(toast_type, id)
  Model(..model, toasts: list.append(model.toasts, [new_toast]))
}

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

pub fn view(model: Model) -> Element(Msg) {
  html.div(
    [class("flex flex-col p-6 h-screen w-full justify-center items-center")],
    [
      view_toasts(model.toasts),
      html.div([class("flex gap-x-2 items-center")], [
        html.h3([class("text-2xl font-semibold my-3")], [
          html.text("whats-changed"),
        ]),
        html.a(
          [
            attribute.href(
              "https://github.com/willemclarke/whats-changed-gleam",
            ),
            attribute.target("_blank"),
          ],
          [icon.icon("github", icon.Alt("repo"), icon.Medium)],
        ),
      ]),
      html_extra.view_if(
        is_true: model.is_input_hidden,
        display: html.button(
          [
            event.on_click(OnSearchAgainClicked),
            class(
              "my-2 px-3 py-2 text-xs bg-black text-white shadow hover:shadow-md focus:ring focus:ring-slate-300 rounded-md transition ease-in-out hover:-translate-y-0.5 duration-300",
            ),
          ],
          [html.text("Search again")],
        ),
      ),
      html.div([class("flex h-full flex-row justify-center gap-x-4 ")], [
        html.div([class("flex flex-col gap-y-2")], [
          case model.is_input_hidden {
            True -> html.text("")
            False ->
              html.div([class("h-full flex flex-col")], [
                html.textarea(
                  [
                    class(
                      "h-2/3 w-80 p-2 border border-gray-300 rounded-lg hover:border-gray-500 focus:border-gray-700 focus:outline-0 focus:ring focus:ring-slate-300",
                    ),
                    event.on_input(OnInputChange),
                    attribute.placeholder("paste package.json here"),
                  ],
                  model.input_value,
                ),
                html.button(
                  [
                    class(
                      "py-2 px-4 bg-black text-white shadow hover:shadow-md focus:ring focus:ring-slate-300 rounded-md transition ease-in-out hover:-translate-y-0.5 duration-300",
                    ),
                    event.on_click(OnSubmitClicked),
                  ],
                  [html.text("Submit")],
                ),
              ])
          },
        ]),
        html.div([class("h-2/3 overflow-y-auto")], case model.is_loading {
          True -> [
            html.div(
              [class("w-[53rem] h-full flex justify-center items-center")],
              [
                html.div([class("animate-spin")], [
                  icon.icon("diamond", icon.Alt("spinner"), icon.Large),
                ]),
              ],
            ),
          ]
          False -> view_accordions(model.accordions_dict, model.dependency_map)
        }),
      ]),
    ],
  )
}

fn view_toasts(toasts: Toasts) {
  // todo: use element.keyed here
  toasts
  |> list.map(fn(toast_tuple) {
    let #(toast_type, id) = toast_tuple
    toast.view(toast_type, CloseToast(id))
  })
  |> toast.region()
}

fn view_accordions(
  accordions_dict: AccordionsDict,
  dependency_map: common.DependencyMap,
) -> List(Element(Msg)) {
  let accordions_dict_list = dict.to_list(accordions_dict)
  let dependency_map_list = dict.to_list(dependency_map)

  use accordion_pair, map_pair <- list.map2(
    accordions_dict_list,
    dependency_map_list,
  )

  let #(id, is_open) = accordion_pair
  let #(_, processed_dependency) = map_pair

  accordion.view(accordion.Config(
    title: accordion_title(processed_dependency),
    body: view_processed_dependency(processed_dependency),
    on_click: AccordionNClicked(id, is_open),
    is_open: is_open,
  ))
}

fn accordion_title(
  processed_dependency: common.ProcessedDependency,
) -> Element(msg) {
  case processed_dependency {
    common.HasReleases(_, name, releases) -> {
      let count =
        releases
        |> list.length()
        |> int.to_string()

      html.div([class("flex flex-row gap-x-2 items-center")], [
        html.p([class("font-semibold")], [html.text(name)]),
        html.p([class("text-sm")], [
          html.text("(" <> count <> " releases" <> ")"),
        ]),
      ])
    }
    common.NotFound(_, name) -> {
      html.div([class("flex flex-row gap-x-2 items-center")], [
        html.p([class("font-semibold")], [html.text(name)]),
        html.p([class("text-sm")], [html.text("(Dependency not found)")]),
      ])
    }
    common.NoReleases(_, name) -> {
      html.div([class("flex flex-row gap-x-2 items-center")], [
        html.p([class("font-semibold")], [html.text(name)]),
        html.p([class("text-sm")], [html.text("(Dependecy has no releases)")]),
      ])
    }
  }
}

fn view_processed_dependency(
  processed_dependency: common.ProcessedDependency,
) -> Element(msg) {
  case processed_dependency {
    common.HasReleases(_, _, releases) -> {
      html.div(
        [class("flex flex-col gap-y-2")],
        list.map(releases, fn(release) {
          html.div([class("flex flex-row gap-x-2 w-full")], [
            badge.view(release.tag_name),
            html.a(
              [
                attribute.href(release.url),
                attribute.target("_blank"),
                class("hover:underline"),
              ],
              [html.text(release.url)],
            ),
          ])
        }),
      )
    }
    common.NotFound(_, _) -> {
      html.p([], [html.text("Not found")])
    }
    common.NoReleases(_, _) -> {
      html.p([], [html.text("Up to date")])
    }
  }
}

// -- Main --

pub fn main() {
  let assert Ok(main) = tardis.single("main")

  lustre.application(init, update, view)
  |> tardis.wrap(with: main)
  |> lustre.start("#app", Nil)
  |> tardis.activate(with: main)

  Nil
}
