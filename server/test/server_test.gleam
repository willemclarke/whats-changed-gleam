import gleeunit
import gleeunit/should
import server/router

pub fn main() {
  gleeunit.main()
}

pub fn link_header_url_parsing_test() {
  // should get the `next` url
  router.url_from_link_header(
    "<https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"next\", <https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\"",
  )
  |> should.equal(Ok(
    "https://api.github.com/repositories/20929025/releases?per_page=100&page=2",
  ))

  // if malformed string or no `next` url should Error
  router.url_from_link_header(
    "; rel=\"next\", <https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\"",
  )
  |> should.equal(Error(Nil))

  router.url_from_link_header(
    "<https://api.github.com/repositories/20929025/releases?per_page=100&page=2>; rel=\"last\"",
  )
  |> should.equal(Error(Nil))
}
