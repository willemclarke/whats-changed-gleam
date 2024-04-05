import sqlight
import server/error
import gleam/result
import gleam/dynamic
import server/github
import gluid

pub opaque type Connection {
  Connection(inner: sqlight.Connection)
}

const schema = "
pragma foreign_keys = on;
pragma journal_mode = wal;

CREATE TABLE IF NOT EXISTS releases (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  tag_name TEXT NOT NULL,
  version TEXT NOT NULL,
  release_url TEXT NOT NULL,
  created DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
  UNIQUE (name, tag_name)
);
"

pub fn connect(database: String) -> Connection {
  let assert Ok(db) = sqlight.open(database)
  let assert Ok(_) = sqlight.exec(schema, db)
  Connection(db)
}

pub type DbRelease {
  DbRelease(
    id: String,
    name: String,
    tag_name: String,
    version: String,
    url: String,
    created_at: String,
  )
}

pub fn insert_release(
  db: Connection,
  release: github.Release,
) -> Result(Nil, error.Error) {
  let query =
    "
    INSERT INTO releases (id, name, tag_name, version, url)
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (name, tag_name) DO NOTHING
  "

  let parameters = [
    sqlight.text(gluid.guidv4()),
    sqlight.text(release.dependency_name),
    sqlight.text(release.tag_name),
    sqlight.text(release.display_version),
    sqlight.text(release.url),
  ]

  let _ =
    sqlight.query(query, on: db.inner, with: parameters, expecting: Ok)
    |> result.map_error(error.DatabaseError)

  Ok(Nil)
}

fn decode_db_release() -> fn(dynamic.Dynamic) ->
  Result(DbRelease, List(dynamic.DecodeError)) {
  dynamic.decode6(
    DbRelease,
    dynamic.field("id", dynamic.string),
    dynamic.field("name", dynamic.string),
    dynamic.field("tag_name", dynamic.string),
    dynamic.field("version", dynamic.string),
    dynamic.field("url", dynamic.string),
    dynamic.field("created_at", dynamic.string),
  )
}
