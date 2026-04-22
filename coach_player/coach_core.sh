#!/bin/bash
# Ядро actor-critic цикла. Не запускать напрямую.
# Источник: вызывается через `source` из ralph_coach_player.sh.
#
# Ожидаемые переменные от вызывающего скрипта:
#   MODEL                     — модель opencode для Player
#   COACH_MODEL               — модель opencode для Coach
#   PROJECT_PATH              — путь к целевому проекту
#   ITERATIONS                — лимит итераций (опционально)
#   TOOLKIT_PATH              — директория coach_player
#   PLAYER_LOGIC              — содержимое prompts/player_logic.md
#   COACH_LOGIC               — содержимое prompts/coach_logic.md
#   PLAYER_CONTEXT            — @-файлы для player
#   COACH_CONTEXT             — @-файлы для coach
#   MAX_RETRIES               — retry на opencode run (default 3)
#   MAX_NO_PROGRESS_TURNS     — сколько итераций без нового коммита до выхода (default 5)
#   MAX_REVERTS_PER_US        — сколько раз Coach может подряд ревёртить одну US до выхода (default 3)

SAFETY_STOP=10000
MAX_RETRIES=${MAX_RETRIES:-3}
MAX_NO_PROGRESS_TURNS=${MAX_NO_PROGRESS_TURNS:-5}
MAX_REVERTS_PER_US=${MAX_REVERTS_PER_US:-3}

cd "$PROJECT_PATH" || exit 1

mkdir -p docs
[ -f docs/progress.txt ]      || touch docs/progress.txt
[ -f docs/coach_feedback.md ] || touch docs/coach_feedback.md
[ -f docs/coach_history.md ]  || touch docs/coach_history.md

STATE_FILE="docs/.coach_player_state"
[ -f "$STATE_FILE" ] || : > "$STATE_FILE"

# === State helpers (key=value плоский файл) ===

state_get() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; found=1; exit } END { if (!found) print "" }' "$STATE_FILE"
}

