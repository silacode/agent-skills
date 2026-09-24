---
name: new-workspace
description: "Create or safely close a top-level Herdr workspace backed by a git worktree, including workspace-ID labels, pane cleanup, worktree removal, and local branch deletion. Never use herdr worktree create — it nests the workspace and hides the branch."
---

# Herdr workspace on a git worktree

`scripts/ws.sh` is relative to this `SKILL.md`, not the current repository.
Its full path is `~/.pi/agent/skills/new-workspace/scripts/ws.sh`.
Run that script; relay its output. Do not reimplement its steps by hand.

Requires `HERDR_ENV=1` (the script checks; if it fails, stop).

## Create

```bash
"$HOME/.pi/agent/skills/new-workspace/scripts/ws.sh" create <branch> [label]
```

- Need a branch name. Ask once if missing. Never invent one.
- Label defaults to the last path segment of the branch (`feat/foo-bar` → `foo-bar`); pass a second arg only if the user gave one.
- Repo defaults to `/Volumes/SpaceHD/Work/complyplus/comply_plus`; override with `WS_REPO=<path>` for another repo.
- Exit 0 → report the printed `workspace=`, `label=`, `path=`, `branch=`, `tracking=`, `head=` lines, plus the `.env` line. Done.
- Non-zero → show the error and stop. Do not retry with different git commands.

What it guarantees: branch exists on GitHub (created there from GitHub's `develop` if missing), worktree is a sibling dir cut from `origin/<branch>` with tracking, Herdr workspace is top-level (no `worktree` object), label is `<id> · <label>`, `.env` copied from the invoking checkout if it's the same repo, `npm ci` ran with the repo's `.nvmrc` Node.

## Close

```bash
"$HOME/.pi/agent/skills/new-workspace/scripts/ws.sh" close <workspace-id|label>
```

- Run from a different workspace than the target (the script refuses to close `$HERDR_WORKSPACE_ID`).
- Exit 0 → report the printed summary. Done.
- Exit 3 → the worktree has uncommitted files, unpushed commits, or no remote branch. Show the printed `NEEDS CONFIRMATION` text to the user verbatim and ask once. Only after an explicit yes:
  ```bash
  "$HOME/.pi/agent/skills/new-workspace/scripts/ws.sh" close <workspace-id|label> --confirm
  ```
- Exit 1 → refused (ambiguous target, primary checkout, `main`/`develop`, detached, multiple git roots, Herdr close failed…). Show the error and stop. Never work around it with `--force`, `rm -rf`, or manual `herdr pane close`.

The script never deletes the remote branch. If the user wants that, it is a separate, explicit request.

## Never

- `herdr worktree create` / `herdr worktree open` — Herdr nests the workspace and hides the branch.
- `git worktree add -b <branch>` without `origin/<branch>` — forks from local HEAD.
- `npm install` — rewrites the lockfile; the script uses `npm ci`.
- Closing the workspace you are running in, stopping the Herdr server, or touching unrelated workspaces.
