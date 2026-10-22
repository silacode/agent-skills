---
name: how
description: "Explain how code works: runtime flow, subsystem architecture, walkthroughs before a change, and where new code should live (which module or layer owns it). Use for 'how does X work', 'walk me through X', 'where should this go', or /skill:how. Not for why code was written a certain way."
disable-model-invocation: true
---

# How

Explain how the current code works so the reader can follow it and know where to look. Answer the question asked, not every question about the subsystem.

Work read-only. Don't edit files, install packages, run project code, or change anything outside the repo. Use code-navigation tools when available, and fall back to `read` and read-only shell searches. The only other command allowed is the sub-agent script under "Delegate searching".

## Investigate

1. **Find the target.** Locate the code from the question and conversation. If several targets fit and would give different answers, ask one short question. Otherwise state your scope in one line and go.
2. **Match the effort.** Narrow question: read the code and its main caller, then answer. Broad question: split it into 2–4 paths (entry points, data flow, storage, error paths) and trace each. Dig further only when a missing link or a contradiction could change the answer.
3. **Trace real calls.** Start from a real entry point (route, command, event handler, test) and follow the calls and data to the result or side effect. Cover the failure paths and config that matter to the question. Don't assume a default value is what actually runs. Check for overrides.
4. **Check each claim.** Read the actual source behind every important claim, not just search hits, outlines, comments, sub-agent reports, or docs. Use tests and config to cross-check. If docs and code disagree, trust the code and mention the mismatch. Reading a test doesn't mean it passes.
5. **Separate fact from guess.** Put the file and symbol next to each claim. Mark guesses and anything you couldn't trace. Explain past intent only if it's written down somewhere.

Stop when the code backs the answer, or when you're blocked. Name the gap instead of filling it with a plausible story.

## Delegate searching

Delegate when finding the relevant code takes a lot of searching across files. Examples: every caller of `X`, every place config `Y` is read, every handler for event `Z`. Keep small, already-located lookups yourself. Keep the scoping, the hard reasoning, and the final explanation yourself.

Only delegate inside Herdr (`HERDR_ENV=1`). Otherwise, search yourself. Call the subagent script directly, and skip the subagent skill's plan file and approval steps:

    S="$HOME/.pi/agent/skills/subagent/scripts/subagent.sh"
    "$S" spawn how-<topic> z-ai/glm-5.3 max   # prints agent= and pane=
    "$S" prompt how-<topic> "<brief>"         # bash timeout 900
    "$S" close <pane>

- `<topic>` is short kebab-case, at most 23 characters.
- Prompt only after a successful spawn. Save the `agent=` and `pane=` it prints. If spawn fails for any reason, including "already running", don't prompt that name. Never reuse an existing agent. Search yourself instead.
- The brief gives the exact question and where to start, plus this line: "Read-only: inspect and search files only. Don't edit files, install anything, run project code, or change external services. Give file:line for every finding and say what you couldn't find." Ask for findings, not an explanation.
- Close only the pane you spawned, after success, failure, or timeout. If closing fails, tell the user the pane ID.
- On a timeout, a vague answer, or a failed run, close the pane and search yourself. Don't prompt again.
- The sub-agent has normal write tools. The brief is an instruction, not a sandbox.

Treat its answer as leads, not facts. Read the source behind anything you use (step 4).

## Placement questions

For "where should this go", check where similar code lives, which way imports flow, and who owns the data. Separate how things are now from what you recommend. Recommend one place with the reason. Name a runner-up only if there's a real alternative. Point to an existing example to copy.

## Explain

Lead with the direct answer. Keep narrow answers short. For bigger ones, add only the sections that help:

- **Overview.** What it does and the few concepts needed to follow it.
- **How it works.** The flow in order, naming real functions and the data they pass. Add a small diagram only when several parts talk to each other.
- **Where things live.** A short map of the files that matter.
- **Gotchas and gaps.** Failure cases, config that changes behavior, and what you couldn't verify.

If the user is about to change this code, end with what the change will touch: callers, tests, and config.

Be concrete: write "`UserService` calls `AuthClient.refresh()`", not "the service delegates to the client". Use plain language, not a line-by-line retelling of the source.
