#!/bin/bash

MODEL="${MODEL:-opencode/big-pickle}"
PROJECT_PATH=$1
ITERATIONS=$2

TOOLKIT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$PROJECT_PATH" ]; then
  echo "Usage: ./ralph_research.sh <project_path> [iterations]"
  echo "MODEL can be set via environment variable: MODEL=opencode/your-model ./ralph_research.sh ..."
  exit 1
fi

LOOP_LOGIC=$(cat "$TOOLKIT_PATH/prompts/loop_logic_research.md")
CONTEXT_FILES="@docs/research_brief.json, @docs/progress.txt, @docs/results.tsv"
LABEL="Research Loop"
CHECK_COMPLETE="false"

source "$TOOLKIT_PATH/ralph_core.sh"
