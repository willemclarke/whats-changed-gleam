import lustre/element
import lustre/element/html

pub fn view_if(
  is_true condition: Bool,
  display dis: element.Element(msg),
) -> element.Element(msg) {
  case condition {
    True -> dis
    False -> html.text("")
  }
}
