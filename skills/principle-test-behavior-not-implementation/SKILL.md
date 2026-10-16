---
name: principle-test-behavior-not-implementation
description: "Apply when you write, change, review, or keep a test. Test through the public interface and assert the observable contract."
disable-model-invocation: false
---

# Test Behavior, Not Implementation

Test at the narrowest public boundary that exercises the behavior, called the way its users call it. Mock only true boundaries (network, clock, randomness, third-party services). A behavior-preserving refactor must not break the test.

A test must fail when the behavior it claims to verify breaks. If a no-op or a wrong result would still pass, strengthen it. Review signals: existence-only or "was called" assertions, absences with no paired presence case, expected values computed by the subject, restated constants, assertions on data the test built itself. Keep these only when they are the whole contract.

Assert required fields, absences, and invariants. Assert full snapshots or exact error text only when those details are part of the contract.

When rewriting or deleting a test, preserve the behavior it covered.

Keep relation checks across tables, type-level tests, and property-based invariants.
