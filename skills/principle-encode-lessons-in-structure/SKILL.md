---
name: principle-encode-lessons-in-structure
description: "Apply when you catch yourself writing the same instruction a second time, or notice a recurring correction. Encode the rule as a type, lint, test, runtime check, or script instead of more text."
disable-model-invocation: false
---

# Encode Lessons in Structure

When the same correction comes up a second time, encode it so the mistake can't recur silently: a type, a lint rule, a test, a runtime check, or a script. Use the cheapest mechanism that catches it. Add new tooling only when it costs less to maintain than the mistakes it prevents.

Once the structural fix exists, delete the repeated instruction; it was the symptom. Keep at most a one-line reason next to the rule so nobody removes it as noise.

If the lesson needs judgment and can't be encoded, make the instruction more prominent and add an example of the failure.
