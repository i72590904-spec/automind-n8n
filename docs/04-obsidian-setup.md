# Фаза 2 — Obsidian как «мозг» AI-команды

Цель: дать AI-агентам чтение/запись твоей базы знаний в Obsidian через
**Local REST API**. Дальше эти заметки будут источником RAG (Фаза 4) и
живой памятью между сессиями.

## Архитектура

```
                   Windows host (твой ПК)
   ┌──────────────────────────────────────────────────────┐
   │  Obsidian.exe                                         │
   │   └─ плагин Local REST API → http://localhost:27123   │
   │                                                       │
   │  Vault на диске — папка с .md файлами                 │
   │   └─ git init, ветки main + ai-staging                │
   └──────────────────────────────────────────────────────┘
                       ▲                 ▲
       HTTP            │                 │ volume mount
                       │                 │ (для git commit)
   ┌───────────────────┴─────────────────┴─────────────────┐
   │  Docker Desktop                                        │
   │   └─ n8n container — обращается к Obsidian API:        │
   │      http://host.docker.internal:27123/vault/...       │
   │      и к /vault на FS через примонтированную папку.    │
   └────────────────────────────────────────────────────────┘
```

## 1. Устанавливаем Local REST API в Obsidian

1. В Obsidian: **Settings → Community plugins → Browse**.
2. Найди **Local REST API**, нажми **Install**, потом **Enable**.
3. Открой настройки плагина:
   - **Enable** ✅
   - **Encrypted (HTTPS) Server Port**: 27124 (можно оставить, но мы будем использовать HTTP — проще для интеграции внутри LAN).
   - **Non-encrypted (HTTP) Server**: ✅ Enable. Порт **27123**.
   - **API Key**: нажми **Copy** — будет нужен для n8n credential.
4. Перезапусти Obsidian.
5. Проверка с PowerShell:
   ```powershell
   $key = "ВСТАВЬ_API_KEY"
   Invoke-RestMethod -Uri "http://localhost:27123/" -Headers @{Authorization="Bearer $key"}
   ```
   Должен вернуться JSON с `service: "Obsidian Local REST API"`.

## 2. Структура Vault

Создай в корне Vault папку `_AI/` со следующими файлами:

```
_AI/
├── AI_System_Specs.md      # роли, промпты, правила всех агентов
├── agents/                  # инструкции для отдельных агентов
│   ├── booking-helper.md
│   ├── sales-manager.md
│   └── analyst.md
├── playbooks/              # типовые сценарии
│   ├── client-onboarding.md
│   └── lead-qualification.md
└── inbox/                   # сюда AI пишет черновики (потом ты переносишь)
```

Шаблоны в этом репо: `obsidian/_AI/` — скопируй их в свой Vault.

## 3. n8n credential

В n8n: **Credentials → Create credential → HTTP Header Auth** (любой generic header
auth работает; можно также через **Generic Credential Type → HTTP Bearer**).

- **Имя**: `Obsidian Local REST API`
- **Header Name**: `Authorization`
- **Header Value**: `Bearer ВСТАВЬ_API_KEY`

Также в `.env` добавлено:

```env
OBSIDIAN_API_URL=http://host.docker.internal:27123
```

> На Windows Docker Desktop `host.docker.internal` уже работает из коробки.
> На Linux добавь `extra_hosts: ["host.docker.internal:host-gateway"]` в
> `docker-compose.yml` (для n8n уже добавлено).

## 4. Тест workflow

После импорта `workflows/10-obsidian-read-note.json`:

1. Открой workflow в n8n.
2. В узле **Read Note** на вкладке **Execute Workflow** в поле `path` поставь `_AI/AI_System_Specs.md`.
3. Click **Execute Workflow**. Должен вернуться объект с `content`.

## 5. Что делать дальше

После того как Obsidian API отвечает и workflow читает заметки:
- Подключаем `13-obsidian-git-commit.json` (Фаза 3) — AI коммитит свои правки в `ai-staging`.
- В Фазе 4 строим RAG-пайплайн: при изменении заметки → embeddings → Supabase pgvector.
