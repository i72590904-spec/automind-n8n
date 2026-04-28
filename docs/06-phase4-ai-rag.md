# Фаза 4 — AI-команда, парсер ВК, аутрич, RAG

## Что добавляется

### Новые credentials в n8n (всё ручное, токены ты вводишь сам)

| Credential                   | Тип n8n              | Base URL                              | Где взять ключ                                       |
|------------------------------|----------------------|----------------------------------------|--------------------------------------------------------|
| `OpenRouter — АвтоMind`      | OpenAI               | `https://openrouter.ai/api/v1`        | https://openrouter.ai/keys                            |
| `OpenAI — embeddings`        | OpenAI               | (default `https://api.openai.com/v1`) | https://platform.openai.com/api-keys                  |
| (без credential, в `.env`)   | env `VK_ACCESS_TOKEN` | —                                     | https://vk.com/apps?act=manage → Сервисный ключ      |
| (без credential, в `.env`)   | env `TEAM_TELEGRAM_CHAT_ID` | —                              | `getUpdates` твоего бота                              |

**Почему две credentials типа «OpenAI», а не одна:**
- OpenRouter отдаёт OpenAI-совместимый API → штатный узел `OpenAI Chat Model` его понимает, в credential просто меняем base URL и подсовываем ключ от OpenRouter. Через него ходим в Claude Sonnet 4.5 (`anthropic/claude-sonnet-4.5`).
- OpenRouter **не даёт endpoint для embeddings**. Поэтому workflow 23 (RAG-синк) отдельной credential ходит в OpenAI за `text-embedding-3-small`. Расход на embeddings копеечный (~$0.02 за 1М токенов).
- Если в будущем перейдёшь на Voyage/Jina/Cohere для embeddings — поменяешь только credential workflow 23, остальное не тронется.

### Как создать credential `OpenRouter — АвтоMind` в n8n

1. **Settings → Credentials → New** → выбери тип **OpenAI**.
2. Имя: `OpenRouter — АвтоMind` (точно так, чтобы JSON автоматически слинковался).
3. **Base URL**: `https://openrouter.ai/api/v1`
4. **API Key**: твой OpenRouter ключ (формат `sk-or-v1-...`).
5. Save → Test (должен вернуть OK).

### Как создать credential `OpenAI — embeddings`

1. **Settings → Credentials → New** → тип **OpenAI**.
2. Имя: `OpenAI — embeddings`.
3. Base URL — оставь дефолтный (`https://api.openai.com/v1`).
4. API Key — обычный ключ OpenAI с https://platform.openai.com/api-keys.
5. Save → Test.

### Новые таблицы (см. `db/init/02-rag.sql`)

- `notes` — снапшоты заметок Vault.
- `note_chunks` — чанки + векторы (1536 dim, OpenAI `text-embedding-3-small`).
- `outreach_messages` — переписка с лидами (отдельно от `messages`).
- `ai_sessions` — короткая память диалога AI Agent.

Если стек уже запущен с обычным `postgres:16-alpine` — нужно пересоздать
контейнер на `pgvector/pgvector:pg16`:

```powershell
docker compose down
docker compose up -d
# Init-скрипты из db/init/ запускаются ТОЛЬКО при первой инициализации тома.
# Если volume postgres_data уже существует, выполни миграцию вручную:
docker exec -it automind-postgres psql -U automind -d automind -f /db/init/02-rag.sql
```

### Workflow

| Файл                                | Назначение                                              |
|-------------------------------------|----------------------------------------------------------|
| `20-ai-booking-helper.json`        | AI Agent на Telegram, отвечает на свободный текст        |
| `20a-tool-list-services.json`      | Tool: список услуг                                       |
| `20b-tool-start-booking.json`      | Tool: создать запись                                     |
| `20c-tool-escalate.json`           | Tool: передать диалог человеку                          |
| `21-vk-lead-parser.json`           | Cron каждые 6h, парсит группы VK по нишам в `leads`     |
| `22-ai-first-contact.json`         | Cron каждый час, AI пишет драфт первого сообщения        |
| `23-rag-sync.json`                 | Cron каждые 30 мин, индексирует Obsidian → pgvector     |

## Как получить VK access_token

VK поддерживает несколько типов токенов. Для `groups.search` достаточно
**сервисного токена** (server-side, без пользователя):

1. Заходишь в https://vk.com/apps?act=manage
2. **Создать приложение** → тип «Standalone» → название «АвтоMind Lead Parser».
3. После создания — **Settings** → копируешь **Сервисный ключ доступа** (это и есть token).
4. Добавляешь в `.env`:
   ```env
   VK_ACCESS_TOKEN=vk1.a.XXXXXX
   ```
