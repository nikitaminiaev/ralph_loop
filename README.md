# Ralph Loop — CLI агент в цикле

Этот каталог содержит минимальный тулкит для запуска CLI-агента, который работает по PRD в цикле и обновляет прогресс.

## Что делает цикл
- Читает `docs/prd.json` и выбирает самую приоритетную задачу с `passes: false` и `blocked: false`
- Выполняет одну задачу за итерацию
- Запускает тесты, коммитит изменения, обновляет `docs/prd.json` и `docs/progress.txt`
- Если задача требует человека, ставит `blocked: true` и описывает причину в `notes`
- Если больше нет задач с `passes: false` и `blocked: false`, выводит `<promise>COMPLETE</promise>`

## Структура в целевом проекте
В проекте, над которым работает агент, должны быть:
- `docs/prd.json` — список задач (генерируется конвертером)
- `docs/progress.txt` — пустой файл для логов агента

## Быстрый старт
1) Создай обычный текстовый файл с тем, что ты хочешь сделать (например, `IMPLEMENTATION_PLAN.md`).
2) Сконвертируй его в PRD:
   ```bash
   ./prd-converter.sh /path/to/project IMPLEMENTATION_PLAN.md
   ```
3) При желании доработай PRD в режиме plan:
   ```bash
   opencode run "Проверь docs/prd.json и улучши формулировки" --mode plan
   ```
4) Запусти цикл:
   ```bash
   ./ralph_opencode.sh /path/to/project 20
   ```
5) Наблюдай: агент будет брать задачу `US-001`, выполнять её, запускать тесты, делать коммит, обновлять `docs/prd.json` и переходить к следующей итерации.
   Если лимит итераций достигнут, скрипт спросит продолжать ли дальше.

## Запуск через tmux (чтобы не зависеть от SSH)
1) Подключись к Raspberry Pi по SSH.
2) Запусти `tmux`:
   ```bash
   tmux new -s ralph
   ```
3) Запусти цикл внутри `tmux`:
   ```bash
   ./ralph_opencode.sh /path/to/project 100
   ```
4) Отсоединись от сессии:
   - Нажми `Ctrl+B`, затем `D`
5) Закрой SSH или выключи свой ПК — процесс на Pi продолжит работать.
6) Чтобы вернуться:
   ```bash
   tmux attach -t ralph
   ```

## Скрипты
### `prd-converter.sh`
Конвертирует текстовый план в `docs/prd.json` с полями `passes` и `blocked`.

Использование:
```bash
./ralph_loop/prd-converter.sh <project_path> <input_file.md>
```

### `ralph_opencode.sh`
Запускает итеративный цикл Ralph Loop.
По умолчанию safety-stop — 10000 итераций, после чего скрипт спросит, продолжать ли дальше.

Использование:
```bash
./ralph_loop/ralph_opencode.sh <project_path> [iterations]
```
