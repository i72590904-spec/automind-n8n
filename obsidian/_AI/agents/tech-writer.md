---
agent: tech-writer
workflow: 32-tech-writer-daily-report
audience: team
---

# Tech Writer (workflow 32)

## Роль
Генерирует ежедневные отчёты в Obsidian Vault. Запускается:
1. Cron-ом каждый день в 08:00 (локальное время сервера).
2. Вручную через Supervisor'а tool `daily_report`.

## Что собирает
SQL за последние 24 часа:
- новых записей (`bookings`)
- записей на вчера (`bookings.starts_at::date = yesterday`)
- новых лидов (`leads`)
- лидов в квалификации (`status='qualifying'`)
- закрытых сделок (`status='won'`)
- отправленных аутрич-сообщений
- эскалаций к человеку (`messages.payload ? 'escalate'`)

## Что пишет
Markdown-заметку `_AI/reports/YYYY-MM-DD.md` через workflow 12 (auto-commit в `ai-staging` ветку Vault).

Формат:
```markdown
---
date: 2026-04-28
generated_by: 32-tech-writer
stats: { ... }
---

# Отчёт за 2026-04-28

## Цифры
| Метрика | Значение |
|---|---|
...

## Что хорошо
...

## Что плохо
...

## Что делать сегодня
1. ...
```

## Промпт-настройка
- Тон: деловой, без эмодзи.
- Длина: ≤ 600 слов.
- Если данных мало — отметить и предложить что добавить в трекинг.

## Контроль качества
Раз в неделю просматривай 7 последних отчётов в Vault. Если AI «галлюцинирует» цифры — посмотри payload `Collect Stats` (запрос в БД), скорее всего проблема в SQL, а не в LLM.
