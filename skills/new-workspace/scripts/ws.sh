#!/usr/bin/env bash
# Herdr workspace on a git worktree — deterministic create/close.
#   ws.sh create <branch> [label]              exit 0 ok, 1 error
#   ws.sh close  <workspace-id|label>          exit 0 done, 1 refused, 3 needs --confirm
#   ws.sh close  <workspace-id|label> --confirm
set -euo pipefail

REPO=${WS_REPO:-/Volumes/SpaceHD/Work/complyplus/comply_plus}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need_herdr() { [ "${HERDR_ENV:-}" = 1 ] || die "not inside Herdr (HERDR_ENV != 1)"; }
remote_sha() { git -C "$1" ls-remote --heads origin "$2" | cut -f1; }

create() {
  local branch=${1:?usage: ws.sh create <branch> [label]} label=${2:-${1##*/}}
  need_herdr
  REPO=$(cd "$REPO" && pwd -P) || die "$REPO missing"
  [ "$(git -C "$REPO" rev-parse --show-toplevel)" = "$REPO" ] || die "$REPO is not a git repo root"
  local dir="$(dirname "$REPO")/$label"
  [ ! -e "$dir" ] || die "$dir already exists"
  ! git -C "$REPO" show-ref --verify --quiet "refs/heads/$branch" || die "local branch $branch already exists"

  # Branch must exist on GitHub; create it there from GitHub's develop if missing.
  local sha; sha=$(remote_sha "$REPO" "$branch")
  if [ -z "$sha" ]; then
    local base nwo
    base=$(git -C "$REPO" ls-remote origin refs/heads/develop | cut -f1)
    [ -n "$base" ] || die "origin has no develop branch"
    nwo=$(cd "$REPO" && gh repo view --json nameWithOwner -q .nameWithOwner)
    # Failure (incl. 422 race) falls through to the re-check below.
    gh api "repos/$nwo/git/refs" -f ref="refs/heads/$branch" -f sha="$base" >/dev/null || true
    sha=$(remote_sha "$REPO" "$branch")
    [ -n "$sha" ] || die "failed to create $branch on GitHub"
    echo "created $branch on GitHub from develop ($base)"
  fi

  git -C "$REPO" fetch --quiet origin "$branch"
  [ "$(git -C "$REPO" rev-parse "origin/$branch")" = "$sha" ] || die "origin/$branch moved during setup; rerun"
  git -C "$REPO" worktree add --track -b "$branch" "$dir" "origin/$branch" >/dev/null
  [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ] || die "worktree HEAD != GitHub $branch ($sha)"

  # Copy .env from the invoking checkout if it is a worktree of the same repo.
  local src
  src=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$src" ] && [ -f "$src/.env" ] &&
     [ "$(git -C "$src" rev-parse --path-format=absolute --git-common-dir)" = \
       "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" ]; then
    cp "$src/.env" "$dir/.env" && echo "copied .env from $src"
  else
    echo "skipped .env copy"
  fi

  local result wsid
  result=$(herdr workspace create --cwd "$dir" --label "$label" --focus)
  wsid=$(jq -er '.result.workspace.workspace_id' <<<"$result") || die "no workspace_id in: $result"
  herdr workspace rename "$wsid" "$wsid · $label" >/dev/null
  herdr workspace list | jq -e --arg id "$wsid" \
    '.result.workspaces[] | select(.workspace_id==$id) | has("worktree") | not' >/dev/null \
    || die "workspace $wsid has a worktree object (Herdr nested it)"

  (cd "$dir" && fnm exec npm ci >/dev/null)

  printf 'workspace=%s\nlabel=%s · %s\npath=%s\nbranch=%s\ntracking=origin/%s\nhead=%s\n' \
    "$wsid" "$wsid" "$label" "$dir" "$branch" "$branch" "$sha"
}

close() {
  local target=${1:?usage: ws.sh close <workspace-id|label> [--confirm]} confirm=${2:-}
  need_herdr
  [ -z "$confirm" ] || [ "$confirm" = --confirm ] || die "unknown flag $confirm"

  local matches wsid label
  matches=$(herdr workspace list | jq -c --arg t "$target" \
    '[.result.workspaces[] | select(.workspace_id==$t or .label==$t or (.label|sub("^[^·]+ · ";""))==$t)]')
  case $(jq length <<<"$matches") in
    0) die "no workspace matches '$target'" ;;
    1) ;;
    *) die "ambiguous target '$target': $(jq -r '.[] | "\(.workspace_id)=\(.label)"' <<<"$matches" | paste -sd, -)" ;;
  esac
  wsid=$(jq -r '.[0].workspace_id' <<<"$matches")
  label=$(jq -r '.[0].label' <<<"$matches")
  [ "$wsid" != "${HERDR_WORKSPACE_ID:-}" ] || die "refusing to close the workspace running this script ($wsid)"

  local panes pane_count roots root
  panes=$(herdr pane list --workspace "$wsid")
  pane_count=$(jq '.result.panes | length' <<<"$panes")
  roots=$(jq -r '.result.panes[].cwd' <<<"$panes" \
    | while IFS= read -r c; do git -C "$c" rev-parse --show-toplevel 2>/dev/null || true; done | sort -u)
  [ -n "$roots" ] && [ "$(grep -c . <<<"$roots")" -eq 1 ] || die "panes resolve to zero or multiple git roots: ${roots:-<none>}"
  root=$roots

  local primary branch
  primary=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
  [ "$root" != "$primary" ] || die "$root is the primary checkout"
  git -C "$primary" worktree list --porcelain | grep -Fxq "worktree $root" || die "$root is not a registered worktree of $primary"
  branch=$(git -C "$root" symbolic-ref --quiet --short HEAD) || die "$root is detached"
  case $branch in main|develop) die "refusing to remove a $branch checkout" ;; esac

  local dirty ahead=0 remote_missing= summary=
  dirty=$(git -C "$root" status --porcelain)
  if [ -n "$(remote_sha "$root" "$branch")" ]; then
    git -C "$root" fetch --quiet origin "$branch"
    ahead=$(git -C "$root" rev-list --count "origin/$branch..HEAD")
  else
    remote_missing=1
  fi
  [ -z "$dirty" ] || summary="$summary, $(grep -c . <<<"$dirty") uncommitted/untracked files"
  [ "$ahead" -eq 0 ] || summary="$summary, $ahead local commits not on origin/$branch"
  [ -z "$remote_missing" ] || summary="$summary, no remote branch origin/$branch"
  summary=${summary#, }
  if [ -n "$summary" ] && [ "$confirm" != --confirm ]; then
    printf 'NEEDS CONFIRMATION\nWorkspace %s (%s) contains %s.\nContinuing will close all %s panes, permanently discard local changes, remove %s, and delete local branch %s. Remote branch origin/%s will not be deleted.\nRerun with --confirm after the user explicitly agrees.\n' \
      "$wsid" "$label" "$summary" "$pane_count" "$root" "$branch" "$branch"
    exit 3
  fi

  herdr workspace close "$wsid" >/dev/null || die "herdr workspace close failed; git state untouched"
  git -C "$primary" worktree remove ${dirty:+--force} "$root" || die "worktree remove failed; local branch $branch kept"
  git -C "$primary" branch -D "$branch" >/dev/null

  herdr workspace list | jq -e --arg id "$wsid" '[.result.workspaces[] | select(.workspace_id==$id)] | length == 0' >/dev/null \
    || die "workspace $wsid still listed"
  ! git -C "$primary" worktree list --porcelain | grep -Fxq "worktree $root" || die "worktree still registered"
  [ ! -e "$root" ] || die "$root still exists"
  ! git -C "$primary" show-ref --verify --quiet "refs/heads/$branch" || die "local branch $branch still exists"

  local forced=no; [ -z "$dirty" ] || forced=yes
  printf 'closed=%s\nlabel=%s\npanes=%s\nremoved=%s\ndeleted_local_branch=%s\nforced=%s\nremote_branch=untouched\n' \
    "$wsid" "$label" "$pane_count" "$root" "$branch" "$forced"
}

case ${1:-} in
  create) shift; create "$@" ;;
  close)  shift; close "$@" ;;
  *) sed -n '2,5p' "$0" >&2; exit 1 ;;
esac
