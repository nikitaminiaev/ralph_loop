#!/bin/bash
# Coach-Player (actor-critic) режим Ralph Loop.
# Работает поверх существующего PRD workflow: Player — как обычный ralph-цикл,
# Coach — отдельный opencode run со свежим контекстом после каждого хода Player.

TOOLKIT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Auto-load defaults from .env next to this script.
# Variables already set in the environment win over .env — so CLI overrides still work:
#   MODEL=opencode/other ./ralph_coach_player.sh ...
if [ -f "$TOOLKIT_PATH/.env" ]; then
  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    line="${raw_line%%#*}"                            # strip inline/full-line comments
    line="${line#"${line%%[![:space:]]*}"}"           # ltrim
    line="${line%"${line##*[![:space:]]}"}"           # rtrim
    [ -z "$line" ] && continue
    key="${line%%=*}"
    value="${line#*=}"
    # strip surrounding single/double quotes from value
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    # only set if not already set in the environment
    if [ -z "${!key+set}" ]; then
      export "$key=$value"
    fi
  done < "$TOOLKIT_PATH/.env"
fi

MODEL="${MODEL:-opencode/big-pickle}"
COACH_MODEL="${COACH_MODEL:-$MODEL}"
PROJECT_PATH=$1
ITERATIONS=$2

# Safety / loop-protection knobs (overridable via env or .env)
MAX_RETRIES="${MAX_RETRIES:-3}"
MAX_NO_PROGRESS_TURNS="${MAX_NO_PROGRESS_TURNS:-5}"
MAX_REVERTS_PER_US="${MAX_REVERTS_PER_US:-3}"

if [ -z "$PROJECT_PATH" ]; then
  echo "Usage: ./ralph_coach_player.sh <project_path> [iterations]"
  echo ""
  echo "Environment:"
  echo "  MODEL                  — opencode model for Player (default: opencode/big-pickle)"
  echo "  COACH_MODEL            — opencode model for Coach  (default: same as MODEL)"
  echo "  MAX_RETRIES            — opencode run retries on failure (default: 3)"
  echo "  MAX_NO_PROGRESS_TURNS  — halt after N turns with no new commit (default: 5)"
  echo "  MAX_REVERTS_PER_US     — halt after Coach reverts same US N times in a row (default: 3)"
  echo ""
  echo "Example:"
  echo "  MODEL=opencode/your-model COACH_MODEL=opencode/smarter-model \\"
  echo "    ./ralph_coach_player.sh /path/to/project 100"
  exit 1
fi

PLAYER_LOGIC=$(cat "$TOOLKIT_PATH/prompts/player_logic.md")
COACH_LOGIC=$(cat "$TOOLKIT_PATH/prompts/coach_logic.md")
PLAYER_CONTEXT="@docs/prd.json, @docs/progress.txt, @docs/coach_feedback.md"
COACH_CONTEXT="@docs/prd.json, @docs/progress.txt, @docs/coach_feedback.md, @docs/coach_history.md"

export MODEL COACH_MODEL PROJECT_PATH ITERATIONS TOOLKIT_PATH \
       PLAYER_LOGIC COACH_LOGIC PLAYER_CONTEXT COACH_CONTEXT \
       MAX_RETRIES MAX_NO_PROGRESS_TURNS MAX_REVERTS_PER_US

source "$TOOLKIT_PATH/coach_core.sh"
