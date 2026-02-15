#!/bin/bash

MODEL="${MODEL:-opencode/big-pickle}"
PROJECT_PATH=$1
ITERATIONS=$2
SAFETY_STOP=10000

TOOLKIT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "$PROJECT_PATH" ]; then
  echo "Usage: ./ralph_opencode.sh <project_path> [iterations]"
  echo "MODEL can be set via environment variable: MODEL=opencode/your-model ./ralph_opencode.sh ..."
  exit 1
fi

cd "$PROJECT_PATH" || exit

# Загружаем универсальную логику цикла (как вести себя Ральфу)
LOOP_LOGIC=$(cat "$TOOLKIT_PATH/prompts/loop_logic.md")

mkdir -p docs
if [ ! -f docs/progress.txt ]; then
  touch docs/progress.txt
fi

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

  echo "--- Ralph Loop: Iteration $current_iteration ---"

  # Мы передаем:
  # 1. LOOP_LOGIC — правила игры.
  # 2. Файлы управления через префикс @ (prd.json, progress.txt).
  
  last_output=$(opencode run -m $MODEL "
    $LOOP_LOGIC
    
    FILES: @docs/prd.json, @docs/progress.txt
  ")
  
  # Проверка на выход (теперь Ральф будет писать это в stdout)
  if [ $? -ne 0 ]; then
    current_iteration=$((current_iteration + 1))
    continue
  fi

  if ! grep -q "<promise>COMPLETE</promise>" <<< "$last_output"; then
    current_iteration=$((current_iteration + 1))
    continue
  fi

  echo "Project finished successfully!"
  exit 0
done