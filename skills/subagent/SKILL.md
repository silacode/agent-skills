---
name: subagent
description: "Plan a task, get user approval, then delegate execution to a Herdr pi sub-agent (defaults to openrouter/meta/muse-spark-1.3 at xhigh thinking; override with --model); verify its work independently and either close it or send fix-up instructions (max 3 rounds). YOLO mode (leading `yolo` argument) answers the sub-agent's questions instead of relaying them. Use when the user asks to delegate, hand off, or run a task through a sub-agent. Requires HERDR_ENV=1."
disable-model-invocation: false
metadata:
  argument-hint: "[yolo] [--model <provider/id[:thinking]>] [--thinking <level>] <task>"
---

# Sub-agent: plan, delegate, verify, close

You are the planner and the reviewer. The sub-agent is the implementer. Never trust its report; verify the tree yourself.

`scripts/subagent.sh` is relative to this `SKILL.md` (`~/.pi/agent/skills/subagent/scripts/subagent.sh`). Run that script for argument parsing, spawning, prompting/waiting, reading, and closing; do not reimplement its Herdr loops by hand.

Herdr CLI details live in `~/.pi/agent/skills/herdr/SKILL.md`. Read it if a command fails or you need `send-keys`.

## 0. Preflight & Parse

Pass the invocation arguments to `subagent.sh parse`:

```bash
"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" parse <args...>
```

- Leading flags before `<task>` may appear in any order:
  - `yolo` / `--yolo` — enables **YOLO mode** (changes only step 3a; planning questions and plan approval stay the same).
  - `--model <model>` / `-m <model>` — full `provider/id`, a unique model ID from `enabledModels` / `pi --list-models` (e.g. `gpt-6-sol`), or `provider/id:thinking`. Defaults to `openrouter/meta/muse-spark-1.3`.
  - `--thinking <level>` / `-t <level>` — `off|minimal|low|medium|high|xhigh|max`. Defaults to `xhigh`.
- If the user asked in natural language (e.g. *"delegate this to a sub-agent with gpt-6-sol in yolo mode"*), pass the normalized flags (`yolo --model gpt-6-sol "<task>"`) to `parse`.
- Exit 0 prints `mode=`, `model=`, `thinking=`, `task=`.
- Non-zero (not inside Herdr, unknown/unauthenticated model, invalid thinking level, missing task): show the error and stop.

## 1. Plan

