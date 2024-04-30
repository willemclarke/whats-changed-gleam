import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

// todo: add color variants
pub fn view(label: String) -> Element(msg) {
  html.span(
    [
      class(
        "flex bg-slate-800 items-center text-white text-xs font-medium me-2 px-2.5 py-0.5 rounded-md dark:bg-gray-700 dark:text-gray-300",
      ),
    ],
    [html.text(label)],
  )
}
