import common
import gleam/dynamic
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gluid
import kirala/bbmarkdown/html_renderer
import server/error
import sqlight

pub opaque type Connection {
  Connection(inner: sqlight.Connection)
}

const schema = "
pragma foreign_keys = on;
pragma journal_mode = wal;

CREATE TABLE IF NOT EXISTS releases (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT,
  tag_name TEXT NOT NULL,
  dependency_name TEXT NOT NULL,
  version TEXT NOT NULL,
  url TEXT NOT NULL,
  body TEXT,
  created DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
  UNIQUE (dependency_name, version)
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
    name: Option(String),
    tag_name: String,
    dependency_name: String,
    version: String,
    url: String,
    body: Option(String),
    created_at: String,
  )
}

pub fn get_releases(
  db: Connection,
  dependency: common.ClientDependency,
) -> Result(List(common.Release), error.Error) {
  let query =
    "SELECT * FROM releases WHERE dependency_name = $1 AND version >= $2 ORDER BY version desc"

  let parameters = [
    sqlight.text(dependency.name),
    sqlight.text(dependency.version),
  ]

  sqlight.query(
    query,
    on: db.inner,
    with: parameters,
    expecting: decode_db_release,
  )
  |> result.map(from_db_releases)
  |> result.map_error(error.DatabaseError)
}

pub fn insert_releases(db: Connection, releases: List(common.Release)) -> Nil {
  list.each(releases, fn(release) { insert_release(db, release) })
}

pub fn insert_release(
  db: Connection,
  release: common.Release,
) -> Result(Nil, error.Error) {
  let query =
    "
    INSERT INTO releases (id, name, tag_name, dependency_name, version, url, body)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    ON CONFLICT (dependency_name, version) DO NOTHING
  "

  let parameters = [
    sqlight.text(gluid.guidv4()),
    sqlight.nullable(sqlight.text, release.name),
    sqlight.text(release.tag_name),
    sqlight.text(release.dependency_name),
    sqlight.text(release.version),
    sqlight.text(release.url),
    sqlight.nullable(sqlight.text, release.body),
  ]

  sqlight.query(query, on: db.inner, with: parameters, expecting: Ok)
  |> result.replace(Nil)
  |> result.map_error(error.DatabaseError)
}

pub fn from_db_releases(db_releases: List(DbRelease)) -> List(common.Release) {
  db_releases
  |> list.map(fn(db_release) {
    let html_body = html_renderer.convert(option.unwrap(db_release.body, ""))

    common.Release(
      tag_name: db_release.tag_name,
      dependency_name: db_release.dependency_name,
      name: db_release.name,
      url: db_release.url,
      body: option.Some(html_body),
      version: db_release.version,
      created_at: db_release.created_at,
    )
  })
}

fn decode_db_release(
  data: dynamic.Dynamic,
) -> Result(DbRelease, List(dynamic.DecodeError)) {
  dynamic.decode8(
    DbRelease,
    dynamic.element(0, dynamic.string),
    dynamic.element(1, dynamic.optional(dynamic.string)),
    dynamic.element(2, dynamic.string),
    dynamic.element(3, dynamic.string),
    dynamic.element(4, dynamic.string),
    dynamic.element(5, dynamic.string),
    dynamic.element(6, dynamic.optional(dynamic.string)),
    dynamic.element(7, dynamic.string),
  )(data)
}
