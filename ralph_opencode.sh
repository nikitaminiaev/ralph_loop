#!/bin/bash

# Путь к тулкиту
TOOLKIT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

PROJECT_PATH=$1
ITERATIONS=$2

if [ -z "$PROJECT_PATH" ] || [ -z "$ITERATIONS" ]; then
  echo "Usage: ./ralph_opencode.sh <project_path> <iterations>"
  exit 1
fi

cd "$PROJECT_PATH" || exit

# Загружаем универсальную логику цикла (как вести себя Ральфу)
LOOP_LOGIC=$(cat "$TOOLKIT_PATH/prompts/loop_logic.md")

mkdir -p docs
if [ ! -f docs/progress.txt ]; then
  touch docs/progress.txt
fi

for ((i=1; i<=$ITERATIONS; i++)); do
  echo "--- Ralph Loop: Iteration $i ---"

  # Мы передаем:
  # 1. LOOP_LOGIC (из тулкита) — правила игры.
  # 2. Файлы управления через префикс @ (prd.json, progress.txt).
  
  last_output=$(opencode run "
    $LOOP_LOGIC
    
    ФАЙЛЫ УПРАВЛЕНИЯ: @docs/prd.json, @docs/progress.txt
  ")
  
  # Проверка на выход (теперь Ральф будет писать это в stdout)
  if [ $? -ne 0 ]; then
    continue
  fi

  if ! grep -q "<promise>COMPLETE</promise>" <<< "$last_output"; then
    continue
  fi

  echo "Project finished successfully!"
  exit 0
done