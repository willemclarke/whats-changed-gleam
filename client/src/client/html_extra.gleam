import lustre/element
import lustre/element/html

pub fn view_if(bool: Bool, msg: element.Element(msg)) -> element.Element(msg) {
  case bool {
    True -> msg
    False -> html.text("")
  }
}
