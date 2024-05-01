import client/components/icon
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type ToastType {
  Success(String)
  Error(String)
}

fn type_to_appearance(toast_type: ToastType) -> String {
  case toast_type {
    Success(_) -> "bg-slate-950"
    Error(_) -> "bg-red-600"
  }
}

fn view_toast(
  toast_type: ToastType,
  message: String,
  on_close: msg,
) -> Element(msg) {
  let appearance = type_to_appearance(toast_type)

  html.div(
    [
      attribute.class(
        appearance
        <> " animate-fadein text-white shadow-lg rounded-lg pointer-events-auto ring-1 ring-black ring-opacity-5 overflow-hidden",
      ),
    ],
    [
      html.div([attribute.class("p-4")], [
        html.div([attribute.class("flex items-center gap-x-3")], [
          html.p([], [html.text(message)]),
          html.button(
            [
              attribute.class("bg-transparent rounded-md inline-flex"),
              event.on_click(on_close),
            ],
            [icon.icon("x-circle-fill", icon.Alt("close-toast"), icon.Small)],
          ),
        ]),
      ]),
    ],
  )
}

pub fn region(toasts: List(Element(msg))) -> Element(msg) {
  html.div(
    [
      attribute.class(
        "z-10 fixed inset-0 flex items-start px-4 py-6 pointer-events-none",
      ),
    ],
    [
      html.div(
        [attribute.class("w-full flex flex-col items-center space-y-4")],
        toasts,
      ),
    ],
  )
}

pub fn view(toast_type: ToastType, on_close: msg) -> Element(msg) {
  case toast_type {
    Success(message) -> view_toast(Success(message), message, on_close)
    Error(message) -> view_toast(Error(message), message, on_close)
  }
}
