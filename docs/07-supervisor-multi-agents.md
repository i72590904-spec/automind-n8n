# Фаза 5 — Супервайзер и мульти-агенты

## Что добавляется

### Workflow

| Файл                                    | Назначение                                                     |
|-----------------------------------------|------------------------------------------------------------------|
| `30-supervisor.json`                    | Главный AI-агент в Telegram (только команда). Tools: 31, 32, 33, 34. |
| `31-sales-manager.json`                 | Квалификация лидов (sub-workflow по `lead_id`).                 |
| `32-tech-writer-daily-report.json`      | Ежедневный отчёт в Obsidian Vault (cron 08:00 + ручной запуск). |
| `33-analytics.json`                     | Read-only Q&A по метрикам.                                       |
| `34-tool-rag-search.json`               | Sub-workflow для RAG поиска (используется всеми агентами).      |
| `35-tool-sql-query.json`                | Sub-workflow для безопасного SELECT (только Analytics).         |

### Новая Postgres роль

Миграция `db/init/03-readonly.sql` создаёт роль `automind_ro` с **только SELECT** на все таблицы `public`. Это нужно для Analytics-агента: даже если LLM сгенерирует деструктивный SQL, он физически не выполнится.

Если Postgres volume уже существует, применить миграцию вручную:
```powershell
docker exec -it automind-postgres psql -U automind -d automind -f /db/init/03-readonly.sql
```

И задать пароль (по умолчанию роль создаётся без пароля; если хочешь пароль — заранее):
```powershell
docker exec -it automind-postgres psql -U postgres -d automind -c "ALTER ROLE automind_ro WITH PASSWORD 'STRONG_PASSWORD_HERE'"
```

## Credentials в n8n

| Credential                       | Тип n8n      | Параметры                                              |
|----------------------------------|--------------|----------------------------------------------------------|
| `OpenRouter — АвтоMind`          | OpenAI       | base URL `https://openrouter.ai/api/v1`, твой ключ     |
| `OpenAI — embeddings`            | OpenAI       | дефолтный base URL, ключ OpenAI                        |
| `Postgres — automind app`        | Postgres     | host=postgres, db=automind, user=automind             |
| `Postgres — automind readonly`   | Postgres     | host=postgres, db=automind, user=automind_ro **(новая)** |
| `Telegram Bot — АвтоMind`        | Telegram     | token от BotFather                                      |
| `Obsidian Local REST API`        | HTTP Header Auth | Authorization: Bearer <key>                          |

## Связь tool ↔ workflow ID

Это самая хрупкая часть. Каждый tool в Supervisor (и в других агентах) ссылается на ID sub-workflow, а ID генерируется n8n при импорте — на твоей машине он будет другим, чем у меня.

**Порядок импорта (чтобы потом меньше править):**

1. **Sub-workflows сначала** (чтобы получить ID):
   - 34-tool-rag-search
   - 35-tool-sql-query
   - 12-obsidian-write-note (уже есть)
2. **Уровень-1 агенты:**
   - 31-sales-manager — открой, в `Tool: search_knowledge` подставь ID workflow 34
   - 32-tech-writer-daily-report — в `Write Note (workflow 12)` подставь ID workflow 12
   - 33-analytics — в `Tool: sql_query` подставь ID workflow 35, в `Tool: search_knowledge` — ID workflow 34
3. **Supervisor (30):** open, и подставь ID workflows 34, 31, 32, 33 в соответствующие узлы Tool.

После импорта: **Save → Activate** каждый workflow по очереди.

## Поток данных

```
Telegram (команда пишет супервайзеру)
   │
   ▼
30-supervisor (Claude Sonnet 4.5)
   ├─ Tool: search_knowledge → 34-tool-rag-search → pgvector
   ├─ Tool: qualify_lead    → 31-sales-manager
   │                            ├─ Tool: search_knowledge → 34
   │                            └─ UPDATE leads
   ├─ Tool: daily_report    → 32-tech-writer
   │                            ├─ SQL stats
   │                            └─ Execute: 12-obsidian-write-note → git push ai-staging
   └─ Tool: analytics       → 33-analytics
                                ├─ Tool: sql_query → 35 → readonly Postgres
                                └─ Tool: search_knowledge → 34
```

## Проверка

После активации Supervisor'а напиши ему в Telegram:
- «Что у нас написано в скриптах продаж про возражение по цене?»
  → Supervisor → search_knowledge → ответ из `_AI/playbooks/lead-qualification.md`
- «Сколько новых лидов за вчера?»
  → Supervisor → analytics → SQL → число
- «Сделай дневной отчёт»
  → Supervisor → daily_report → tech-writer пишет заметку, шлёт ссылку
- «Квалифицируй лида 12»
  → Supervisor → qualify_lead(12) → sales-manager обновляет leads.status

## Стоимость

Claude Sonnet 4.5 через OpenRouter — ~$3 за 1M input / $15 за 1M output (та же цена, что напрямую в Anthropic + 5% маржа OpenRouter).

Прикидка на день при 50 запросов в Supervisor + 10 квалификаций + 1 отчёт + 5 analytics:
- ~30k input + 15k output токенов
- **≈ $0.32 в день**, **≈ $10 в месяц**

Embeddings (OpenAI `text-embedding-3-small`) для RAG — копейки.

## Что НЕ входит в Фазу 5

- Loki + Grafana (Фаза 6)
- Auto-send в VK (workflow 22 пока шлёт драфты в Telegram)
- Voice/STT для Supervisor (TODO)
- Дообучение/fine-tuning под наши скрипты — пока работаем чисто на промптах + RAG
