import client/html_extra
import gleam/bool
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Config(msg) {
  Config(title: Element(msg), body: Element(msg), on_click: msg, is_open: Bool)
}

pub fn view(config: Config(msg)) {
  let aria_hidden = bool.guard(config.is_open, "false", fn() { "true" })

  html.div([class("w-[62rem]"), event.on_click(config.on_click)], [
    html.h2([], [
      html.button(
        [
          class(
            "flex items-center justify-between w-full p-3 rtl:text-right text-gray-500 border border-b-0 border-gray-200 rounded-t-xl focus:ring-2 focus:ring-gray-200 dark:focus:ring-gray-800 dark:border-gray-700 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 gap-3",
          ),
        ],
        [config.title],
      ),
    ]),
    html.div([class(aria_hidden)], []),
    html_extra.view_if(
      is_true: config.is_open,
      display: html.div(
        [
          class(
            "max-h-96 min-h-96 flex-1 animate-fadein overflow-y-scroll p-3 border border-b-0 border-gray-200 dark:border-gray-700 dark:bg-gray-900",
          ),
        ],
        [config.body],
      ),
    ),
  ])
}
