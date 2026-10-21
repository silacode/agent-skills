---
name: typescript-best-practices
description: "Apply when reading, writing, or reviewing TypeScript (.ts/.tsx), especially when designing types or function signatures or handling external data. Never lie to the compiler, and strengthen types only where a weak type forces a cast, `!`, or impossible-case throw."
disable-model-invocation: false
---

# TypeScript best practices

Two rules govern everything below:

- **Don't lie to the compiler.** No `any`, unchecked `as`, `!`, or type guard that doesn't verify its claim. If the compiler can't prove a fact, prove it: parse, narrow, or refine the model.
- **Strengthen a type only where partiality appears.** A `!`, a cast, or a "should never happen" throw marks a type that is too weak. Push that fact into the type, then stop. Don't model data more precisely than its use sites need.

Follow the repository's existing conventions (brand shape, discriminant name, schema library, logger). Don't add a dependency or refactor working code just to satisfy these rules.

| Rule | Summary |
|------|---------|
| Discriminated unions | Model mutually exclusive states as a union with one literal discriminant, not a bag of optional fields where contradictory combinations compile. If a comment explains which field combinations are valid, split the type. Fields that vary independently stay optional. |
| Constructive types | Build the shape so the illegal value can't be constructed: `readonly [T, ...T[]]` for non-empty, `[T, T][]` for pairs. Where the shape can't carry the whole invariant (a duration must be non-negative), check it once in the constructor. |
| Simplest total type | Keep `T[]` while every operation on it stays total (`sum([])` is 0). Require a non-empty type only where the loose one forces `!`, a cast, or a throw. Returning `T \| undefined` is the other honest signature. |
| Branded types | Brand a primitive (`string & { readonly __brand: "UserId" }`) when swapping two values is a realistic bug, such as IDs of different entities. Create brand values only in a validating constructor. |
| Boundary parsing | External data (JSON, RPC, IPC, env, files, database rows) is `unknown` until parsed into a domain type where it enters. Use the repository's schema library and infer the type from the schema (`z.infer`). Hand-write a guard only where no schema exists. Where boundaries go: **principle-boundary-discipline**. |
| Derived types | When a schema, generated type, or existing type owns a shape, derive from it (`Pick`, `Omit`, `Parameters`, `ReturnType`, `Awaited`, `typeof`) instead of declaring a parallel interface. |
| Narrowing | Prefer compiler narrowing (discriminant, `in`, `typeof`, `instanceof`), then a type guard that verifies every field it claims (`isX`, `hasX`), then `as` only after validation. A lying guard is worse than `as`: the bug hides behind a name that says it's safe. |
| `as` | Fine: `as const`, a brand constructor right after validation, a library typing gap with a one-line comment. Not fine: asserting a shape nobody checked. |
| `satisfies` | Checks a value against a type at compile time without widening it to that type. Literals survive only where the target type has literal types; add `as const` when you need them otherwise. It validates nothing at runtime. |
| Exhaustiveness | End a switch over a union with `const _exhaustive: never = x` so adding a variant is a compile error. |
| Object args | Pass an object when two or more arguments share a type, so a swap can't compile. Skip on hot paths (per-frame render, tokenizers, parsers). |
| Logging | No leftover debug `console.log`. Diagnostics go through the repository's logger. Console output is fine when it is the program's real output, as in a CLI. |

Examples: `references/patterns.md`.
