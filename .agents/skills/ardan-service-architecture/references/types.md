# Type Boundaries

Part of `ardan-service-architecture`. Its SKILL.md holds the layer diagram, the converter table, the import rules, and the type-confirmation rule; this file adds the detail.

## User controls the types (MUST)

The user owns every type choice here — field types, DB column representations, converter signatures, wrappers.

- **Suggest existing types first** — a `business/types/*` strong type for Business, or a type already defined locally. Propose a new type only when nothing fits, and say why.
- Call out decisions: pointer vs value, `sql.Null*` vs wrapper, `json.RawMessage` vs typed struct, NULL/empty representation.
- If the user picks a type that diverges from these patterns, follow it and adapt the converters.

## Type boundaries (MUST)

- **API request/response** (`app/*`): primitives only — `string`, `int`, `bool`, `json.RawMessage`, `time.Time`, and slices/structs of these. Never a `business/types/*` strong type.
- **Business models** (`business/domain/*/model.go`): strong types for IDs, enums, classifications.
- **DB rows** (`.../stores/*db`): native/SQL types only — `string`, `sql.Null*`, `json.RawMessage`, `time.Time`. Never a strong type, **including validated enums — store as `string`.**

## Foundation types are wrapped, not used directly (MUST)

`foundation/*` types must not appear directly in `business/types/*` aggregates or Business models. Define a `business/types` wrapper and convert via `toFoundation<T>` / `fromFoundation<T>` at the foundation-client boundary. The wrapper may store the foundation value in an unexported field and delegate (un)marshaling; aggregates reference the wrapper, never the foundation type.

## Pointer types (avoid)

Prefer non-pointer types at every layer. Reach for a pointer only when nothing else expresses the requirement, and say why.

- Nullable columns: prefer value types that model absence — `sql.Null*` for scalars; for nullable `JSONB`, a small `sql.Scanner`/`driver.Valuer` wrapper around `json.RawMessage` that scans NULL into the empty value. Not `*json.RawMessage`, and not a `COALESCE(col, CAST('null' AS jsonb))` patch (it turns NULL into JSON `null` and defeats `omitempty`).
- Before a wrapper or pointer, consider reshaping the data so the case can't arise, and offer it as the user's call:
  - **Storage:** `NOT NULL DEFAULT '{}'::jsonb` (or `'null'::jsonb`) never yields a NULL to scan (schema/migration change).
  - **App request:** if field absence is the only reason for a pointer/wrapper, make the field required (validate in `toBus<Type>`) or default it to zero, keeping it a plain primitive.
  - Trade-off either way: a NOT NULL/forced default collapses "unset" and "empty" into one value — may or may not be acceptable.
- Don't add a pointer field/param/return to signal optionality when a zero value, `sql.Null*`, or explicit "is set" flag does the job.
- If a pointer genuinely is the only option, surface it in the type confirmation before writing it.

## Converter rules (MUST)

- **All parsing/validation happens in App-layer `toBus<Type>`.** Parse each primitive into its strong type; on failure `fieldErrors.Add(field, err)` and return `errs.FieldErrors`. The request struct carries only strings — no strong types, no strong-type validation there.
- `fromBus<Type>Response` converts explicitly (`id.String()`, `cls.String()`). Never rely on a strong type's `MarshalJSON` to hide a leak — the response field must already be primitive.
- Storage `toBus<Type>` validates natives back into strong types and returns an error (`<subpkg>.Parse<Type>(row.ID)`); `toDB<Type>` calls `.String()` to flatten.
- One converter pair per persisted type, per CRUD op that needs it (Create/Get/List/Update/Delete).

## Constructor naming: Parse / MustParse only (MUST)

Strong types in `business/types/*` MUST expose constructors as `Parse<Type>` and `MustParse<Type>` — never `New<Type>` / `MustNew<Type>`.

- `Parse<Type>(s string) (<Type>, error)` — parses + validates; returns an error on invalid input. Converters call this.
- `MustParse<Type>(s string) <Type>` — panics; reserve for tests and package-level vars with known-good constants, never request-derived data.
- **Reject `New*` / `MustNew*`.** Rename to `Parse*` / `MustParse*` and update call sites, including typed variants (`New<Type>FromUUID` → `Parse<Type>FromUUID`). Keep a `New*` form only if the user gives a concrete reason; when in doubt, ask.

## Example — App layer

```go
// Request carries only primitives.
type CreateWidgetRequest struct {
	Name    string `json:"name"`
	OwnerID string `json:"owner_id"` // NOT a strong OwnerID type
}

// toBus parses + validates here.
func toBusCreateWidget(req CreateWidgetRequest) (widgetbus.CreateWidgetInput, error) {
	var fieldErrors errs.FieldErrors

	ownerID, err := types.ParseOwnerID(req.OwnerID)
	if err != nil {
		fieldErrors.Add("owner_id", err)
	}
	if len(fieldErrors) > 0 {
		return widgetbus.CreateWidgetInput{}, fieldErrors
	}

	return widgetbus.CreateWidgetInput{
		Name:    strings.TrimSpace(req.Name),
		OwnerID: ownerID,
	}, nil
}

// fromBus converts strong -> primitive explicitly.
func fromBusCreateWidgetResponse(w widgetbus.Widget) CreateWidgetResponse {
	return CreateWidgetResponse{
		ID:      w.ID.String(),
		OwnerID: w.OwnerID.String(),
		Name:    w.Name,
	}
}
```

## Example — Storage layer

```go
type dbWidget struct {
	ID      string `db:"id"`       // native, not a strong WidgetID type
	OwnerID string `db:"owner_id"`
}

func toDBWidget(w widgetbus.Widget) dbWidget {
	return dbWidget{ID: w.ID.String(), OwnerID: w.OwnerID.String()}
}

func toBusWidget(row dbWidget) (widgetbus.Widget, error) {
	id, err := types.ParseWidgetID(row.ID)
	if err != nil {
		return widgetbus.Widget{}, fmt.Errorf("parse widget id: %w", err)
	}
	// ... parse remaining natives into strong types ...
	return widgetbus.Widget{ID: id /* ... */}, nil
}
```

Names above are illustrative — not real codebase symbols.

## Conformance checklist

- [ ] No `business/types` strong type in an API request/response struct.
- [ ] No `business/types` strong type in a DB row struct (validated enums as `string`).
- [ ] Each crossing has its named function: `toBus<Type>`, `fromBus<Type>Response`, `toDB<Type>`, storage `toBus<Type>`.
- [ ] App-layer `toBus<Type>` parses + validates and returns `errs.FieldErrors`.
- [ ] `fromBus<Type>Response` converts every strong field explicitly (no `MarshalJSON` reliance).
- [ ] Storage `toBus<Type>` returns an error and parses natives into strong types.
- [ ] Constructors named `Parse<Type>` / `MustParse<Type>`, not `New*` (unless user-justified).
- [ ] No pointer introduced where a value, `sql.Null*`, or "is set" flag would do.
- [ ] Reused an existing `business/types/*` or local type where one fit.
- [ ] No cross-domain Business, store, or App imports; no store reads, writes, or joins another domain's tables.
- [ ] Cross-domain work lives in a user-confirmed coordinator (App, `business/composite/<x>bus`, or other) that uses only `*bus` APIs and owns any cross-domain transaction.
- [ ] Any view joining several domains' tables is owned by a read-only `business/composite/<x>bus` that only queries it.
- [ ] No `foundation/*` type appears directly in an aggregate or model; each wrapped via `toFoundation`/`fromFoundation`.
- [ ] User confirmed concrete types at each boundary before finalizing.

