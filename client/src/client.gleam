import client/api/api
import client/components/accordion
import client/components/badge
import client/components/icon
import client/components/popover
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
    search_term: String,
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
      search_term: "",
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
  OnSearchDependenciesInputChanged(String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    OnInputChange(value) -> #(Model(..model, input_value: value), effect.none())
    OnSearchDependenciesInputChanged(search_term) -> {
      let filtered_accordions =
        model.accordions_dict
        |> dict.filter(fn(dependency_name, _) {
          string.contains(dependency_name, search_term)
        })

      // if the size of the dict > 0 and the search_term is "", it means we've filtered
      // the set of results, but backspaced, so we want to show the original unfiltered set of data.
      // otherwise, show the filtered accordions
      let updated_accordions = case dict.size(filtered_accordions), search_term {
        _, "" -> set_accordions_dict(model.dependency_map)
        _, _ -> filtered_accordions
      }

      #(
        Model(
          ..model,
          search_term: search_term,
          accordions_dict: updated_accordions,
        ),
        effect.none(),
      )
    }
    OnSubmitClicked -> {
      let verified = verify_input(model.input_value)

      case verified {
        Ok(client_dependencies) -> {
          let toast = #(
            toast.Success("Processing dependencies.."),
            gluid.guidv4(),
          )

          #(
            Model(
              ..with_toast(toast, model),
              dependency_map: dict.new(),
              accordions_dict: dict.new(),
              is_loading: True,
              is_input_hidden: True,
            ),
            effect.batch([
              api.process_dependencies(GotDependencyMap, client_dependencies),
              local_storage.set_key("last_searched", model.input_value),
            ]),
          )
        }
        Error(error) -> {
          case error {
            EmptyInput -> {
              let toast = #(
                toast.Error("Input cannot be empty"),
                gluid.guidv4(),
              )

              #(
                with_toast(toast, model),
                timer.after(3000, CloseToast(pair.second(toast))),
              )
            }
            NotValidJson -> {
              let toast = #(
                toast.Error("Please provide valid json"),
                gluid.guidv4(),
              )
              #(
                with_toast(toast, model),
                timer.after(3000, CloseToast(pair.second(toast))),
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
          toasts: [],
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
          let toast = #(
            toast.Error("Unable to decode value from local storage"),
            gluid.guidv4(),
          )
          #(
            with_toast(toast, model),
            timer.after(3000, CloseToast(pair.second(toast))),
          )
        }
      }
    }
    GotDependencyMapFromLocalStorage(Error(_)) -> #(model, effect.none())

    GotLastSearchedFromLocalStorage(Ok(last_searched)) -> {
      let decoded = json.decode(last_searched, dynamic.string)
      case decoded {
        Ok(json) -> #(
          Model(..model, last_searched: option.Some(json)),
          effect.none(),
        )
        Error(_) -> #(model, effect.none())
      }
      #(
        Model(..model, last_searched: option.Some(last_searched)),
        effect.none(),
      )
    }
    GotLastSearchedFromLocalStorage(Error(_)) -> {
      #(model, effect.none())
    }
    AccordionNClicked(id, is_open) -> {
      #(
        Model(
          ..model,
          accordions_dict: dict.insert(model.accordions_dict, id, !is_open),
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

// when we get the dependency_map back from either backend or localstorage, 
// we need to initialise N accordion (dependency_name, bool) for each dependency we get back, 
// so if 10 keys we will get 10 dict states
fn set_accordions_dict(dependency_map: common.DependencyMap) -> AccordionsDict {
  dependency_map
  |> dict.fold(dict.new(), fn(acc, name, _) { dict.insert(acc, name, False) })
}

fn with_toast(toast: #(toast.ToastType, String), model: Model) -> Model {
  Model(..model, toasts: [toast, ..model.toasts])
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
      view_header(),
      view_controls(model),
      html.div([class("flex h-full flex-row justify-center gap-x-4 ")], [
        view_package_json_input(model),
        view_releases(model),
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

fn view_header() -> Element(msg) {
  html.div([class("flex gap-x-2 items-center")], [
    html.h3([class("text-2xl font-semibold my-3")], [html.text("whats-changed")]),
    html.a(
      [
        attribute.href("https://github.com/willemclarke/whats-changed-gleam"),
        attribute.target("_blank"),
      ],
      [icon.icon("github", icon.Alt("repo"), icon.Medium)],
    ),
  ])
}

fn view_controls(model: Model) -> Element(Msg) {
  case dict.size(model.dependency_map) {
    0 -> html.text("")
    _ ->
      html.div([class("flex gap-x-2 items-center")], [
        view_search_again_button(model.is_input_hidden),
        view_filter_input(),
      ])
  }
}

fn view_search_again_button(is_input_hidden: Bool) -> Element(Msg) {
  html_extra.view_if(
    is_true: is_input_hidden,
    display: html.button(
      [
        event.on_click(OnSearchAgainClicked),
        class(
          "my-2 px-3 py-2 text-xs bg-black text-white shadow hover:shadow-md focus:ring focus:ring-slate-300 rounded-md transition ease-in-out hover:-translate-y-0.5 duration-300",
        ),
      ],
      [html.text("Search again")],
    ),
  )
}

fn view_filter_input() -> Element(Msg) {
  html.input([
    class(
      "my-2 p-1 px-2 border border-gray-300 rounded-lg hover:border-gray-500 focus:border-gray-700 focus:outline-0 focus:ring focus:ring-slate-300",
    ),
    event.on_input(OnSearchDependenciesInputChanged),
    attribute.placeholder("Filter here"),
  ])
}

fn view_package_json_input(model: Model) -> Element(Msg) {
  html.div([class("flex flex-col gap-y-2")], [
    case model.is_input_hidden {
      True -> html.text("")
      False ->
        html.div([class("h-full flex flex-col gap-y-2")], [
          html.textarea(
            [
              class(
                "min-h-[36rem] max-h-[36rem] w-80 p-2 border border-gray-300 rounded-lg hover:border-gray-500 focus:border-gray-700 focus:outline-0 focus:ring focus:ring-slate-300",
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
  ])
}

fn view_releases(model: Model) -> Element(Msg) {
  html.div([class("min-h-[36rem] max-h-[36rem] overflow-y-auto")], case
    model.is_loading
  {
    True -> [
      html.div([class("w-[62rem] h-full flex justify-center items-center")], [
        html.div([class("animate-spin")], [
          icon.icon("diamond", icon.Alt("spinner"), icon.Large),
        ]),
      ]),
    ]

    False ->
      view_release_accordions(model.accordions_dict, model.dependency_map)
  })
}

fn view_release_accordions(
  accordions_dict: AccordionsDict,
  dependency_map: common.DependencyMap,
) -> List(Element(Msg)) {
  let accordions_dict_list = dict.to_list(accordions_dict)
  use accordion_pair <- list.map(accordions_dict_list)

  let #(dep_name, is_open) = accordion_pair
  let lookup_processed_dep = dict.get(dependency_map, dep_name)

  case lookup_processed_dep {
    Ok(processed_dep) -> {
      accordion.view(accordion.Config(
        title: accordion_title(processed_dep),
        body: view_processed_dependency(processed_dep),
        on_click: AccordionNClicked(dep_name, is_open),
        is_open: is_open,
      ))
    }
    Error(_) -> html.text("")
  }
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
    common.HasReleases(_, _, releases) -> view_has_releases(releases)
    common.NotFound(_, _) -> html.p([], [html.text("Not found")])
    common.NoReleases(_, _) -> html.p([], [html.text("Up to date")])
  }
}

fn view_has_releases(releases: List(common.Release)) -> Element(msg) {
  html.div(
    [class("flex flex-col gap-y-2")],
    list.map(releases, fn(release) {
      html.div([class("flex flex-row gap-x-2 w-full")], [
        badge.view(release.tag_name),
        case release.body {
          option.None -> release_url(release.url)

          option.Some(release_body) -> {
            case release_body {
              "" -> release_url(release.url)
              _ ->
                popover.view(popover.Props(
                  trigger: [release_url(release.url)],
                  content: html.div([class("rounded-md p-2 overflow-y-auto")], [
                    html.div(
                      [
                        class("w-[24rem] max-h-72"),
                        attribute.attribute(
                          "dangerous-unescaped-html",
                          release_body,
                        ),
                      ],
                      [],
                    ),
                  ]),
                ))
            }
          }
        },
      ])
    }),
  )
}

fn release_url(url: String) -> Element(msg) {
  html.a(
    [attribute.href(url), attribute.target("_blank"), class("hover:underline")],
    [html.text(url)],
  )
}

// -- Main --

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
