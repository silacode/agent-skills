---
name: subagent
description: "Plan a task, get user approval, then delegate execution to a Herdr pi sub-agent running openai/gpt-6-sol at xhigh thinking; verify its work independently and either close it or send fix-up instructions (max 3 rounds). YOLO mode (leading `yolo` argument) answers the sub-agent's questions instead of relaying them. Use when the user asks to delegate, hand off, or run a task through a sub-agent. Requires HERDR_ENV=1."
---

# Sub-agent: plan, delegate, verify, close

You are the planner and the reviewer. The sub-agent is the implementer. Never trust its report; verify the tree yourself.

Herdr CLI details live in `~/.pi/agent/skills/herdr/SKILL.md`. Read it if a command below fails.

## Mode

If the first word of the arguments is `yolo` (any case), **YOLO mode** is on and the rest is the task. Otherwise, normal mode.

YOLO changes only how sub-agent questions are handled after handoff (step 3a). Planning questions and plan approval are the same in both modes.

## 0. Preflight

```bash
test "${HERDR_ENV:-}" = 1 || echo "NOT IN HERDR"
```

Not in Herdr: say so and stop.

## 1. Plan

1. Read the task and the code it touches. Trace the real flow. Read the repo's `AGENTS.md` files for the area.
2. Ambiguous requirement you cannot default: ask the user now (one `ask_user_question` call), not after spawning.
3. Write the plan to `<repo-root>/plans/<slug>.md` (`git rev-parse --show-toplevel`). `<slug>` is short kebab-case. Sections:
   - **Goal**: one paragraph.
   - **Context**: exact files, symbols, and the relevant `AGENTS.md`/skills the implementer must read.
   - **Steps**: numbered, concrete, file-level.
   - **Acceptance criteria**: numbered, each one checkable by reading the diff or running a command.
   - **Verification**: exact commands to run (from the repo's guides / `package.json`).
   - **Out of scope / constraints**: what not to touch. Default: do not commit, push, or open PRs; do not edit `AGENTS.md`; do not weaken checks or update baselines.
4. Show the user a short summary plus the path. **Stop and wait for approval.** Apply requested edits to the plan file before continuing.

## 2. Spawn

Pick `right` for a wide caller pane, `down` for a narrow one (`herdr pane layout --pane "$HERDR_PANE_ID"`). Name: `sub-<slug>`, matching `[a-z][a-z0-9_-]{0,31}`.

```bash
PANE=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r .result.pane.pane_id)
# New shell may not be at its prompt yet (agent_pane_busy), so retry
for i in $(seq 30); do
  OUT=$(herdr agent start sub-<slug> --kind pi --pane "$PANE" --timeout 120000 -- --model openai/gpt-6-sol --thinking xhigh --exclude-tools ask_user_question 2>&1)
  echo "$OUT" | grep -q agent_pane_busy || break; sleep 1
done; echo "$OUT"
```

Any other error: show it, close `$PANE`, stop.

`--exclude-tools ask_user_question` is required: that questionnaire UI is not reported to Herdr as `blocked`, so a wait would hang on it. Questions must arrive as plain text instead (step 3a).

Remember `PANE` and the agent name for the rest of the session. Do not edit files in this worktree while the sub-agent is working.

## 3. Delegate

```bash
herdr agent prompt sub-<slug> "Execute the plan in plans/<slug>.md exactly. Read every file and guide it lists first. Stay in scope. Run its Verification commands. Finish with a report: DONE or NOT DONE, files changed, each acceptance criterion with pass/fail, checks run with outcomes, anything skipped and why. If you need a decision the plan does not answer, stop and end your turn with one line per question starting with QUESTION:, listing the options you see." --wait --timeout 3600000
```

Give the bash tool a `timeout` larger than the herdr timeout (e.g. 3700 s). Route the result:

- `timeout` / `agent_prompt_stalled`: run `herdr agent get sub-<slug>`. Still `working`: `herdr agent wait sub-<slug> --timeout 3600000`. Never re-send the prompt blindly.
- `idle` / `done` / `blocked`: run `herdr agent read sub-<slug> --source recent-unwrapped --lines 120`. If it contains `QUESTION:` or a blocked UI, go to step 3a. Otherwise go to step 4.

### 3a. Sub-agent questions

**Normal mode:** if the plan already answers it, answer from the plan. Otherwise ask the user (one `ask_user_question` call) and relay their answer.

**YOLO mode:** do not ask the user. Pick the most sensible answer, in this order of authority: the plan, the repo's `AGENTS.md` and guides, existing patterns in the code, then the smallest option that stays in scope. Escalate to the user only when the question involves:

- committing, pushing, opening or updating a PR;
- deleting data, or deleting files the plan does not name;
- a remote or production database or service;
- secrets or credentials;
- going beyond the plan's scope.

In YOLO mode, append each answer to `plans/<slug>.md` under `## Decisions (YOLO)`: the question, your answer, and a one-line reason.

**Both modes:** reply with

```bash
herdr agent prompt sub-<slug> "Answers: <answers>. Continue executing the plan and finish with the same report." --wait --timeout 3600000
```

For a `blocked` UI, answer with `herdr agent send-keys` instead, then `herdr agent wait sub-<slug> --timeout 3600000`. Then route the result as in step 3.

## 4. Verify (independently)

1. Read the report: `herdr agent read sub-<slug> --source recent-unwrapped --lines 200`. Treat it as claims, not evidence.
2. `git status --short` and `git diff` (include untracked files). Review every changed file against the plan.
3. Check each acceptance criterion yourself. Run the plan's Verification commands yourself and follow the repo's verification rules (watchers, lint, named test suites).
4. Hunt for: skipped steps, scope creep, unrelated files touched, untouched sibling callers, new `any`, stubs/TODOs, disabled or weakened tests/checks, baseline edits, commits or pushes it was told not to make.

## 5. Decide

**All criteria pass and checks are green:**

```bash
herdr pane close "$PANE"
```

Report to the user: what changed, checks run with outcomes, anything unverified, and (YOLO) the decisions you made on their behalf.

**Gaps found** (fix round N, N <= 3):

1. Append `## Fix round N` to `plans/<slug>.md`: numbered gaps, each with file:line, what is wrong, expected result, and how you will check it.
2. Prompt:
   ```bash
   herdr agent prompt sub-<slug> "Read the 'Fix round N' section of plans/<slug>.md. Fix only those items, re-run the Verification commands, then report in the same format. Ask any question with a QUESTION: line as before." --wait --timeout 3600000
   ```
3. Route the result as in step 3 (questions go through 3a), then return to step 4.

**Still failing after round 3:** stop. Leave the pane open. Tell the user the remaining gaps, the agent name, and the pane ID.

## Rules

- Never close panes you did not create.
- Never commit, push, or open PRs unless the user explicitly asked in this conversation.
- The plan file is the single source of truth; put every instruction in it, not only in the prompt.
