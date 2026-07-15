---
name: branching-logic-flow
description: Prefer defaulting and naked switches over if/else chains for shallow branching logic in Go. Use when writing or refactoring conditional logic with 1-3 branches.
---

# Branching Logic Flow

For shallow branching (1–3 cases), prefer **defaulting** or **naked switches** over if/else chains — less nesting, no duplication, lower cognitive load.

**Apply when:** writing 1–3 branch conditionals, refactoring nested if/else, type-asserting on `any`/`map[string]any`, or when every branch assigns the same variable.

## Rule 1: Default first, override later

Initialize with the default, then override only in the special case.

```go
// ❌ every branch re-assigns result
var result map[string]any
if outer, ok := input["outer"].(map[string]any); ok {
    if inner, ok := outer["inner"].(map[string]any); ok {
        result = make(map[string]any, len(inner))
        maps.Copy(result, inner)
    } else {
        result = make(map[string]any)
    }
} else {
    result = make(map[string]any)
}

// ✅ default up front, override only the special case
result := make(map[string]any)
if outer, ok := input["outer"].(map[string]any); ok {
    if inner, ok := outer["inner"].(map[string]any); ok {
        result = make(map[string]any, len(inner))
        maps.Copy(result, inner)
    }
}
```

## Rule 2: Naked switch over if/else-if ladders

```go
// ❌
if a > b {
    result = a
} else if a == b {
    result = a + b
} else {
    result = b
}

// ✅
switch {
case a > b:
    result = a
case a == b:
    result = a + b
default:
    result = b
}
```

For simple two-way numeric comparison, prefer `min`/`max`: `result := max(a, b)`.

## When NOT to apply

- Default init is heavyweight (DB call, large alloc, external API).
- The "default" case is exceptional and should fail fast with an error.
- Nesting >3 levels — extract a function instead.
- Defaulting would mask a bug that should surface explicitly.

## Related modern Go

- `maps.Copy(dst, src)` over manual copy loops (dst must be non-nil).
- `cmp.Or(a, b, "default")` for first non-zero across fallbacks.
- Two-value form `v, ok := x.(T)` for type assertions.
