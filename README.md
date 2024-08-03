### gleam-whats-changed

- port of my existing whats-changed app to gleam for fun!
- [wisp](https://github.com/gleam-wisp/wisp) backend
- [lustre](https://github.com/lustre-labs/lustre) front-end

Paste a `package.json` and get back a list of releases for each dependency that are greater than your provided version.

Backed by a SQLite DB which has releases for some dependencies to try make requests faster. If a dependency isn't in the cache, requests will slow down considerably (some package.json's have taken like 40 seconds for me) as I have to fetch the data from NPM and then paginate Github for the releases.. but they are written into DB as we go -> so for each new request, the subsequent request will faster!!. For convenience, I ignore any dependencies prefixed with `@types/` as they don't really add much value IMO.


Preview images:
<img width="1440" alt="image" src="https://github.com/user-attachments/assets/1a529da8-d6e1-4369-b9d2-f83efd89bebb">


<img width="1440" alt="image" src="https://github.com/user-attachments/assets/0d06e385-a45f-4c07-9ae1-55d451489607">


