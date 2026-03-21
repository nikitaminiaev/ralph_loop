#!/bin/bash
# Общее ядро цикла. Не запускать напрямую.
# Источник: вызывается через `source` из ralph_opencode.sh / ralph_research.sh.
#
# Ожидаемые переменные от вызывающего скрипта:
#   MODEL          — модель opencode
#   PROJECT_PATH   — путь к целевому проекту
#   ITERATIONS     — лимит итераций (опционально)
#   TOOLKIT_PATH   — директория ralph_loop
#   LOOP_LOGIC     — содержимое .md-файла с логикой агента
#   CONTEXT_FILES  — строка @-файлов для opencode (напр. "@docs/prd.json, @docs/progress.txt")
#   LABEL          — метка в логе итераций (напр. "Ralph Loop")
#   CHECK_COMPLETE — "true" если цикл должен завершаться по <promise>COMPLETE</promise>

SAFETY_STOP=10000

cd "$PROJECT_PATH" || exit

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

  echo "--- ${LABEL}: Iteration $current_iteration ---"

  last_output=$(opencode run -m "$MODEL" "
    $LOOP_LOGIC

    FILES: $CONTEXT_FILES
  ")
  exit_code=$?

  if [ "${CHECK_COMPLETE:-false}" = "true" ]; then
    if [ $exit_code -ne 0 ]; then
      current_iteration=$((current_iteration + 1))
      continue
    fi
    if grep -q "<promise>COMPLETE</promise>" <<< "$last_output"; then
      echo "Project finished successfully!"
      exit 0
    fi
  fi

  current_iteration=$((current_iteration + 1))
done
