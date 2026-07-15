---
name: business-layer-extensions
description: Use when adding a cross-cutting concern (OTEL tracing, logging, metrics, caching, auth) to a business domain, creating files under business/domain/*/extensions/*, or adding the extension seam (ExtBusiness/Extension) to a *bus package.
---

# Business Layer Extensions

Cross-cutting concerns layer onto core domain logic via a **decorator pattern**: each extension wraps an `ExtBusiness` and delegates. **Wrap, never modify core `Business`.** An extension that traces one method must still implement every other method as a plain pass-through.

Three pieces: the **seam** on the bus, the **extension** package, and the **wiring**.

## Checklist

1. **Seam exists?** Confirm `<x>bus.go` has `ExtBusiness`, `Extension`, and the reverse-apply loop in `NewBusiness`. If not, add them (Piece 1).
2. **Create** `extensions/<x><concern>/<x><concern>.go` (Piece 2).
3. **Implement EVERY `ExtBusiness` method** — wrap the relevant ones, pass the rest straight through to `ext.bus`. Missing one won't compile.
4. **Wire** into `api/services/*/main.go` in outermost-first order (Piece 3).

## Piece 1 — the seam (`<x>bus/<x>bus.go`)

```go
// ExtBusiness lists every public method an extension can wrap.
type ExtBusiness interface {
	Create(ctx context.Context, input CreateInput) (Model, error)
	// ... every other public business method
}

// Extension wraps a new layer of business logic around the existing logic.
type Extension func(ExtBusiness) ExtBusiness

func NewBusiness(log *logger.Logger, delegate *delegate.Delegate, storer Storer, extensions ...Extension) ExtBusiness {
	b := ExtBusiness(&Business{ /* ... */ })
	for i := len(extensions) - 1; i >= 0; i-- { // reverse: first-listed = outermost
		if ext := extensions[i]; ext != nil {
			b = ext(b)
		}
	}
	return b
}
```

## Piece 2 — the extension (`extensions/<x><concern>/<x><concern>.go`)

Package `<x><concern>` (e.g. `widgetotel`, `widgetlog`). Struct holds the wrapped bus plus deps; `NewExtension` returns the closure.

```go
// Package widgetotel adds OTEL to WidgetBus without changing existing logic.
package widgetotel

type Extension struct {
	bus widgetbus.ExtBusiness
}

func NewExtension() widgetbus.Extension {
	return func(bus widgetbus.ExtBusiness) widgetbus.ExtBusiness {
		return &Extension{bus: bus}
	}
}

// Wrapped method — adds the concern, then delegates.
func (ext *Extension) Create(ctx context.Context, input widgetbus.CreateWidgetInput) (widgetbus.Widget, error) {
	ctx, span := otel.AddSpan(ctx, "business.widgetbus.create")
	defer span.End()

	w, err := ext.bus.Create(ctx, input)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return w, err
	}
	span.SetStatus(codes.Ok, "")
	return w, nil
}

// Pass-through — not relevant to this concern, but REQUIRED for the interface.
func (ext *Extension) Delete(ctx context.Context, w widgetbus.Widget) error {
	return ext.bus.Delete(ctx, w)
}
```

### Metrics variant

House style: package-level singleton built in `init()` with `promauto`, `_total` counter naming, a `status` label. Record after delegating, return the original result.

```go
var metrics = struct {
	created *prometheus.CounterVec
}{
	created: promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "widgetbus_created_total",
		Help: "The total number of widget create operations.",
	}, []string{"status"}),
}

func status(err error) string {
	if err != nil {
		return "error"
	}
	return "success"
}

func (ext *Extension) Create(ctx context.Context, input widgetbus.CreateWidgetInput) (widgetbus.Widget, error) {
	w, err := ext.bus.Create(ctx, input)
	metrics.created.WithLabelValues(status(err)).Inc()
	return w, err
}
```

## Piece 3 — wiring (`api/services/*/main.go`)

Construct each extension, pass them as trailing variadic args in outermost-first order:

```go
widgetOtelExt := widgetotel.NewExtension() // first = outermost wrapper
widgetLogExt := widgetlog.NewExtension(log)
widgetBus := widgetbus.NewBusiness(log, delegate, widgetStorage, widgetOtelExt, widgetLogExt)
```

**Order matters.** `NewBusiness` applies in reverse, so first-passed = outermost (runs first in, last out). Convention: OTEL first (outermost span), then logging/metrics inside.

## Common mistakes

- **Forgetting a pass-through method** → compile error. List every `ExtBusiness` method first, then fill in.
- **Guessing wrap order** — first in the slice is outermost, not innermost.
- **Modifying core `Business`** instead of wrapping it.
- Extensions forward already-typed Business values, so boundary converters usually don't apply — but if you touch primitives or DB rows, follow `layered-architecture-types`.

Use `use-modern-go` for syntax.
