### gleam-whats-changed

- port of my existing whats-changed app to gleam for fun!
- [wisp](https://github.com/gleam-wisp/wisp) backend
- [lustre](https://github.com/lustre-labs/lustre) front-end

Paste a `package.json` and get back a list of releases for each dependency that are greater than the provided version.

Backed by a SQLite DB which has releases for some dependencies to try make requests faster. If a dependency isn't in the cache, requests will slow down considerably as I have to fetch the data from NPM and Github.. but they are written into DB as we go. 
