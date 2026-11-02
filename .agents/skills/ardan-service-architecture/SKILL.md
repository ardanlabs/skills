---
name: ardan-service-architecture
description: Ardan Labs Go rules. Branching (any Go code) - default-first assignment and naked switches over if/else chains; use whenever writing or refactoring conditional logic in Go. Service architecture - primitive-at-edges / strong-types-in-Business layering with toBus/fromBusResponse/toDB converters, and the ExtBusiness/Extension decorator seam for cross-cutting concerns (OTEL, logging, metrics, caching, auth); use when writing, editing, or auditing Go files under app/*, business/domain/*, business/domain/*/extensions/*, business/composite/*, or .../stores/*db, when combining Business domains (storage isolation, domain events, composites), or when adding a cross-cutting concern to a *bus package.
---

# Ardan Service Architecture

A service has three layers. Data crosses them only through named converters, and cross-cutting concerns wrap the Business layer instead of modifying it.

```
API (app/*)            Business (business/domain/*)        Storage (.../stores/*db)
primitive types  ──►   strong types (business/types/*)    ──►   native DB types
request struct    toBus<Type>          model type        toDB<Type>     db<Type> row
response struct   ◄── fromBus<Type>Response   ◄── toBus<Type>  ◄──
                      (App layer)                  (Storage layer)
                              ▲
                  extensions/<x><concern> wrap ExtBusiness
```

## Which reference to read (MUST)

`<skill>` = this file's dir. Read the matching reference before writing or auditing the code it covers. This file holds only the invariants; the references hold the rules, examples, and checklists you need to get the code right.

| Task                                                                                                            | Read                               |
|-----------------------------------------------------------------------------------------------------------------|------------------------------------|
| Any `app/*`, `business/*`, or `.../stores/*db` file: API types, models, DB rows, converters, `business/types/*` | `<skill>/references/types.md`      |
| Cross-cutting concern (OTEL, logging, metrics, caching, auth), `extensions/*`, the `ExtBusiness` seam           | `<skill>/references/extensions.md` |
| Domain events: publishing, subscribing, `<x>bus/event.go`, `business/sdk/delegate`, cross-domain reactions | `<skill>/references/events.md` |
| Conditional logic in any Go code: 1-3 branches, nested if/else, type assertions on `any`                        | `<skill>/references/branching.md`  |

Use `use-modern-go` for syntax in all of them.

## Invariants (MUST, always)

Exempt: internal helpers that never cross a boundary, `foundation/*` and `business/types/*` packages themselves, and pure intra-package refactors that don't move data between layers.

- **Primitives at the edges, strong types only in Business.** API request/response structs (`app/*`) and DB row structs (`.../stores/*db`) never contain a `business/types/*` strong type. Validated enums are stored as `string`.
- **Every boundary crossing goes through a named converter**, one per type in each direction. Never assign across a boundary directly.

  | Direction          | Layer pair         | Name                    | Returns                                                                 |
  |--------------------|--------------------|-------------------------|-------------------------------------------------------------------------|
  | primitive → strong | App → Business     | `toBus<Type>`           | `(busInput, error)`: parse + validate, accumulate `errs.FieldErrors`    |
  | strong → primitive | Business → App     | `fromBus<Type>Response` | response struct: convert each strong field with `.String()` etc.        |
  | strong → native    | Business → Storage | `toDB<Type>`            | db row struct                                                           |
  | native → strong    | Storage → Business | `toBus<Type>`           | `(busType, error)`: parse via the relevant `business/types/*` `Parse*`  |

- **The user controls the types.** Before you finalize (a commit or a review summary), state the concrete type at each affected boundary (request/response field, DB row field, converter return) and get explicit confirmation. Don't finalize on an assumed default.
- **Storage is private to its domain.**
  - `business/domain/<x>bus` may import another domain's Business package (`.../<y>bus`) and use it through its `ExtBusiness` API.
  - Nothing outside domain `<y>` imports `<y>`'s store (`.../stores/<y>db`): not another `*bus`, not another store, not an App or composite package.
  - `.../stores/<x>db` must not read, write, or join tables owned by another domain. Each table is owned by exactly one domain.
  - `app/domain/<x>app` must not import `.../<y>app`.
- **Combining domains.** Pick the mechanism that fits; when it's unclear, propose one with the reason and get the user's confirmation.
  - **Direct `*bus` import:** `<x>` needs `<y>`'s data or rules to do its own job (e.g. `homebus.Create` checks via `userbus` that the user is enabled).
  - **Domain events** (`references/events.md`): `<y>` must react to a change in `<x>` (e.g. `homebus` cleans up when a user is deleted).
  - **Coordinator:** a workflow spanning domains that none of them owns. It lives in an App package, a `business/composite/<x>bus` package, or another abstraction the user approves. An App package may import a composite. A composite must not import another composite or any App package, and domain packages never import a coordinator.
- **Transactions spanning domains.** The App layer owns the tx: it begins it and commits or rolls it back (e.g. `mid.BeginCommitRollback`). It binds each `*bus` it uses with `NewWithTx(tx)`. A tx-bound `*bus` in turn calls `NewWithTx(tx)` on every `*bus` it depends on, so the whole call tree shares one tx. A `*bus` never begins a transaction itself.
- **Cross-domain views belong to a read-only composite.** A database view joining tables of several domains (e.g. products + users) is owned by a read-only `business/composite/<x>bus` package, not by any domain. That package and its store expose queries only, read only the views they own, and never write.
- `business/types/*` and `foundation/*` are shared leaf packages: any layer may import them, and they must not import App, Business domain, or coordinator packages.
- **Wrap, never modify, core `Business`.** Cross-cutting concerns are extensions around `ExtBusiness`.