1. Read the task and the code it touches. Trace the real flow. Read the repo's `AGENTS.md` files for the area.
2. Ambiguous requirement you cannot default: ask the user now (one `ask_user_question` call), not after spawning.
3. Write the plan to `<repo-root>/plans/<slug>.md` (`git rev-parse --show-toplevel`). `<slug>` is short kebab-case (`[a-z0-9-]+`, max 27 chars so `sub-<slug>` fits Herdr's 32-char limit). Include `Mode: <mode>` and `Model: <model> (<thinking>)` at the top, followed by:
   - **Goal**: one paragraph.
   - **Context**: exact files, symbols, and the relevant `AGENTS.md`/skills the implementer must read.
   - **Steps**: numbered, concrete, file-level.
   - **Acceptance criteria**: numbered, each one checkable by reading the diff or running a command.
   - **Verification**: exact commands to run (from the repo's guides / `package.json`).
   - **Out of scope / constraints**: what not to touch. Default: do not commit, push, or open PRs; do not edit `AGENTS.md`; do not weaken checks or update baselines.
4. Show the user a short summary, the chosen `model` (`thinking`) and `mode`, plus the plan path. **Stop and wait for approval.** Apply requested edits to the plan file before continuing.

## 2. Spawn

```bash
"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" spawn <slug> "<model>" "<thinking>"
```

- Automatically picks `right` or `down` from the caller pane's geometry (`herdr pane layout`), splits the pane with `--no-focus`, retries `herdr agent start` up to 30s on `agent_pane_busy`, passes `--exclude-tools ask_user_question`, and closes the new pane on any startup error.
- Exit 0 prints `agent=sub-<slug>`, `pane=<pane-id>`, `direction=`, `model=`, `thinking=`. Remember `PANE` and `agent` for the rest of the session.
- Non-zero: show the error and stop.
- Do not edit files in this worktree while the sub-agent is working.

## 3. Delegate

Run with a `bash` tool `timeout` of `3700` seconds:

```bash
"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" prompt <slug> "Execute the plan in plans/<slug>.md exactly. Read every file and guide it lists first. Stay in scope. Run its Verification commands. Finish with a report: DONE or NOT DONE, files changed, each acceptance criterion with pass/fail, checks run with outcomes, anything skipped and why. If you need a decision the plan does not answer, stop and end your turn with one line per question starting with QUESTION:, listing the options you see."
```

`subagent.sh prompt` handles `timeout` / `agent_prompt_stalled` recovery (`agent get` → `agent wait`) and reads the sub-agent's verbatim assistant message from its session `.jsonl` file (falling back to `herdr agent read --source recent-unwrapped --lines 200`).

Route the result:
- **Exit 2** (`status=blocked` or a `QUESTION:` line): go to **3a**.
- **Exit 0**: if the report is not a clear DONE / NOT DONE, or it ends by asking something without the `QUESTION:` prefix, go to **3a**. Otherwise go to **4**.
- **Exit 1** (`stop_reason=error|aborted` or Herdr failure): read the output. If `herdr agent get sub-<slug>` still shows `working`, run `herdr agent wait sub-<slug> --timeout 3600000`, then `subagent.sh read <slug>`. Never re-send the prompt blindly. If the sub-agent hit a transient error, you may prompt once to resume; otherwise report and stop.

### 3a. Sub-agent questions

**Normal mode:** if the plan already answers it, answer from the plan. Otherwise ask the user (one `ask_user_question` call) and relay their answer.

**YOLO mode:** do not ask the user. Pick the most sensible answer, in this order of authority: the plan, the repo's `AGENTS.md` and guides, existing patterns in the code, then the smallest option that stays in scope. Escalate to the user (one `ask_user_question` call) only when the question involves:

- committing, pushing, opening or updating a PR;
- deleting data, or deleting files the plan does not name;
- a remote or production database or service;
- secrets or credentials;
- going beyond the plan's scope.

In YOLO mode, append each answer to `plans/<slug>.md` under `## Decisions (YOLO)`: the question, your answer, and a one-line reason.

**Reply in both modes** (with `bash` tool `timeout: 3700`):

```bash
"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" prompt <slug> "Answers: <answers>. Continue executing the plan and finish with the same report."
```

For a `blocked` TUI dialog, answer with `herdr agent send-keys sub-<slug> ...`, then `herdr agent wait sub-<slug> --timeout 3600000` and `"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" read <slug>`. Route the result as in step 3.

## 4. Verify (independently)

1. Treat the sub-agent's report from step 3 as claims, not evidence (re-read anytime with `"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" read <slug>`).
2. `git status --short` and `git diff` (include untracked files). Review every changed file against the plan.
3. Check each acceptance criterion yourself. Run the plan's Verification commands yourself and follow the repo's verification rules (watchers, lint, named test suites).
4. Hunt for: skipped steps, scope creep, unrelated files touched, untouched sibling callers, new `any`, stubs/TODOs, disabled or weakened tests/checks, baseline edits, commits or pushes it was told not to make.

## 5. Decide

**All criteria pass and checks are green:**

```bash
"$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" close "$PANE"
```

Report to the user: what changed, checks run with outcomes, anything unverified, and (YOLO) the decisions you made on their behalf.

**Gaps found** (fix round N, N <= 3):

1. Append `## Fix round N` to `plans/<slug>.md`: numbered gaps, each with `file:line`, what is wrong, expected result, and how you will check it.
2. Prompt (with `bash` tool `timeout: 3700`):
   ```bash
   "$HOME/.pi/agent/skills/subagent/scripts/subagent.sh" prompt <slug> "Read the 'Fix round N' section of plans/<slug>.md. Fix only those items, re-run the Verification commands, then report in the same format. Ask any question with a QUESTION: line as before."
   ```
3. Route the result as in step 3 (questions go through 3a), then return to step 4.

**Still failing after round 3:** stop. Leave the pane open. Tell the user the remaining gaps, the agent name (`sub-<slug>`), and the pane ID (`$PANE`).

## Rules

- Never close panes you did not create (`subagent.sh close` refuses to close `$HERDR_PANE_ID`).
- Never commit, push, or open PRs unless the user explicitly asked in this conversation.
- The plan file is the single source of truth; put every instruction in it, not only in the prompt.
