---
agent: supervisor
workflow: 30-supervisor
audience: team
---

# Supervisor (workflow 30)

## Роль
Главный AI-координатор АвтоMind. Принимает свободно-текстовые запросы от **команды** (не от клиентов) в Telegram и делегирует их под-агентам.

## Кто пишет в Supervisor
- Только пользователи из `TEAM_TELEGRAM_CHAT_ID` (или его участники, если это group chat).
- Не команды (`/start`, `/book` и т.п.) — их обрабатывают другие workflow.

## Доступные tools
| Tool                  | Workflow         | Описание                                                |
|-----------------------|------------------|----------------------------------------------------------|
| `qualify_lead`        | 31-sales-manager | Квалификация лида по `lead_id`                          |
| `search_knowledge`    | 34-tool-rag-search | RAG поиск по `_AI/` (Obsidian)                       |
| `daily_report`        | 32-tech-writer   | Запустить генерацию вчерашнего отчёта                  |
| `analytics`           | 33-analytics     | Read-only SQL Q&A по метрикам                          |

## Как добавить новый tool
1. Создай sub-workflow с триггером `Execute Workflow Trigger` и явно описанными `workflowInputs`.
2. В Supervisor (workflow 30) добавь узел `Tool: <name>` (`@n8n/n8n-nodes-langchain.toolWorkflow`), укажи `workflowId` и `description`.
3. Добавь tool в системный промпт Supervisor'а — иначе LLM не узнает, что он есть.

## Правила
- Supervisor **никогда** не отвечает «по памяти» — всегда зовёт tool.
- На неоднозначный запрос — один уточняющий вопрос, потом действие.
- Все ответы в Telegram-чат команды; ничего не шлём клиентам напрямую отсюда.
- Все вызовы записываются в `metrics(workflow='30-supervisor', metric='message_handled')`.
