# АвтоMind — n8n проект

Автоматизация для малого бизнеса (салоны, барбершопы, кафе, клиники, онлайн-школы)
на стеке **n8n + PostgreSQL + Redis + Telegram + AI**.

Это репозиторий **исходников**: docker-compose, workflow JSON-ы, миграции БД,
документация. Сами секреты (токены, API-ключи, пароли) **не коммитятся** —
они лежат в `.env` (локально) и в Credentials самого n8n.

## Содержание

- [Что внутри](#что-внутри)
- [Быстрый старт (Windows)](#быстрый-старт-windows)
- [Запуск Cloudflare Tunnel](#запуск-cloudflare-tunnel)
- [Импорт workflow в n8n](#импорт-workflow-в-n8n)
- [Подключение Credentials](#подключение-credentials)
- [Настройка вебхука Telegram](#настройка-вебхука-telegram)
- [Структура проекта](#структура-проекта)
- [Резервные копии](#резервные-копии)
- [Дорожная карта (по фазам)](#дорожная-карта)

---

## Что внутри

| Слой               | Чем покрыто                                                   |
|--------------------|----------------------------------------------------------------|
| Инфраструктура     | `docker-compose.yml` — n8n + Postgres + Redis (опционально cloudflared) |
| Схема данных       | `db/init/01-schema.sql` — services, clients, bookings, conversation_state, leads, messages, metrics |
| Автоматизации      | `workflows/*.json` — готовые workflow для импорта в n8n        |
| Документация       | `docs/` — пошаговые инструкции по фазам                        |
| Резервные копии    | `backups/` — туда экспортируются workflow перед изменениями    |

Готовые workflow:

1. **`01-booking-bot.json`** — Telegram-бот записи (услуга → дата → время → имя/телефон → сохранение).
2. **`02-reminder-bot.json`** — напоминания за 24 часа и за 1 час до записи.
3. **`10-obsidian-read-note.json`** — sub-workflow: чтение заметки Obsidian по path.
4. **`11-obsidian-search-notes.json`** — sub-workflow: simple search по Vault.
5. **`12-obsidian-write-note.json`** — sub-workflow: запись/перезапись заметки + автоматический git commit.
6. **`13-obsidian-git-commit.json`** — sub-workflow: коммит в ветку `ai-staging` репозитория Vault.
7. **`20-ai-booking-helper.json`** — AI-агент на Telegram (free-text → услуга/дата/время).
8. **`20a/20b/20c-tool-*.json`** — sub-workflow tools для AI-агента (list_services, start_booking, escalate).
9. **`21-vk-lead-parser.json`** — Cron 6h, парсер ВК групп по нишам в таблицу `leads`.
10. **`22-ai-first-contact.json`** — Cron 1h, AI генерирует первое сообщение → драфт в Telegram команды.
11. **`23-rag-sync.json`** — Cron 30 мин, индексация Obsidian заметок в pgvector через OpenAI embeddings.
12. **`30-supervisor.json`** — главный AI-агент команды в Telegram, маршрутизирует на под-агентов.
13. **`31-sales-manager.json`** — sub-workflow квалификации лидов (4 вопроса, рекомендация пакета).
14. **`32-tech-writer-daily-report.json`** — ежедневный отчёт-заметка в Obsidian Vault (cron 08:00).
15. **`33-analytics.json`** — read-only Q&A по метрикам через SQL и RAG.
16. **`34-tool-rag-search.json`** — общий sub-workflow для cosine-search по `note_chunks`.
17. **`35-tool-sql-query.json`** — sub-workflow для безопасного read-only SQL.
18. **`40-alerting.json`** — Cron 15 мин, проверяет аномалии (нет бронирований, много эскалаций, ошибки n8n) → Telegram.

Плюс стэк мониторинга в профиле `monitoring` docker-compose: **Loki** (логи) + **Promtail** (сборщик) + **Grafana** (дашборды). Преднастроенные дашборды: «АвтоMind Overview» и «AI Agents».

---

## Быстрый старт (Windows)

### Что нужно установить один раз

1. **Docker Desktop** для Windows: <https://www.docker.com/products/docker-desktop/>.
   - После установки запусти Docker Desktop и дождись, пока в трее значок станет зелёным.
   - В настройках включи интеграцию с WSL 2, если предложит.
2. **Git for Windows**: <https://git-scm.com/download/win>.
3. **PowerShell 7+** (необязательно, но удобнее): <https://aka.ms/powershell>.

### Клонируем репозиторий и готовим .env

В **PowerShell**:

```powershell
git clone https://github.com/i72590904-spec/automind-n8n.git
cd automind-n8n

# Копируем шаблон и редактируем
Copy-Item .env.example .env
notepad .env
```

В `.env` обязательно:

- задай **сильные пароли** для `POSTGRES_PASSWORD`, `APP_DB_PASSWORD`, `N8N_BASIC_AUTH_PASSWORD`, `REDIS_PASSWORD`;
- сгенерируй `N8N_ENCRYPTION_KEY` (никогда потом не меняй):

  ```powershell
  [Convert]::ToBase64String((1..32 | %{[byte](Get-Random -Max 256)}))
  ```

  Скопируй вывод в `N8N_ENCRYPTION_KEY=...`.
- `WEBHOOK_URL` пока оставь как есть — заполнишь после поднятия туннеля.

### Поднимаем стек

```powershell
docker compose up -d
docker compose ps
```

Должны быть запущены `automind-postgres`, `automind-redis`, `automind-n8n`.
n8n доступен на <http://localhost:5678> (логин/пароль из `.env`).

При первом запуске Postgres сам выполнит `db/init/00-create-app-db.sh` и
`db/init/01-schema.sql` — создаст БД `automind`, пользователя `automind` и все таблицы.

> Если ты уже запускал контейнер раньше и тома существуют — миграция автоматически не выполнится. Применяй вручную:
> ```powershell
> docker exec -i automind-postgres psql -U n8n -d n8n -f /db/init/01-schema.sql
> ```

### Логи

```powershell
docker compose logs -f n8n
docker compose logs -f postgres
```

### Остановить / стартовать заново

```powershell
docker compose down       # стоп без удаления данных
docker compose up -d      # запуск
docker compose down -v    # ОПАСНО: удалит все тома (БД, n8n)
```

---

## Запуск Cloudflare Tunnel

Telegram должен иметь возможность стучаться на n8n из интернета. На локальной
машине без публичного IP это решается туннелем. Самый простой вариант на
Windows — **quick tunnel** (без аккаунта Cloudflare, для разработки):

1. Скачай `cloudflared.exe`: <https://github.com/cloudflare/cloudflared/releases/latest> (файл `cloudflared-windows-amd64.exe`).
2. Положи рядом с `docker-compose.yml`, переименуй в `cloudflared.exe`.
3. В отдельном окне PowerShell:

   ```powershell
   .\cloudflared.exe tunnel --url http://localhost:5678
   ```

4. В выводе появится строка вида:

   ```
   Your quick Tunnel has been created! Visit it at:
   https://something-random.trycloudflare.com
   ```

5. Скопируй этот URL в `.env` → `WEBHOOK_URL=...` и перезапусти n8n:

   ```powershell
   docker compose up -d --force-recreate n8n
   ```

> ⚠️ Quick tunnels — временные: при перезапуске `cloudflared.exe` URL меняется,
> и Telegram-вебхук придётся переподключать. Для продакшена настрой **named tunnel**
> с собственным доменом — см. `docs/02-cloudflare-tunnel.md`.

Альтернатива: **ngrok** (`ngrok http 5678`) — тоже сгодится, но требует регистрации.

---

## Импорт workflow в n8n

1. Открой <http://localhost:5678>, залогинься.
2. Слева **Workflows → Add workflow → Import from file** (или меню `...` →
   `Import from File`).
3. Выбери файл из папки `workflows/`, например `workflows/01-booking-bot.json`.
4. После импорта в каждом узле, где использовались credentials, будет красный
   значок «No credentials» — это нормально. Перейди к следующему шагу.

---

## Подключение Credentials

В наших workflow используются 2 credential-а:

### 1. `Telegram Bot — АвтоMind`

> 🛑 **Этот шаг ты делаешь сам.** Я не прикасаюсь к токенам.

1. Получи токен у <https://t.me/BotFather> (`/newbot` или `/token` для существующего).
2. В n8n → **Credentials → Create credential → Telegram API**.
3. Имя: `Telegram Bot — АвтоMind` (важно — именно так, чтобы JSON-ы подцепились).
4. Access Token: вставь токен от BotFather. Сохрани.

### 2. `Postgres — automind app`

1. В n8n → **Credentials → Create credential → Postgres**.
2. Имя: `Postgres — automind app`.
3. Параметры:
   - Host: `postgres`
   - Database: значение `APP_DB_NAME` из `.env` (по умолчанию `automind`)
   - User: `APP_DB_USER` (по умолчанию `automind`)
   - Password: `APP_DB_PASSWORD`
   - Port: `5432`
   - SSL: `disable`
4. Нажми **Test connection** — должно быть зелёное `Connection successful`.

После этого открой каждый workflow и в красных узлах выбери созданные credentials.

---

## Настройка вебхука Telegram

n8n автоматически регистрирует вебхук в Telegram, когда workflow становится
**Active**. Условия:

1. `WEBHOOK_URL` в `.env` содержит публичный HTTPS URL (Cloudflare Tunnel / ngrok).
2. Контейнер n8n перезапущен после изменения `WEBHOOK_URL`.
3. Telegram credential подключён.

Активируй workflow `01 — Booking Bot` тумблером в правом верхнем углу.

Проверка:

- Напиши боту `/start` в Telegram.
- В n8n: **Executions** → должны появляться запуски.

Если Telegram не доходит, проверь зарегистрированный вебхук вручную:

```powershell
$Token = "ВСТАВЬ_СВОЙ_TOKEN"
Invoke-RestMethod "https://api.telegram.org/bot$Token/getWebhookInfo"
```

---

## Структура проекта

```
automind-n8n/
├── .env.example                # Шаблон переменных окружения
├── .gitignore
├── docker-compose.yml          # n8n + Postgres + Redis (+ vault mount)
├── README.md                   # Этот файл
├── db/
│   └── init/
│       ├── 00-create-app-db.sh # Создаёт прикладную БД и юзера
│       └── 01-schema.sql       # Схема таблиц (services, bookings, ...)
├── workflows/
│   ├── 01-booking-bot.json     # Telegram-бот записи
│   ├── 02-reminder-bot.json    # Напоминания за 24h и 1h
│   ├── 10-obsidian-read-note.json
│   ├── 11-obsidian-search-notes.json
│   ├── 12-obsidian-write-note.json
│   └── 13-obsidian-git-commit.json
├── obsidian/_AI/               # Шаблоны для копирования в твой Obsidian Vault
│   ├── AI_System_Specs.md
│   ├── agents/
│   └── playbooks/
├── vault-placeholder/          # Заглушка для docker volume, если Vault не примонтирован
├── backups/                    # Сюда экспортируй свои workflow перед правками
├── docs/
│   ├── 01-windows-setup.md     # Подробная установка под Windows
│   ├── 02-cloudflare-tunnel.md # Named tunnel с собственным доменом
│   ├── 03-importing-workflows.md
│   ├── 04-obsidian-setup.md    # Local REST API в Obsidian
│   ├── 05-ai-staging-branch.md # Git-интеграция AI в ветку ai-staging
│   └── 99-roadmap.md           # Полная дорожная карта по фазам
└── .github/workflows/ci.yml    # Валидация JSON в PR-ах
```

---

## Резервные копии

Перед каждой правкой workflow в UI n8n — экспортируй текущую версию:

- В n8n: **Workflows → workflow → меню `...` → Download** → положи файл в `backups/`.
- Или через API/CLI (см. `docs/03-importing-workflows.md`).

`backups/` под `.gitignore` для сырых дампов; чистовые версии переноси в
`workflows/` после ревью.

---

## Дорожная карта

Полный план по фазам — в [`docs/99-roadmap.md`](docs/99-roadmap.md).

| Фаза | Что делаем                                              | Статус        |
|------|---------------------------------------------------------|---------------|
| 1    | n8n + Postgres + Telegram, бот записи и напоминания     | ✅ Done        |
| 2    | Obsidian Local REST API + структурированная база знаний | ✅ Done        |
| 3    | Git-интеграция AI-агента (ветка `ai-staging`)           | ✅ Done        |
| 4    | AI-агент booking + парсер ВК + AI-аутрич + RAG (pgvector) | ✅ Done        |
| 5    | Супервайзер + мульти-агенты (Sales / Analytics / Tech Writer) | ✅ Done    |
| 6    | Логи (Loki) + дашборд (Grafana) + Alerting              | ✅ Done       |
| 7+   | Opik (AI-trace), CRM-интеграция, школа/контент          | ⏳ Опционально|

---

## Лицензия / приватность

Приватный репозиторий. Внутренние материалы АвтоMind. Никаких секретов в коммитах.
