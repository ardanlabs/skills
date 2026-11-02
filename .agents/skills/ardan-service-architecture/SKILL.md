---
name: ardan-service-architecture
description: Ardan Labs Go rules. Branching (any Go code) - default-first assignment and naked switches over if/else chains; use whenever writing or refactoring conditional logic in Go. Service architecture - primitive-at-edges / strong-types-in-Business layering with toBus/fromBusResponse/toDB converters, and the ExtBusiness/Extension decorator seam for cross-cutting concerns (OTEL, logging, metrics, caching, auth); use when writing, editing, or auditing Go files under app/*, business/domain/*, business/domain/*/extensions/*, business/composite/*, or .../stores/*db, when coordinating work across Business domains (domain isolation), or when adding a cross-cutting concern to a *bus package.
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
| Domain events: publishing, subscribing, `business/types/event/*`, `business/sdk/delegate`, cross-domain reactions | `<skill>/references/events.md` |
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
- **Domain isolation: a domain never reaches into another domain, storage included.**
  - `business/domain/<x>bus` must not import another domain's Business package (`.../<y>bus`) or store (`.../stores/<y>db`).
  - `.../stores/<x>db` must not import another domain's Business package or store, and must not read, write, or join tables owned by another domain. Each table is owned by exactly one domain.
  - `app/domain/<x>app` must not import `.../<y>app`.
- **Cross-domain work is coordinated above the domains**, never inside one:
  - The coordinator talks to each domain only through its `*bus` package, never through its store or tables.
  - Where it lives depends on the case: an App package, a `business/composite/<x>bus` package, or another abstraction the user approves. Don't pick a default. Propose one with the reason and get the user's confirmation.
  - An App package may import a composite package. A composite must not import another composite or any App package, and domain packages never import a coordinator.
  - The coordinator owns any transaction spanning domains: it begins the tx and hands it to each domain's Business package (e.g. `NewWithTx(tx)`). A domain never starts a transaction that touches another domain's tables.
- **Cross-domain views belong to a read-only composite.** A database view joining tables of several domains (e.g. products + users) is owned by a read-only `business/composite/<x>bus` package, not by any domain. That package and its store expose queries only, read only the views they own, and never write. This is the only exception to the rule that a coordinator never touches tables directly.
- **Domains react to each other only through domain events**, never by calling each other. Event definitions live in `business/types/event/<y>event`, and handlers run inside the publisher's transaction, which is passed explicitly with the event.
- `business/types/*` and `foundation/*` are shared leaf packages: any layer may import them, and they must not import App, Business domain, or coordinator packages.
- **Wrap, never modify, core `Business`.** Cross-cutting concerns are extensions around `ExtBusiness`.
