import gleam/list
import lustre/attribute.{attribute, class}
import lustre/element/html.{i}

pub type AltText {
  Alt(String)
  Hidden
}

pub type Size {
  Small
  Large
}

fn size_to_value(size: Size) -> String {
  case size {
    Large -> "2rem"
    Small -> "1rem"
  }
}

// (thanks elektrofoni repo :D)
/// Render a Bootstrap icon with alt text.
///
/// See https://icons.getbootstrap.com/ for the icon name list. If no alt text
/// is provided, the element is set as `aria-hidden`.
pub fn icon(name: String, alt: AltText, size: Size) {
  i(
    list.flatten([
      [
        class("bi-" <> name),
        attribute.style([#("font-size", size_to_value(size))]),
        attribute("role", "img"),
      ],
      case alt {
        Alt(text) -> [attribute("title", text), attribute("aria-label", text)]
        Hidden -> [attribute("aria-hidden", "true")]
      },
    ]),
    [],
  )
}