state_set() {
  local key="$1" value="$2" tmp
  tmp=$(mktemp)
  awk -F= -v k="$key" -v v="$value" '
    BEGIN { seen=0 }
    $1 == k { print k "=" v; seen=1; next }
    { print }
    END { if (!seen) print k "=" v }
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

state_inc() {
  local key="$1" cur
  cur=$(state_get "$key")
  [ -z "$cur" ] && cur=0
  state_set "$key" "$((cur + 1))"
}

# Сбросить ВСЕ счётчики REVERT:US-XXX кроме тех, что были ревёрнуты в этот ход.
# Передать список US через $1 (space-separated).
reset_revert_counters_except() {
  local keep_list="$1" tmp
  tmp=$(mktemp)
  awk -F= -v keep="$keep_list" '
    BEGIN {
      n = split(keep, arr, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (arr[i] != "") keepmap["REVERT:" arr[i]] = 1
    }
    $1 ~ /^REVERT:/ {
      if ($1 in keepmap) print
      next
    }
    { print }
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# === opencode run с retry и экспоненциальным бэкоффом ===

run_with_retry() {
  local role="$1" model="$2" prompt="$3"
  local attempt=1 delay=5 output ec
  while [ "$attempt" -le "$MAX_RETRIES" ]; do
    output=$(opencode run -m "$model" "$prompt")
    ec=$?
    if [ "$ec" -eq 0 ] && [ -n "$output" ]; then
      printf '%s' "$output"
      return 0
    fi
    echo ">>> $role attempt $attempt/$MAX_RETRIES failed (exit=$ec, output_len=${#output}), retrying in ${delay}s..." >&2
    sleep "$delay"
    delay=$((delay * 3))
    attempt=$((attempt + 1))
  done
  echo ">>> $role: giving up after $MAX_RETRIES attempts" >&2
  return 1
}

# === HEAD snapshot для stall-детектора ===

current_head() {
  git rev-parse HEAD 2>/dev/null || echo "NO_COMMITS"
}

# === Основной цикл ===

current_iteration=1
max_iterations=${ITERATIONS:-$SAFETY_STOP}

while true; do
  if [ "$current_iteration" -gt "$max_iterations" ]; then
    echo "Достигнут лимит $max_iterations. Продолжить? (y/n)"
    read -r continue_answer
    case "$continue_answer" in
      [Yy]) max_iterations=$SAFETY_STOP ;;
      *) exit 0 ;;
    esac
  fi

  echo "--- Coach-Player: Iteration $current_iteration ---"

  head_before=$(current_head)

  # === PLAYER ===
  echo ">>> PLAYER ($MODEL)"
  if ! player_output=$(run_with_retry "PLAYER" "$MODEL" "
    $PLAYER_LOGIC

    FILES: $PLAYER_CONTEXT
  "); then
    echo ">>> PLAYER failed after retries, skipping to next iteration" >&2
    current_iteration=$((current_iteration + 1))
    continue
  fi

  player_complete=false
  if grep -q "<promise>COMPLETE</promise>" <<< "$player_output"; then
    player_complete=true
    echo ">>> Player signalled COMPLETE, handing over to Coach for final review"
  fi

  # === COACH (fresh context) ===
  echo ">>> COACH ($COACH_MODEL)"

  if git rev-parse HEAD~1 >/dev/null 2>&1; then
    git_diff=$({
      echo "### git log -1 --stat"
      git log -1 --stat
      echo
      echo "### git diff HEAD~1"
      git diff HEAD~1
    } | head -c 20000)
  else
    git_diff="(no previous commit; this is the initial state)"
  fi

  if ! coach_output=$(run_with_retry "COACH" "$COACH_MODEL" "
    $COACH_LOGIC

    FILES: $COACH_CONTEXT

    LAST_COMMIT:
    $git_diff
  "); then
    echo ">>> COACH failed after retries, skipping to next iteration" >&2
    current_iteration=$((current_iteration + 1))
    continue
  fi

  coach_approved=false
  grep -q "<promise>APPROVED</promise>" <<< "$coach_output" && coach_approved=true

  # === A. Детектор спора по US ===
  # Парсим строку "COACH_REVERTED: US-003 US-007" (может быть пустая после ':')
  reverted_line=$(grep -m1 -E '^COACH_REVERTED:' <<< "$coach_output" | sed -E 's/^COACH_REVERTED:[[:space:]]*//')
  if [ -n "$reverted_line" ]; then
    echo ">>> Coach reverted: $reverted_line"
    for us in $reverted_line; do
      state_inc "REVERT:$us"
      cnt=$(state_get "REVERT:$us")
      echo ">>> revert counter $us=$cnt (limit $MAX_REVERTS_PER_US)"
      if [ "$cnt" -ge "$MAX_REVERTS_PER_US" ]; then
        echo ""
        echo "!!! STABLE DISPUTE on $us ($cnt consecutive reverts) — halting."
        echo "!!! Human intervention needed. See docs/coach_feedback.md and docs/coach_history.md."
        exit 2
      fi
    done
  fi
  # Сбросить счётчики всех US, которые НЕ были ревёрнуты в этот ход.
  reset_revert_counters_except "$reverted_line"

  # === Условие выхода по APPROVED ===
  if $player_complete && $coach_approved; then
    echo "Coach approved final state. Project finished successfully!"
    exit 0
  fi
  if $player_complete && ! $coach_approved; then
    echo ">>> Player claimed COMPLETE but Coach disagreed — continuing loop"
  fi

  # === B. Stall-детектор ===
  head_after=$(current_head)
  if [ "$head_before" = "$head_after" ]; then
    state_inc "NO_PROGRESS"
  else
    state_set "NO_PROGRESS" "0"
  fi
  no_progress=$(state_get "NO_PROGRESS")
  [ -z "$no_progress" ] && no_progress=0
  if [ "$no_progress" -ge "$MAX_NO_PROGRESS_TURNS" ]; then
    echo ""
    echo "!!! NO PROGRESS for $no_progress consecutive turns (HEAD unchanged) — halting."
    echo "!!! Player is stuck. Check docs/progress.txt and docs/coach_feedback.md."
    exit 3
  fi

  current_iteration=$((current_iteration + 1))
done
