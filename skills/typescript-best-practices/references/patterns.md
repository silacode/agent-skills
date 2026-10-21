# TypeScript patterns

Examples for the rules in `SKILL.md`. Every snippet type-checks under `strict` and `noUncheckedIndexedAccess`.

## Discriminated unions

```ts
// Don't: contradictory states compile ({ loading: true, error: "x" })
type DiffState = { loading: boolean; diff?: GitDiff; error?: string };

// Do: only valid states exist
type DiffState =
  | { kind: "loading" }
  | { kind: "ready"; diff: GitDiff }
  | { kind: "error"; error: string };
```

Fields that vary independently stay optional:

```ts
type SearchOptions = { limit?: number; caseSensitive?: boolean };
```

## Constructive types

```ts
type NonEmpty<T> = readonly [T, ...T[]];

const isNonEmpty = <T>(xs: readonly T[]): xs is NonEmpty<T> => xs.length > 0;

function first<T>(xs: NonEmpty<T>): T {
  return xs[0];
}
```

Keep the `readonly`. A mutable `[T, ...T[]]` still allows `.pop()`, which empties it while the type says it can't be empty.

A shape can't carry every invariant. Start plus duration rules out `end < start` only if the duration is non-negative, so check that once in the constructor:

```ts
type TimeRange = { readonly start: Date; readonly durationMs: number };

function timeRange(start: Date, durationMs: number): TimeRange {
  if (!Number.isFinite(durationMs) || durationMs < 0) {
    throw new RangeError(`Invalid duration: ${durationMs}`);
  }
  return { start, durationMs };
}
```

Code that builds a `TimeRange` literal elsewhere skips this check. Brand the type only if that actually happens.

## Simplest total type

```ts
// Total on a plain array: an empty list sums to 0
const sum = (xs: readonly number[]) => xs.reduce((a, b) => a + b, 0);
```

```ts
// Don't: partiality smuggled past the compiler
function newestSession(sessions: Session[]): Session {
  return sessions[0]!;
}

// Do: demand a non-empty input
function newestSession(sessions: NonEmpty<Session>): Session {
  return sessions[0];
}

// ...or admit the empty case
function newestSession(sessions: readonly Session[]): Session | undefined {
  return sessions[0];
}
```

## Branded types

```ts
type UserId = string & { readonly __brand: "UserId" };

function parseUserId(input: string): UserId {
  if (!/^u_[a-z0-9]+$/.test(input)) throw new Error(`Invalid user id: ${input}`);
  return input as UserId; // the sanctioned cast: right after validation
}
```

## Boundary parsing

```ts
import { z } from "zod";

// Don't: a parallel interface plus a cast, nothing checked
interface User { id: string; role: "admin" | "member" }
const user = JSON.parse(body) as User;

// Do: one schema owns validation, and the type is inferred from it
const User = z.object({ id: z.string(), role: z.enum(["admin", "member"]) });
type User = z.infer<typeof User>;
const user = User.parse(JSON.parse(body));
```

Use `safeParse` when failure is an expected branch. When the type must come first, annotate the schema with it so the compiler rejects a schema that proves less:

```ts
import { z } from "zod";

type Point = { x: number; y: number };
const Point: z.ZodType<Point> = z.object({ x: z.number(), y: z.number() });
```

## Derived types

```ts
// Don't: a parallel shape that drifts from the generated type
type CheckSummary = { totalCount: number; checks: { name: string; status: string }[] };

// Do
type CheckSummary = Pick<ChecksResponse, "totalCount" | "checks">;
```

## Narrowing and exhaustiveness

```ts
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; width: number; height: number };

function area(s: Shape): number {
  switch (s.kind) {
    case "circle":
      return Math.PI * s.radius ** 2;
    case "rect":
      return s.width * s.height;
    default: {
      const _exhaustive: never = s;
      return _exhaustive;
    }
  }
}
```

In a switch that returns nothing, follow the binding with `void _exhaustive;` so unused-variable checks stay quiet.

With no discriminant, `in` narrows:

```ts
type Contact = { email: string } | { phone: string };

const address = (c: Contact) => ("email" in c ? c.email : c.phone);
```

## Type guards

```ts
// Don't: claims a full User, checks one field
function isUser(x: unknown): x is User {
  return typeof x === "object" && x !== null && "id" in x;
}

// Do: verify every field the type claims (or use the schema's safeParse)
function isPoint(x: unknown): x is { x: number; y: number } {
  return (
    typeof x === "object" && x !== null &&
    "x" in x && typeof x.x === "number" &&
    "y" in x && typeof x.y === "number"
  );
}
```

## Removing an `as`

Find out why the compiler can't infer the type:

- Missing discriminant: add one.
- Source type too wide (such as `Record<string, unknown>`): narrow it.
- Untyped boundary: parse with the schema that owns the shape.
- Genuinely inexpressible: use a brand constructor or `satisfies`.

## `satisfies`

```ts
type Config = { theme: "dark" | "light"; cols: number };

// Don't: `as` accepts the missing `cols`
const a = { theme: "dark" } as Config;

// Do: checked, and `theme` keeps the literal type "dark"
const b = { theme: "dark", cols: 3 } satisfies Config;
```

If `theme` were typed `string`, `b.theme` would be `string`. Add `as const` when you need the literal anyway.

## Object args

```ts
// Don't: four numbers in a row; a swap still compiles
openFile(uri, 10, 1, 10, 1);

// Do
openFile({ uri, selection: { startLine: 10, startColumn: 1, endLine: 10, endColumn: 1 } });
```
