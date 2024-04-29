import gleam/list
import lustre/attribute.{attribute, class}
import lustre/element/html.{i}

pub type AltText {
  Alt(String)
  Hidden
}

// (thanks elektrofoni repo :D)
/// Render a Bootstrap icon with alt text.
///
/// See https://icons.getbootstrap.com/ for the icon name list. If no alt text
/// is provided, the element is set as `aria-hidden`.
pub fn icon(name: String, alt: AltText) {
  i(
    list.flatten([
      [class("bi-" <> name), attribute("role", "img")],
      case alt {
        Alt(text) -> [attribute("title", text), attribute("aria-label", text)]
        Hidden -> [attribute("aria-hidden", "true")]
      },
    ]),
    [],
  )
}
