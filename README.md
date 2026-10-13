# agent-skills

Personal agent skills.

| Skill | What it does |
| --- | --- |
| [new-workspace](skills/new-workspace/SKILL.md) | Create or safely close a Herdr workspace backed by a git worktree. |
| [native-web-search](skills/native-web-search/SKILL.md) | Run a fast model with native web search and full source URLs. |
| [subagent](skills/subagent/SKILL.md) | Plan a task, hand it to a gpt-6-sol Herdr sub-agent, verify its work, and send fix-ups; `yolo` auto-answers its questions. |
| [security-alerts-plan](skills/security-alerts-plan/SKILL.md) | Read all open GitHub security alerts (Dependabot, code scanning, secret scanning, advisories), trace root causes, and write one fix plan. |
| [review-comment-triage](skills/review-comment-triage/SKILL.md) | Classify review-bot comments as TRUE, TRUE-MINOR, or FALSE with a one-line argument each; optionally reply to FALSE ones after approval. |

## Prompts

| Prompt | What it does |
| --- | --- |
| [subagent](prompts/subagent.md) | `/subagent [yolo] <task>` command for the subagent skill. Copy to `~/.pi/agent/prompts/`. |
