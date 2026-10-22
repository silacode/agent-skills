---
name: sharpen
description: "Sharpen a task before starting: find the real goal and the expert approach, keep explicit requirements, ask only blocking questions, and pick an independent check to run after the work. Use before multi-step or ambiguous tasks, or for /sharpen."
disable-model-invocation: false
---

Before starting, think through these quietly, then do the work:

1. **Goal.** What does the user actually want? Solve that, not just the literal words.
2. **Approach.** How would a top expert do this? What would they look at first, and how would they work? Prefer the simplest approach that fully works.
3. **Requirements.** Keep everything the user explicitly asked for. If one seems wrong, say so and suggest the change. Never drop it silently. Don't add scope the goal doesn't need.
4. **Questions.** Ask only if a wrong guess would change the result, there's no safe default, and you can't find the answer by looking. Ask up to 3 questions together. Ask again only if a new blocker needs the user's decision. Otherwise pick a default, state it in one line, and go.
5. **Check.** Before starting, pick a check that doesn't rely on your own judgment: a relevant test, reproducing the bug before and after, or comparing the output with its source. After the work, run it.

At the end, say what you couldn't check. Don't explain this framing or hand back a rewritten prompt. For trivial tasks, skip the planning and unnecessary questions, but not the requirements or the check.
