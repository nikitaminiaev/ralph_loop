# Coach-Player — actor-critic надстройка над Ralph Loop

Эта директория добавляет к ralph_loop **actor-critic** цикл в стиле
[dhanji/g3](https://github.com/dhanji/g3) (coach-player loop), не трогая
существующие скрипты (`ralph_opencode.sh`, `ralph_research.sh`,
`prd-converter.sh`, `ralph_core.sh`, `prompts/`).

## Идея

- **Player** — тот же агент, что и в обычном ralph-loop: читает `docs/prd.json`,
  берёт одну user story за итерацию, реализует, гоняет тесты, коммитит,
  проставляет `passes: true`.
- **Coach** — отдельный `opencode run` **со свежим контекстом**, запускается
  сразу после Player. Читает `prd.json`, `progress.txt` и `git diff HEAD~1`
  последнего коммита. Его задача:
  - проверить, что закрытая US реально соответствует своим `acceptanceCriteria`;
  - при расхождении — вернуть `passes: false`, дописать замечания в
    `docs/coach_feedback.md`, отметить это в `docs/coach_history.md`;
  - при ошибочном `blocked: true` — разблокировать;
  - при явной дыре в PRD — добавить новую US (консервативно);
  - выдать `<promise>APPROVED</promise>` только если всё сходится.
- Player на следующей итерации первым делом читает `coach_feedback.md` и
  чинит замечания — только потом берёт новую US.

Почему это работает: каждый `opencode run` — новый процесс с чистым контекстом,
так что роль "свежего ревьюера" достаётся бесплатно, без отдельной
инфраструктуры агентов.

## Поток одной итерации

```
Player (opencode run, prompt=player_logic.md)
  → правит код / prd.json / progress.txt, коммитит
  → может вывести <promise>COMPLETE</promise>

Coach  (opencode run, prompt=coach_logic.md, fresh context)
  → читает prd.json + git diff HEAD~1
  → правит prd.json, coach_feedback.md, coach_history.md
  → может вывести <promise>APPROVED</promise>

если Player=COMPLETE и Coach=APPROVED → выход
иначе → следующая итерация
```

## Артефакты, которые появятся в проекте

| Файл | Кто пишет | Назначение |
|---|---|---|
| `docs/prd.json` | Player, Coach | То же, что и в обычном ralph-loop. Coach может ревёртить `passes` и разблокировать задачи. |
| `docs/progress.txt` | Player | Краткий лог прогресса (как было). |
| `docs/coach_feedback.md` | Coach пишет, Player вычищает | Живая очередь замечаний. Формат: `## US-XXX` + bullets. |
| `docs/coach_history.md` | Coach | Append-only аудит ревью (для человека). |

Player и Coach работают с одним и тем же `docs/prd.json`, но с
непересекающимися правами на остальные файлы.

## Запуск

PRD готовится тем же конвертером, что и для обычного ralph-loop:

```bash
MODEL=opencode/your-model ./ralph_loop/prd-converter.sh /path/to/project IMPLEMENTATION_PLAN.md
```

Запуск coach-player цикла:

```bash
# одна модель для обоих
MODEL=opencode/your-model \
  ./ralph_loop/coach_player/ralph_coach_player.sh /path/to/project 100

# разные модели: Player подешевле/побыстрее, Coach поумнее
MODEL=opencode/big-pickle COACH_MODEL=opencode/smarter-model \
  ./ralph_loop/coach_player/ralph_coach_player.sh /path/to/project 100
```

Параметры:
- `<project_path>` — путь к целевому проекту с `docs/prd.json`.
- `[iterations]` — опционально, лимит итераций (по умолчанию 10000 с подтверждением).

### Конфиг через .env (по желанию)

Чтобы не писать каждый раз `MODEL=...` в командной строке, скопируйте пример:

```bash
cp ralph_loop/coach_player/.env.example ralph_loop/coach_player/.env
# отредактируйте под свою модель / пороги
./ralph_loop/coach_player/ralph_coach_player.sh /path/to/project 100
```

`.env` лежит рядом со скриптом (не в целевом проекте) и автоматически подгружается. Приоритет значений:

```
CLI env  >  .env  >  хардкод-дефолты в скрипте
```

То есть `MODEL=foo ./ralph_coach_player.sh ...` по-прежнему переопределит `MODEL` из `.env`. `.env` git-ignored — в репо коммитится только `.env.example`.

## Защиты от зацикливания

Цикл помимо обычного `SAFETY_STOP=10000` имеет три встроенных предохранителя:

| Проблема | Защита | Env-переменная | Код выхода |
|---|---|---|---|
| Спор Player ↔ Coach по одной US (Player ставит `passes:true`, Coach ревёртит, по кругу) | Счётчик последовательных revert'ов по каждой US; при достижении лимита — остановка с просьбой вмешаться | `MAX_REVERTS_PER_US` (default 3) | 2 |
| Player буксует и не делает новых коммитов | Сравнение `git rev-parse HEAD` до/после итерации; счётчик итераций без движения | `MAX_NO_PROGRESS_TURNS` (default 5) | 3 |
| `opencode run` падает (сеть, rate limit, пустой ответ) | Retry с экспоненциальным бэкоффом 5s / 15s / 45s. Если не получилось — пропускаем итерацию | `MAX_RETRIES` (default 3) | — |

Счётчики хранятся в `docs/.coach_player_state` (плоский `key=value` файл). При явном закрытии одной US счётчик revert'ов по другим US сбрасывается, чтобы старый временный спор не стрельнул позже.

Чтобы механизм спора работал, Coach в каждом ответе выводит машиночитаемую строку:
```
COACH_REVERTED: US-003 US-007    # если что-то ревёртил
COACH_REVERTED:                  # если нет
```
— это часть промпта в [`prompts/coach_logic.md`](prompts/coach_logic.md).

Коды выхода:
- `0` — успешное завершение (Player=COMPLETE ∧ Coach=APPROVED)
- `2` — остановка из-за `MAX_REVERTS_PER_US`
- `3` — остановка из-за `MAX_NO_PROGRESS_TURNS`

## Запуск через tmux

Так же, как обычный ralph-loop:

```bash
tmux new -s ralph-cp
MODEL=opencode/your-model ./ralph_loop/coach_player/ralph_coach_player.sh /path/to/project 100
# Ctrl+B, D — отсоединиться
# tmux attach -t ralph-cp — вернуться
```

## Когда использовать coach-player вместо обычного ralph-loop

- Нужна более строгая проверка, что `passes: true` действительно заслужено.
- Player-модель склонна к быстрому "галочкованию" задач.
- Хочется использовать разные модели для имплементации и ревью.

Для простых PRD, где Player справляется без ревью, продолжайте использовать
обычный `ralph_opencode.sh` — он дешевле по токенам.

## Файлы

- [`ralph_coach_player.sh`](ralph_coach_player.sh) — точка входа.
- [`coach_core.sh`](coach_core.sh) — ядро цикла Player → Coach.
- [`prompts/player_logic.md`](prompts/player_logic.md) — промпт Player (расширение обычного `loop_logic.md` с учётом `coach_feedback.md`).
- [`prompts/coach_logic.md`](prompts/coach_logic.md) — промпт Coach (критик, правит только docs-файлы, не код).
