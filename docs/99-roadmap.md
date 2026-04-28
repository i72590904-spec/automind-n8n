# Дорожная карта АвтоMind по фазам

## Фаза 1 — Запуск фундамента ✅ (этот PR)

- [x] `docker-compose.yml` — n8n + PostgreSQL + Redis
- [x] Прикладная БД `automind` со схемой (services, clients, bookings, conversation_state, leads, messages, metrics)
- [x] Workflow `01 — Booking Bot` (Telegram → Postgres)
- [x] Workflow `02 — Reminder Bot` (Cron 24h/1h)
- [x] Документация по Windows-установке и Cloudflare Tunnel
- [x] CI: валидация JSON-файлов

## Фаза 2 — Obsidian как «мозг» ✅

- [x] Документация по подключению Local REST API (`docs/04-obsidian-setup.md`).
- [x] Workflow `10 — Obsidian: Read Note` — чтение по path.
- [x] Workflow `11 — Obsidian: Search Notes` — simple search.
- [x] Workflow `12 — Obsidian: Write Note` — запись с защитой от записи вне `_AI/inbox/`.
- [x] Шаблоны: `obsidian/_AI/AI_System_Specs.md`, `agents/booking-helper.md`, `agents/sales-manager.md`, `playbooks/lead-qualification.md`.
- [x] Vault примонтирован в `/vault` контейнера n8n (через `OBSIDIAN_VAULT_PATH`).

## Фаза 3 — Git-интеграция AI-агента ✅

- [x] Sub-workflow `13 — Vault Git Commit (ai-staging)` — git add/commit/push с валидацией путей.
- [x] AI коммитит **только** в `ai-staging` — branch захардкожен в Validate Input.
- [x] Документация по настройке Vault как git-репо (`docs/05-ai-staging-branch.md`).
- [x] Защита `main` — через GitHub Branch Protection (настраивается вручную).
- [x] Метрика `commit` пишется в таблицу `metrics` после каждого пуша.

## Фаза 4 — AI-команда (базовая) ✅

- [x] Workflow `20 — AI Booking Helper` + tools `20a/b/c` (list_services, start_booking, escalate).
- [x] Workflow `21 — VK Lead Parser` (groups.search по 6 нишам, апсерт в `leads`).
- [x] Workflow `22 — AI First Contact` (cron каждый час, AI-драфт → Telegram команды).
- [x] Workflow `23 — RAG Sync` — Obsidian → локальный pgvector (chunking + embeddings).
- [x] Migration `02-rag.sql` — pgvector extension, таблицы `notes`, `note_chunks`, `outreach_messages`, `ai_sessions`.
- [x] Документация: `docs/06-phase4-ai-rag.md`.

## Фаза 5 — Мульти-агенты с Супервайзером

- [ ] Workflow `30 — Supervisor` — главный координатор:
  - роутинг задач на под-агентов через `Switch`/`Execute Workflow`,
  - планирование (разбивает задачу на этапы, назначает агентов),
  - оценка эффективности по метрикам.
- [ ] Под-агенты:
  - `31 — Sales Manager`
  - `32 — Tech Writer`
  - `33 — Analytics`
- [ ] Договорённость: все AI-агенты при работе с Obsidian коммитят в `ai-staging`.

## Фаза 6 — Контроль и дашборд

- [ ] Loki + Grafana в `docker-compose.yml`.
- [ ] Workflow `40 — Metrics Aggregator` — пишет в таблицу `metrics`.
- [ ] Workflow `41 — Daily Report` — каждое утро шлёт сводку в Telegram.
- [ ] Алерты в Grafana (падение конверсии, нет лидов > N часов и т.д.).
- [ ] (опционально) Интеграция с Opik для трассировки AI-решений.

---

## Бизнес-привязка

Эта дорожная карта поддерживает финплан:

| Месяц    | Цель        | Что должно быть готово                                  |
|----------|-------------|----------------------------------------------------------|
| Май      | 400-800k    | Фаза 1 — продаём «Старт» (бот + напоминания, 30к)        |
| Июнь     | 3-5 млн     | Фаза 2-3 + 1й технарь умеет накатывать пакеты с гита     |
| Июль     | 8-12 млн    | Фаза 4 — «База» (60к) с AI-аутричем + CRM                |
| Август   | 15-20 млн   | Фаза 5 — «Про» (100к) с мульти-агентами + аналитика      |
| Сентябрь | 25-30 млн   | Фаза 6 — дашборд, метрики, режим автопилота 85%          |