5. Перезапускаешь n8n: `docker compose up -d --force-recreate n8n`.

> Если планируешь **писать сообщения в VK** (а не только парсить публичные группы)
> — нужен **пользовательский токен** с правами `messages,groups,offline`. Это
> делается через VK OAuth implicit flow. Сейчас в `22-ai-first-contact.json`
> сообщения **в VK не отправляются**, только драфты в Telegram-чат команды для
> ручной валидации. Авто-отправку включим, когда отладишь промпт.

## Как получить TEAM_TELEGRAM_CHAT_ID

Самый простой способ:
1. Напиши боту АвтоMind `/start`.
2. Открой `https://api.telegram.org/bot<TOKEN>/getUpdates` в браузере.
3. Найди в ответе `"chat":{"id":NNNNNN,"type":"private"}` — это твой `chat_id`.
4. В `.env`:
   ```env
   TEAM_TELEGRAM_CHAT_ID=123456789
   ```

Если хочешь алерты в групповой чат — добавь бота в группу, дай ему права
читать/писать, отправь любое сообщение, перевыполни `getUpdates`. Появится
`chat.id` группы (отрицательное число).

## AI Agent: как работает workflow 20

```
Telegram message
   │
   ▼
Prepare Input  (фильтр: только свободный текст, не команды)
   │
   ▼
AI Agent (LangChain) ◀──── OpenAI Chat Model (gpt-4o-mini)
                       ◀──── Postgres Memory (window 8 сообщений по session_key)
                       ◀──── Tool: list_services
                       ◀──── Tool: start_booking
                       ◀──── Tool: escalate
   │
   ▼
Send Telegram Reply  →  Record Metric
```

Tools — это **отдельные workflow** (`20a`, `20b`, `20c`). После импорта в
основном `20-ai-booking-helper.json` нужно вручную проставить ID этих
sub-workflow в полях `Tool: ...` (placeholder `REPLACE_WITH_TOOL_*_ID`).

## RAG-пайплайн (workflow 23)

1. Каждые 30 мин дёргаем `GET /vault/_AI/` через Local REST API.
2. Для каждого `.md` читаем содержимое.
3. Считаем `sha256(content)`, апсертим в `notes`. Если хеш не изменился — `indexed_at` остаётся, выходим.
4. Чанкуем по абзацам в окна ~800 символов.
5. Эмбеддим через `text-embedding-3-small` (1536 dim).
6. Апсертим в `note_chunks` с заменой существующих чанков.

**Cтоимость на эмбеддинги:** `text-embedding-3-small` стоит $0.02 за 1M токенов.
Для базы знаний на 10к слов это ~$0.0003 за полную переиндексацию.

## Использование RAG в других AI-агентах (примеры)

В n8n LangChain Agent можно подключить **Vector Store Tool** (новый узел
типа `@n8n/n8n-nodes-langchain.vectorStorePGVector` + `toolVectorStore`):

```
AI Agent ─ tool ─→ PGVector Tool ─→ Postgres (note_chunks) с cosine similarity
```

Это будет добавлено в Фазе 5 (Супервайзер): он будет использовать RAG для
ответа на «как у нас принято делать X».

## Контрольный список запуска Фазы 4

- [ ] PR #3 смерджен.
- [ ] `docker compose down` → `docker compose up -d` (новый образ pgvector).
- [ ] Если volume сохранился: `docker exec -it automind-postgres psql -U automind -d automind -f /db/init/02-rag.sql` (или просто пересоздать volume — потеряются записи).
- [ ] Credentials в n8n: `OpenAI — АвтоMind` создан.
- [ ] `.env`: `VK_ACCESS_TOKEN`, `TEAM_TELEGRAM_CHAT_ID` заполнены.
- [ ] Workflow 20a/20b/20c импортированы. Активируй их.
- [ ] Workflow 20 импортирован, в нодах Tool проставлены ID sub-workflow.
- [ ] Workflow 21, 22, 23 импортированы. Активируй (Cron сработает по расписанию).
- [ ] Тест 21: `docker exec -it automind-postgres psql -U automind -d automind -c "SELECT * FROM leads WHERE source='vk' ORDER BY id DESC LIMIT 5;"` — должны быть строки.
- [ ] Тест 22: подождать час → драфт прилетит тебе в Telegram.
- [ ] Тест 23: создай заметку `_AI/inbox/test.md` через workflow 12 → подожди 30 мин → `SELECT path, indexed_at FROM notes;` — должна появиться запись.
