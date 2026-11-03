# Go idioms

**Tools:** `gopls` MCP (`go_symbol_references`, `go_search`, `go_file_context`), else `gopls`/`go doc`, then `rg`. Skills: `use-modern-go` on every `.go` file; `ardan-service-architecture` on files with a `layer` (`app`, `business`, `storage`, `foundation`) — `references/types.md` for boundaries, `branching.md` for conditionals, `events.md` for domain events, `extensions.md` only when extension wiring is touched.

**Checks** (`checks/summary.tsv`; package-wide tools report on whole packages, only in-scope hits count):
- `go-build`, `go-vet`, `staticcheck`, `golangci-lint` — each hit is a finding at the Gate its effect warrants. (For an untrusted change `golangci-lint` runs with `--no-config`: default linters, since the repo's config can load custom linter plugins.)
- `checklocks` — a violation of an existing `+checklocks`/`+checkatomic` annotation is a data race (G4). "may require checklocks annotation for X" names the lock guarding those fields: verify in-scope code holds it on every access.
- `nilaway` — candidate nil dereferences; confirm the nil flow before reporting, else Open check.
- `go-fix` — modernizer diff on in-scope lines: G1 (G2 where `use-modern-go` makes it a rule). `gofmt`, `go-mod-tidy` — G2.
- `apidiff` — incompatible exported-API change: confirm every caller was updated; an unannounced break of a library package is G3 (Boundary Keeper).
- `errcheck` — a finding only when the lost error matters (failed write, commit, close of a written file); a dropped `Close` on a read-only body is G1 at most.
- `deadcode` — unreachable functions; an exported function of a library package may be public API.

## Correctness
`context` stored or not propagated, cancellation ignored; nil derefs; slice/map bounds; data races; leaked goroutines, rows, bodies, files; wrong transaction scope; surprising zero values. Architecture: primitives at API/DB edges, strong `business/types/*` in Business, crossings via `toBus<Type>` / `fromBus<Type>Response` / `toDB<Type>`, cross-cutting concerns via the `ExtBusiness`/`Extension` seam, shallow branching.

## Failure paths
Errors checked, wrapped with `%w`, matched with `errors.Is/As`, not `_`-discarded when they matter; overwritten before use; zero value returned after failure; `defer` cleanup failures that matter; goroutines with no error path; row-scan and iterator errors.

## Contracts
The type-boundary rule: API request/response structs use primitives; DB rows use primitive/native DB shapes; Business uses `business/types/*` strong types; every crossing goes through a named converter; nothing is assigned directly across App ↔ Business ↔ Storage. Storage is private to its domain: a `*bus` may import another domain's `*bus`, but nothing outside domain `<y>` imports `<y>`'s store or touches its tables; the App layer owns cross-domain transactions and every tx-bound `*bus` passes the tx to the `*bus` packages it depends on.
- Check: primitives leaking into Business, strong types in API/DB structs, missing converters, validation with no owner; imports of another domain's store; SQL in `<x>db` reading or joining another domain's tables; a `*bus` beginning a transaction, or `NewWithTx` not rebinding a dependency; domain events defined outside the publisher's `<y>bus/event.go`, handlers not binding to the passed tx, external side effects inside a handler.
- Types: exported vs unexported fields, constructors and their validation, zero-value meaning, pointer vs value receivers, mutators keeping invariants, small consumer-owned interfaces, needless interfaces/generics, aliases that erase meaning.
- G4: layer-boundary or storage-isolation violation, constructible invalid Business state, converter bypass. Extra fields: `Type: <Name> (layer)`, `Crossing: toBus | fromBusResponse | toDB | none`.

## Tests
Table-driven tests with named subtests; `errors.Is/As` on error paths; negative, validation, boundary, cancellation, timeout, transaction and store-failure cases; HTTP request/response; converters; strong-type parsing. For a maintainer PR tests ran with `-race`: a `WARNING: DATA RACE` whose stack touches in-scope code is G4 — quote the two conflicting frames; prove a point with one `go test -run TestX ./pkg`. Otherwise `go test` didn't run.

## Security
`gosec`, `govulncheck` rows; trace taint from request/env/file to sink with `gopls`; `database/sql` string building, `exec.Command` with a shell, `html/template` vs `text/template`, `InsecureSkipVerify`, `math/rand` for tokens.

## Clarity
Exported identifiers documented where package style requires, starting with the identifier's name; comments on converters and strong types match the layer rules. Branch chains → default-first assignment or a naked switch (`branching.md`). Don't flatten layer converters or extension seams.
