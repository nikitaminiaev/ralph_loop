#!/bin/bash
MODEL="opencode/glm-4.7-free"
TOOLKIT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_PATH=$1
INPUT_MD=$2

if [ -z "$PROJECT_PATH" ] || [ -z "$INPUT_MD" ]; then
  echo "Usage: ./prd-converter.sh <project_path> <input_file.md>"
  exit 1
fi

cd "$PROJECT_PATH" || exit 1

PRD_LOGIC=$(cat "$TOOLKIT_PATH/prompts/prd_logic.md")

opencode run -m $MODEL "
  $PRD_LOGIC

  ВХОДНОЙ ФАЙЛ: @$INPUT_MD
"