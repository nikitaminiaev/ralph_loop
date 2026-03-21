#!/bin/bash

MODEL="${MODEL:-opencode/big-pickle}"
PROJECT_PATH=$1
ITERATIONS=$2

TOOLKIT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$PROJECT_PATH" ]; then
  echo "Usage: ./ralph_opencode.sh <project_path> [iterations]"
  echo "MODEL can be set via environment variable: MODEL=opencode/your-model ./ralph_opencode.sh ..."
  exit 1
fi

LOOP_LOGIC=$(cat "$TOOLKIT_PATH/prompts/loop_logic.md")
CONTEXT_FILES="@docs/prd.json, @docs/progress.txt"
LABEL="Ralph Loop"
CHECK_COMPLETE="true"

source "$TOOLKIT_PATH/ralph_core.sh"
