---
name: use-modern-go
description: Apply modern Go syntax guidelines based on the project's Go version. Use whenever writing, editing, or reviewing Go (.go) code — not only when explicitly asked for guidelines.
---

# Modern Go Guidelines

## Detected Go Version

!`grep -rh "^go " --include="go.mod" . 2>/dev/null | cut -d' ' -f2 | sort | uniq -c | sort -nr | head -1 | xargs | cut -d' ' -f2 | grep . || echo unknown`

## How to Use

Use ONLY the version above — do not detect it yourself. Everything under **Always available** assumes the Go 1.22 floor and is safe on any currently supported Go version; gate anything newer on the detected version.

- **Version detected:** Say "This project is using Go X.XX, so I'll use modern Go features up to that version. Let me know to target a different one." Do not list features or ask for confirmation.
- **"unknown":** Say "Could not detect Go version." Then AskUserQuestion: "Which Go version should I target?" → [1.22] / [1.23] / [1.24] / [1.25] / [1.26].

When writing Go: use every feature up to the target, prefer modern built-ins/packages (`slices`, `maps`, `cmp`) over legacy patterns, never use features newer than the target.

## Modernizing Existing Files

If the **installed toolchain** is Go 1.26+, run `go fix` on the target package(s) **before reading any file** — it mechanically applies most rewrites below (range-over-int, `min`/`max`, `any`, `strings.Cut`, `fmt.Appendf`, `maps.*`).

```bash
go version                       # gate on installed toolchain
go fix -diff ./path/...          # preview (unflagged form writes in place)
go fix ./path/...                # apply; run twice — one fix enables another
go fix ./path/...
go build ./path/... && go test ./path/...   # verify
```

Then read the post-fix files and apply remaining manual modernizations. Do not Read a file before `go fix` runs on its package.

Caveats:

- Only fixes when the declared Go version permits it (`go 1.X` in `go.mod` / `//go:build go1.X`).
- Skips generated files (per `//go:generate`) — fix the generator.
- Analyzes one build config; re-run per `GOOS`/`GOARCH` combo for tagged code.
- Resolves syntactic conflicts, not semantic ones (e.g. now-unused vars) — post-fix compile errors are normal and need manual fixes.
- `go tool fix help` lists fixers; disable one with `-name=false` (e.g. `-minmax=false`).
- When committing, keep automated `go fix` changes in their own commit, separate from manual modernizations.

If the installed toolchain is older than Go 1.26, skip `go fix` and apply the features below manually.

---

## Features

### Always available (Go 1.22 floor)

Standard library:
- `time.Since(start)` / `time.Until(deadline)` over manual `.Sub`.
- `errors.Is(err, target)` over `==` (handles wrapping); `errors.Join(e1, e2)` to combine.
- `any` over `interface{}`.
- `strings.Cut` / `bytes.Cut`; `strings.CutPrefix` / `CutSuffix`.
- `strings.Clone` / `bytes.Clone`.
- `fmt.Appendf(buf, ...)` over `[]byte(fmt.Sprintf(...))`.
- Type-safe atomics: `atomic.Bool`, `atomic.Int64`, `atomic.Pointer[T]` over `atomic.StoreInt32` etc.
- `context.WithCancelCause` + `context.Cause(ctx)`; `context.AfterFunc`, `context.WithTimeoutCause`, `context.WithDeadlineCause`.

Built-ins & generics:
- `min(a, b)` / `max(a, b)` over if/else.
- `clear(m)` / `clear(s)` to empty a map / zero a slice.
- `for i := range n` over `for i := 0; i < n; i++`. Loop variables are per-iteration — safe to capture in goroutines.
- `cmp.Or(a, b, "default")` returns first non-zero — e.g. `name := cmp.Or(os.Getenv("NAME"), "default")`.
- `reflect.TypeFor[T]()` over `reflect.TypeOf((*T)(nil)).Elem()`.

`slices`:
- `Contains`, `Index`, `IndexFunc` over manual loops.
- `Sort` / `SortFunc(s, func(a, b T) int { return cmp.Compare(a.X, b.X) })`.
- `Max`, `Min`, `Reverse`, `Compact` (dedupes consecutive), `Clip`, `Clone`.

`maps`: `Clone`, `Copy(dst, src)`, `DeleteFunc(m, pred)`.

`sync`: `sync.OnceFunc(fn)`, `sync.OnceValue(fn)` over `sync.Once` + wrapper.

`net/http`: method+path patterns — `mux.HandleFunc("GET /api/{id}", h)`, `r.PathValue("id")`.

### Go 1.23+

- `maps.Keys(m)` / `maps.Values(m)` return iterators.
- `slices.Collect(iter)` to build a slice; `slices.Sorted(iter)` to collect+sort.

```go
keys := slices.Collect(maps.Keys(m))
sortedKeys := slices.Sorted(maps.Keys(m))
for k := range maps.Keys(m) { process(k) }
```

- `time.Tick` is safe to use freely — the GC reclaims unreferenced tickers without `Stop`. No reason to prefer `NewTicker` when `Tick` will do.

### Go 1.24+

- `t.Context()` over `context.WithCancel(context.Background())` in tests. Always.
- `omitzero` over `omitempty` in JSON tags — always for `time.Duration`, `time.Time`, structs, slices, maps (`omitempty` doesn't work for these).
- `for b.Loop()` over `for i := 0; i < b.N; i++` in benchmarks.
- `strings.SplitSeq` / `FieldsSeq` (and `bytes.*`) over `strings.Split` when iterating in a for-range.

```go
for part := range strings.SplitSeq(s, ",") { process(part) }
```

### Go 1.25+

- `wg.Go(fn)` over `wg.Add(1)` + `go func() { defer wg.Done(); ... }()`.

```go
var wg sync.WaitGroup
for _, item := range items {
    wg.Go(func() { process(item) })
}
wg.Wait()
```

### Go 1.26+

- `new(val)` over `x := val; &x` — returns a pointer to any value. Type inferred: `new(0)` → `*int`, `new(true)` → `*bool`, `new(T{})` → `*T`. No redundant casts (`new(0)`, not `new(int(0))`). Common for pointer struct fields.

```go
cfg := Config{Timeout: new(30), Debug: new(true)}
```

- `errors.AsType[T](err)` over `errors.As(err, &target)`.

```go
if pathErr, ok := errors.AsType[*os.PathError](err); ok { handle(pathErr) }
```
