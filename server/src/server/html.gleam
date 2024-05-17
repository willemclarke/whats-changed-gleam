import gleam/string_builder.{type StringBuilder}
import lustre/attribute.{attribute}
import lustre/element
import lustre/element/html
import wisp

pub fn serve_html() {
  wisp.response(200)
  |> wisp.html_body(app_html())
}

// instead of serving static html file, using lustre's ability
// to curate and return html on the server
fn app_html() -> StringBuilder {
  html.html([attribute("lang", "en")], [
    html.head([], [
      html.meta([attribute("charset", "utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute("content", "width=device-width, initial-scale=1"),
      ]),
      html.title([], "whats-changed"),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/client.css"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(
          "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css",
        ),
      ]),
      html.script(
        [attribute.type_("module"), attribute.src("/static/client.mjs")],
        "",
      ),
    ]),
    html.body([], [html.div([attribute.id("app")], [])]),
  ])
  |> element.to_string_builder
  |> string_builder.prepend("<!DOCTYPE html>")
}
