---
name: principle-boundary-discipline
description: "Apply when wiring validation, error handling, or framework adapters. Parse and validate at system boundaries (CLI, config, network, external APIs, storage), trust parsed types inside, keep authorization and business-rule checks where operations happen, and keep business logic in pure functions."
disable-model-invocation: false
---

# Boundary Discipline

Parse, validate, and handle errors where data enters the system. Inside, trust the parsed types. Business logic lives in pure functions, and the shell around them is thin and mechanical.

**Why:** Scattered shape checks are noisy, redundant, and give a false sense of safety. Logic kept out of framework wiring can be tested without the framework.

**At boundaries** (CLI args, config, env, network, external APIs, files, database rows):
- Parse raw input into domain types, return errors, and handle failure defensively.
- Persisted data outlives the code that wrote it: version it and handle parse failures.

**Inside:** typed data and error propagation. Don't re-check a shape, type, or null that the boundary already established.

**Not redundant:** checks on facts that can change after parsing or depend on who is asking. Keep authorization, business rules (sufficient balance, valid state transition), and concurrency checks where the operation happens.

**Across the boundary:** expose domain concepts, not transport, storage, framework, or wire types. Keep general mechanism inside and special-purpose policy at the edge.

**Code organization:**
- Business logic in pure functions with no framework dependencies.
- Parsers: pure transforms from raw input to typed state.
- Renderers and serializers: typed state in, output out.

**The tests:**
- "Is this a shape check on data that isn't crossing a boundary right now?" If yes, it's redundant.
- "Can this be a pure function that the shell just calls?" If yes, extract it.
