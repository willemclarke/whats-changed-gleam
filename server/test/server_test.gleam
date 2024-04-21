import gleeunit
import gleeunit/should
import server/github

pub fn main() {
  gleeunit.main()
}

pub fn version_from_tag_name_test() {
  github.version_from_tag_name("v8.57.0")
  |> should.equal("8.57.0")

  github.version_from_tag_name("plugin-legacy@5.3.1")
  |> should.equal("5.3.1")

  github.version_from_tag_name("v1.2.3-alpha.4")
  |> should.equal("1.2.3")

  github.version_from_tag_name("v9.0.0-rc.0")
  |> should.equal("9.0.0")

  github.version_from_tag_name("v1.0.0")
  |> should.equal("1.0.0")

  github.version_from_tag_name("v1.11.3")
  |> should.equal("1.11.3")
}

pub fn link_header_url_parsing_test() {
  // should get the `next` url
  github.url_from_link_header(
    "<https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"next\", <https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\"",
  )
  |> should.equal(Ok(
    "https://api.github.com/repositories/20929025/releases?per_page=100&page=2",
  ))

  // if malformed string or no `next` url should Error
  github.url_from_link_header(
    "; rel=\"next\", <https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\"",
  )
  |> should.equal(Error(Nil))

  github.url_from_link_header(
    "<https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\"",
  )
  |> should.equal(Error(Nil))
}
