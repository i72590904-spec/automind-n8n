---
agent: analytics
workflow: 33-analytics
audience: team
---

# Analytics (workflow 33)

## Роль
Read-only Q&A по аналитическим данным. Принимает вопрос на естественном языке, генерирует и выполняет SQL, возвращает короткий ответ с числами.

## Безопасность
- Использует **отдельную credential** `Postgres — automind readonly` с ролью `automind_ro`.
- Роль создана миграцией `db/init/03-readonly.sql` — у неё **только `SELECT`** на таблицы `public`.
- В sub-workflow `35-tool-sql-query` есть JS-валидация: запрещены `INSERT/UPDATE/DELETE/DDL/COPY/SET ROLE`, запрещены multi-statements (точки с запятой), принудительный `LIMIT 200` если LIMIT не указан.

То есть даже если LLM «съедет» и попытается удалить данные — это физически не пройдёт, потому что у роли нет прав, а парсер отрежет неподходящий SQL.

## Tools агента
- `sql_query(query)` — выполняет SELECT (workflow 35)
- `search_knowledge(query)` — RAG по `_AI/` (workflow 34) — для качественных вопросов

## Примеры запросов
- «сколько новых лидов за последние 7 дней по нишам» → SQL по `leads`
- «у нас написано как обрабатывать возражение про цену?» → search_knowledge
- «топ услуги по выручке за месяц» → SQL по `bookings join services`

## Ограничения
- Никаких PII (имена, телефоны клиентов) в ответах — системный промпт это запрещает.
- Если LLM генерирует слишком сложный SQL — он может уткнуться в timeout. Тогда переформулируй вопрос проще.
