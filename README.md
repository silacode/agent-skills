# agent-skills

Personal agent skills.

| Skill | What it does |
| --- | --- |
| [new-workspace](skills/new-workspace/SKILL.md) | Create or safely close a Herdr workspace backed by a git worktree. |
| [native-web-search](skills/native-web-search/SKILL.md) | Run a fast model with native web search and full source URLs. |
| [subagent](skills/subagent/SKILL.md) | Plan a task, hand it to a Herdr pi sub-agent (default `openrouter/meta/muse-spark-1.3:xhigh`, configurable via `--model`), verify its work, and send fix-ups; `yolo` auto-answers its questions. |
| [security-alerts-plan](skills/security-alerts-plan/SKILL.md) | Read all open GitHub security alerts (Dependabot, code scanning, secret scanning, advisories), trace root causes, and write one fix plan. |
| [review-comment-triage](skills/review-comment-triage/SKILL.md) | Classify review-bot comments as TRUE, TRUE-MINOR, or FALSE with a one-line argument each; optionally reply to FALSE ones after approval. |
| [principle-redesign-from-first-principles](skills/principle-redesign-from-first-principles/SKILL.md) | Integrate new requirements by redesigning from first principles instead of bolting changes onto the existing design. From [cursor/plugins](https://github.com/cursor/plugins/blob/850d7f2e9f5e55dff7eb00a0a479337fe79eb22f/pstack/skills/principle-redesign-from-first-principles/SKILL.md). |
| [principle-subtract-before-you-add](skills/principle-subtract-before-you-add/SKILL.md) | Remove unnecessary complexity before additions, refactors, or rewrites, then build on the simpler base. From [cursor/plugins](https://github.com/cursor/plugins/blob/850d7f2e9f5e55dff7eb00a0a479337fe79eb22f/pstack/skills/principle-subtract-before-you-add/SKILL.md). |
| [bro](skills/bro/SKILL.md) | Restate the last message in plain human language, no jargon. From [cursor/plugins](https://github.com/cursor/plugins/blob/850d7f2e9f5e55dff7eb00a0a479337fe79eb22f/pstack/skills/bro/SKILL.md). |
