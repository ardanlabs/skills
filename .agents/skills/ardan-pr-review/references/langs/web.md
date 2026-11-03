# Vue / JS / TS / CSS idioms

**Tools:** an LSP if available, else `rg`/`ast-grep`. **Checks:** `jscpd` (clones); the repo's own `lint`/`typecheck`/`test` scripts arrive as extra checks when approved.

## Correctness
Reactivity (mutating props, lost reactivity on destructuring, `watch` without cleanup), leaked listeners/timers/subscriptions, unhandled async, race between overlapping requests, stale closures, `==` coercion, a11y (labels, roles, keyboard, focus).

## Failure paths
Promises and `await` caught; non-2xx handled; `catch` doesn't swallow; the UI shows failure instead of empty or stale state.

## Contracts
`props`/`emits`: required vs optional, types, defaults, payload shapes; props immutable; internal state not leaked; exported types and API client shapes match the backend contract.

## Tests
Rendering, `props`/`emits`, interactions, async and error states; mocks that hide the real request shape.

## Security
XSS (`v-html`, `innerHTML`, `dangerouslySetInnerHTML`), secrets or tokens in bundles/localStorage, open redirects, `postMessage` origin checks, new or unpinned dependencies.

## Clarity
JSDoc and component comments match the real `props`, `emits`, and behavior.
