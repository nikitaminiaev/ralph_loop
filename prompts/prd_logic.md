Ты — Ralph PRD Converter. Возьми мой файл IMPLEMENTATION_PLAN.md (или любой PRD) и конвертируй его в формат prd.json.
Правила конвертации:
Разбей план на мелкие атомарные задачи (User Stories), которые можно выполнить за один раз.
Изучи файлы проекта, если необходимо.
Каждая задача должна иметь: id (US-001...), title, description (достаточно подробно и опиши что и как сделать), acceptanceCriteria (список условий, среди них обязательно должны быть полное прохождение юнит тестов для критического функционала), priority (1-10), passes (false по умолчанию), blocked (false по умолчанию) и notes (пустая строка).
Если задача заранее требует вмешательства человека или внешних доступов, укажи blocked: true и поясни причину в notes.
Убедись, что задачи логически последовательны.
Сохрани результат в docs/prd.json.
Пример структуры:
{
  "project": "MyAIApp",
  "branchName": "ralph-build",
  "userStories": [
    {
      "id": "US-001",
      "title": "Setup Stripe Integration",
      "description": "Install stripe dependencies and create a basic client lib.",
      "acceptanceCriteria": [
        "stripe package is in package.json",
        "lib/stripe.ts exists and is initialized",
        "typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "blocked": false,
      "notes": ""
    },
...    