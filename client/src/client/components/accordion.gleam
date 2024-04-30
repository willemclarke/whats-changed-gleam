import client/html_extra
import gleam/bool
import lustre/attribute.{class}
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(is_open: Bool)
}

pub fn init() -> #(Model, effect.Effect(Msg)) {
  #(Model(is_open: False), effect.none())
}

pub type Msg {
  OnClick
}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    OnClick -> #(Model(is_open: !model.is_open), effect.none())
  }
}

pub fn view(title: Element(Msg), body: Element(Msg), model: Model) {
  let aria_hidden = bool.guard(model.is_open, "false", fn() { "true" })

  html.div([class("w-[48rem]"), event.on_click(OnClick)], [
    html.h2([], [
      html.button(
        [
          class(
            "flex items-center justify-between w-full p-3 rtl:text-right text-gray-500 border border-b-0 border-gray-200 rounded-t-xl focus:ring-2 focus:ring-gray-200 dark:focus:ring-gray-800 dark:border-gray-700 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 gap-3",
          ),
        ],
        [title],
      ),
    ]),
    html.div([class(aria_hidden)], []),
    html_extra.view_if(
      is_true: model.is_open,
      element: html.div(
        [
          class(
            "max-h-52 overflow-y-scroll p-3 border border-b-0 border-gray-200 dark:border-gray-700 dark:bg-gray-900",
          ),
        ],
        [body],
      ),
    ),
  ])
}
