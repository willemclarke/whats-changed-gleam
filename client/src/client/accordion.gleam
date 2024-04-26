import client/html_extra
import gleam/bool
import lustre/attribute
import lustre/effect
import lustre/element
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

pub fn view(model: Model) {
  let aria_hidden = bool.guard(model.is_open, "false", fn() { "true" })

  html.div([event.on_click(OnClick)], [
    html.h2([], [
      html.button(
        [
          attribute.class(
            "flex items-center justify-between w-full p-3 font-medium rtl:text-right text-gray-500 border border-b-0 border-gray-200 rounded-t-xl focus:ring-2 focus:ring-gray-200 dark:focus:ring-gray-800 dark:border-gray-700 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 gap-3",
          ),
        ],
        [html.text("Accordion title goes here")],
      ),
    ]),
    html.div([attribute.class(aria_hidden)], []),
    html_extra.view_if(
      model.is_open,
      html.div(
        [
          attribute.class(
            "p-3 border border-b-0 border-gray-200 dark:border-gray-700 dark:bg-gray-900",
          ),
        ],
        [
          html.p([attribute.class("mb-2 text-gray-500 dark:text-gray-400")], [
            html.text("This is the accordion body hahahah lmao"),
          ]),
        ],
      ),
    ),
  ])
}
