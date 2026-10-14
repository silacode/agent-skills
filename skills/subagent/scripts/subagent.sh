#!/usr/bin/env bash
# Deterministic Herdr pi sub-agent lifecycle helper.
#   subagent.sh parse  [yolo] [--model|-m <model>] [--thinking|-t <level>] <task...>
#   subagent.sh spawn  <slug> [model] [thinking]
#   subagent.sh prompt <slug|agent> <message>       exit 0 done, 2 question/blocked, 1 error
#   subagent.sh read   <slug|agent>
#   subagent.sh close  <pane-id>
set -euo pipefail

DEFAULT_MODEL=${SUBAGENT_DEFAULT_MODEL:-openrouter/meta/muse-spark-1.3}
DEFAULT_THINKING=${SUBAGENT_DEFAULT_THINKING:-xhigh}
SETTINGS_FILE=${PI_SETTINGS_FILE:-"$HOME/.pi/agent/settings.json"}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need_herdr() { [ "${HERDR_ENV:-}" = 1 ] || die "not inside Herdr (HERDR_ENV != 1)"; }

valid_thinking() {
  case "$1" in
    off|minimal|low|medium|high|xhigh|max) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve a model selector (with optional :thinking suffix) against enabledModels and pi --list-models.
# Prints "<provider/id>\t<thinking>" on stdout.
resolve_model_and_thinking() {
  local raw_model=${1:-$DEFAULT_MODEL} explicit_thinking=${2:-}
  local model=$raw_model thinking=$DEFAULT_THINKING

  if [[ "$model" == *:* ]]; then
    local suffix=${model##*:}
    if valid_thinking "$suffix"; then
      model=${model%:*}
      thinking=$suffix
    fi
  fi
  [ -n "$explicit_thinking" ] && thinking=$explicit_thinking
  valid_thinking "$thinking" || die "invalid thinking level '$thinking' (expected: off|minimal|low|medium|high|xhigh|max)"

  local resolved=""
  if [ -f "$SETTINGS_FILE" ]; then
    resolved=$(jq -r --arg m "$model" '
      (.enabledModels // []) as $list
      | ($list | map(select(. == $m))) as $exact
      | if ($exact | length) == 1 then $exact[0]
        else
          ($list | map(select(endswith("/" + $m)))) as $suffix
          | if ($suffix | length) == 1 then $suffix[0]
            else ""
            end
        end
    ' "$SETTINGS_FILE" 2>/dev/null || true)
  fi

  if [ -z "$resolved" ]; then
    local search_term=$model
    [[ "$model" == */* ]] && search_term=${model#*/}
    local catalog
    catalog=$(pi --list-models "$search_term" 2>/dev/null | awk 'NR > 1 && NF >= 2 { print $1 "/" $2 "\t" $2 }')
    if [[ "$model" == */* ]]; then
      resolved=$(awk -F'\t' -v m="$model" '$1 == m { print $1; exit }' <<<"$catalog")
    else
      local matches
      matches=$(awk -F'\t' -v m="$model" '$2 == m { print $1 }' <<<"$catalog")
      if [ -n "$matches" ] && [ "$(wc -l <<<"$matches" | tr -d ' ')" = 1 ]; then
        resolved=$matches
      elif [ -n "$matches" ]; then
        die "ambiguous model '$model'; specify provider/model ($(paste -sd, - <<<"$matches"))"
      fi
    fi
  fi

  [ -n "$resolved" ] || die "unknown or unauthenticated model '$model' (check 'pi --list-models')"
  printf '%s\t%s\n' "$resolved" "$thinking"
}

normalize_agent() {
  local target=$1
  if [[ "$target" == sub-* ]] || [[ "$target" == *:p* ]]; then
    printf '%s\n' "$target"
  else
    printf 'sub-%s\n' "$target"
  fi
}

cmd_parse() {
  need_herdr
  local mode=normal raw_model="" raw_thinking=""
  while [ $# -gt 0 ]; do
    case "$1" in
      yolo|YOLO|--yolo)
        mode=yolo
        shift
        ;;
      --model|-m)
        [ $# -ge 2 ] || die "$1 requires a model argument"
        raw_model=$2
        shift 2
        ;;
      --model=*)
        raw_model=${1#*=}
        shift
        ;;
      --thinking|-t)
        [ $# -ge 2 ] || die "$1 requires a thinking level"
        raw_thinking=$2
        shift 2
        ;;
      --thinking=*)
        raw_thinking=${1#*=}
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  local task="$*"
  [ -n "${task// /}" ] || die "missing task description"

  local resolved model thinking
  resolved=$(resolve_model_and_thinking "${raw_model:-$DEFAULT_MODEL}" "$raw_thinking")
  IFS=$'\t' read -r model thinking <<<"$resolved"

  printf 'mode=%s\nmodel=%s\nthinking=%s\ntask=%s\n' "$mode" "$model" "$thinking" "$task"
}

cmd_spawn() {
  local slug=${1:?usage: subagent.sh spawn <slug> [model] [thinking]}
  local raw_model=${2:-$DEFAULT_MODEL} raw_thinking=${3:-}
  need_herdr

  local agent
  agent=$(normalize_agent "$slug")
  [[ "$agent" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "invalid agent name '$agent' (must match [a-z][a-z0-9_-]{0,31})"

  if herdr agent list | jq -e --arg a "$agent" '.result.agents[]? | select(.agent_name == $a)' >/dev/null 2>&1; then
    die "agent '$agent' is already running"
  fi

  local resolved model thinking
  resolved=$(resolve_model_and_thinking "$raw_model" "$raw_thinking")
  IFS=$'\t' read -r model thinking <<<"$resolved"

  local dir="right"
  if [ -n "${HERDR_PANE_ID:-}" ]; then
    dir=$(herdr pane layout --pane "$HERDR_PANE_ID" 2>/dev/null | jq -r --arg p "$HERDR_PANE_ID" '
      (.result.layout.panes[]? | select(.pane_id == $p) | .rect | if .width >= (.height * 2) then "right" else "down" end) // "right"
    ' || echo "right")
    [ "$dir" = "down" ] || dir="right"
  fi

  local split_out pane
  split_out=$(herdr pane split --current --direction "$dir" --cwd "$PWD" --no-focus)
  pane=$(jq -er '.result.pane.pane_id' <<<"$split_out") || die "failed to read pane_id from: $split_out"

  local out="" started=0
  for _ in $(seq 30); do
    if out=$(herdr agent start "$agent" --kind pi --pane "$pane" --timeout 120000 -- \
      --model "$model" --thinking "$thinking" --exclude-tools ask_user_question 2>&1); then
      started=1
      break
    fi
    if grep -q "agent_pane_busy" <<<"$out"; then
      sleep 1
      continue
    fi
    break
  done

  if [ "$started" -ne 1 ]; then
    herdr pane close "$pane" >/dev/null 2>&1 || true
    die "failed to start $agent in $pane: $out"
  fi

  printf 'agent=%s\npane=%s\ndirection=%s\nmodel=%s\nthinking=%s\n' \
    "$agent" "$pane" "$dir" "$model" "$thinking"
}

# Read the sub-agent's latest state and output (prefers session JSONL over screen-scraping).
# Prints metadata header + "---" + body, and returns:
#   0 = done/idle without QUESTION:
#   2 = blocked or contains QUESTION:
#   1 = error/aborted
read_agent_turn() {
  local agent=$1
  local info status session_file stop_reason="unknown" error_msg="" body=""

  info=$(herdr agent get "$agent" 2>/dev/null) || die "cannot inspect agent '$agent'"
  status=$(jq -r '.result.agent.agent_status // "unknown"' <<<"$info")
  session_file=$(jq -r '.result.agent.agent_session.value // ""' <<<"$info")

  if [ "$status" != "blocked" ] && [ -n "$session_file" ] && [ -f "$session_file" ]; then
    local last_msg
    last_msg=$(jq -s -c '
      [ .[] | select(.type == "message" and .message.role == "assistant") ] | last // empty
    ' "$session_file" 2>/dev/null || true)
    if [ -n "$last_msg" ]; then
      stop_reason=$(jq -r '.message.stopReason // "unknown"' <<<"$last_msg")
      error_msg=$(jq -r '.message.errorMessage // ""' <<<"$last_msg")
      body=$(jq -r '[ .message.content[]? | select(.type == "text") | .text ] | join("\n")' <<<"$last_msg")
    fi
  fi

  if [ -z "$body" ]; then
    body=$(herdr agent read "$agent" --source recent-unwrapped --lines 200 2>/dev/null | jq -r '.result.output // .result.text // .' 2>/dev/null || herdr agent read "$agent" --source recent-unwrapped --lines 200)
  fi

  printf 'agent=%s\nstatus=%s\nstop_reason=%s\nsession=%s\n' "$agent" "$status" "$stop_reason" "$session_file"
  [ -n "$error_msg" ] && printf 'error_message=%s\n' "$error_msg"
  printf -- '---\n%s\n' "$body"

  if [ "$status" = "blocked" ] || grep -Eq '^[[:space:]]*QUESTION:' <<<"$body"; then
    return 2
  fi
  if [ "$stop_reason" = "error" ] || [ "$stop_reason" = "aborted" ]; then
    return 1
  fi
  return 0
}

cmd_prompt() {
  local slug=${1:?usage: subagent.sh prompt <slug|agent> <message>}
  shift
  local message=${1:?usage: subagent.sh prompt <slug|agent> <message>}
  need_herdr

  local agent
  agent=$(normalize_agent "$slug")

  local out=""
  if ! out=$(herdr agent prompt "$agent" "$message" --wait --timeout 3600000 2>&1); then
    if grep -Eq "timeout|agent_prompt_stalled" <<<"$out"; then
      local st
      st=$(herdr agent get "$agent" 2>/dev/null | jq -r '.result.agent.agent_status // "unknown"' || echo "unknown")
      if [ "$st" = "working" ]; then
        herdr agent wait "$agent" --timeout 3600000 >/dev/null \
          || die "$agent still not idle after wait; do not re-send the prompt, run 'herdr agent wait' again"
      fi
    else
      die "herdr agent prompt failed for $agent: $out"
    fi
  fi

  read_agent_turn "$agent"
}

cmd_read() {
  local slug=${1:?usage: subagent.sh read <slug|agent>}
  need_herdr
  read_agent_turn "$(normalize_agent "$slug")"
}

cmd_close() {
  local pane=${1:?usage: subagent.sh close <pane-id>}
  need_herdr
  [ "$pane" != "${HERDR_PANE_ID:-}" ] || die "refusing to close caller pane ($pane)"
  herdr pane close "$pane" >/dev/null
  printf 'closed=%s\n' "$pane"
}

case "${1:-}" in
  parse)  shift; cmd_parse "$@" ;;
  spawn)  shift; cmd_spawn "$@" ;;
  prompt) shift; cmd_prompt "$@" ;;
  read)   shift; cmd_read "$@" ;;
  close)  shift; cmd_close "$@" ;;
  *)      die "usage: subagent.sh {parse|spawn|prompt|read|close} ..." ;;
esac
