import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

pub type Props(msg) {
  Props(trigger: List(Element(msg)), content: Element(msg))
}

pub fn view(props: Props(msg)) -> Element(msg) {
  html.div([class("group inline-flex relative")], [
    html.div([], props.trigger),
    html.div(
      [
        class(
          "hidden group-hover:block absolute left-0 top-full right-auto z-[9999] shrink-0",
        ),
      ],
      [
        html.div(
          [
            class(
              "bg-white border border-slate-300 w-full h-full rounded-md shadow-lg animate-fadein",
            ),
          ],
          [props.content],
        ),
      ],
    ),
  ])
}
