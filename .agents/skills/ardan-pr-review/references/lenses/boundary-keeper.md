# Boundary Keeper (types and contracts)

Review new or changed data shapes: do they make valid states easy, invalid states hard, and crossings explicit? Start from the `type`, `New*`, and converter rows in `symbols.tsv` and the `layer` column in `files.tsv`.

Primary duty: the type-boundary rule. API request/response structs use primitives; DB rows use primitive/native DB shapes; Business uses `business/types/*` strong types; every crossing goes through a named converter; nothing is assigned directly across App ↔ Business ↔ Storage. When the diff touches `app/*`, `business/domain/*`, or stores, apply `ardan-service-architecture` (`references/types.md`).

Mechanical evidence in `checks/`: `apidiff` (incompatible exported Go API changes against the base commit) and `buf-breaking` / `buf-lint` (proto wire and style). An `apidiff` or `buf-breaking` hit the ticket doesn't call for is G3 (G4 for a wire break on a published proto); cite the log line.

## Language lens

- **Go** — exported vs unexported fields, constructors and their validation, zero-value meaning, pointer vs value receivers, mutators that keep invariants, small consumer-owned interfaces, needless interfaces/generics, aliases that erase meaning, converter naming and validation, errors for invalid construction.
- **Vue/JS/TS** — `props`/`emits`: required vs optional, types, defaults, payload shapes; props immutable; internal state not leaked.
- **proto** — field numbers stable, reserved fields, optional semantics, back/forward compatibility.
- **SQL** — types, nullability, constraints, and keys encoding the same invariants as the Go strong types.

## Patrol route

1. **Per changed type** (working notes, not reported): layer, exported surface, valid states, how it's built, mutated, and crosses layers.
2. **Invariants.** Can invalid values be built directly? Validated once, at the boundary? Mutators guarded? Is the type simpler than the bug it prevents?
3. **Boundaries.** Primitives leaking into Business, strong types leaking into API/DB structs, missing `toBus<Type>` / `fromBus<Type>Response` / `toDB<Type>`, direct assignment across layers, validation with no clear owner.

## Gates

- **G4** — layer-boundary violation, constructible invalid Business state, converter bypass, or a design that can corrupt stored data.
- **G3** — exported fields or a missing constructor allow real invariant breakage.
- **G2** — invariants unclear, scattered, or weakly named.
- **G1** — naming or doc around type intent.

Prefer compile-time guarantees, weigh each suggestion's cost; a simpler type with fewer guarantees often wins.

## Extra fields

- Type: `<Name>` (layer)
- Crossing: `toBus` / `fromBusResponse` / `toDB` / none
