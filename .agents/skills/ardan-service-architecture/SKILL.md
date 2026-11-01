---
name: ardan-service-architecture
description: Ardan Labs Go rules. Branching (any Go code) - default-first assignment and naked switches over if/else chains; use whenever writing or refactoring conditional logic in Go. Service architecture - primitive-at-edges / strong-types-in-Business layering with toBus/fromBusResponse/toDB converters, and the ExtBusiness/Extension decorator seam for cross-cutting concerns (OTEL, logging, metrics, caching, auth); use when writing, editing, or auditing Go files under app/*, business/domain/*, business/domain/*/extensions/*, or .../stores/*db, or when adding a cross-cutting concern to a *bus package.
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
- **Package imports:**
  - No cross-domain Business imports: `business/domain/<x>bus` must not import `.../<y>bus`.
  - No cross-domain App imports: `app/domain/<x>app` must not import `.../<y>app`.
  - An App package may import several Business domain packages. This is the intended place to combine domains.
  - `business/types/*` and `foundation/*` are shared leaf packages: any layer may import them, and they must not import App or Business domain packages.
- **Wrap, never modify, core `Business`.** Cross-cutting concerns are extensions around `ExtBusiness`.
