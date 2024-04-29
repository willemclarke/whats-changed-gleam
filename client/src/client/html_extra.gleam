import lustre/element
import lustre/element/html

pub fn view_if(
  is_true condition: Bool,
  element ele: element.Element(msg),
) -> element.Element(msg) {
  case condition {
    True -> ele
    False -> html.text("")
  }
}
