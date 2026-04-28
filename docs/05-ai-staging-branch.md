# Фаза 3 — Git-интеграция AI-агента (ветка `ai-staging`)

## Что хотим

AI-агенты должны иметь право **читать и писать** базу знаний в Obsidian, но
их правки должны:

1. Складываться в отдельную ветку `ai-staging`.
2. Никогда не коммититься напрямую в `main`.
3. Быть проверяемыми тобой через Pull Request (можешь даже автогенерить PR через GitHub API).

## Как настроить (на твоём Windows-хосте)

### 1. Делаем Vault git-репозиторием

Открой PowerShell в папке Vault:

```powershell
cd "C:\Users\<твой_пользователь>\Documents\Vault"
git init -b main

# .gitignore: исключаем кэш Obsidian
@"
.obsidian/workspace*
.obsidian/cache
.trash/
"@ | Out-File -Encoding utf8 .gitignore

git add .
git commit -m "init: vault baseline"
```

### 2. Заводим репо для Vault

Лучше отдельный приватный репо, например `automind-vault`. Создай на GitHub
вручную (как и для основного репо, см. README основного проекта), затем:

```powershell
git remote add origin https://github.com/i72590904-spec/automind-vault.git
git push -u origin main

# Создаём ветку для AI
git checkout -b ai-staging
git push -u origin ai-staging

git checkout main
```

### 3. Авторизация для пушей из Docker

Нам нужен способ для n8n-контейнера выполнять `git push`. Самый простой путь —
**Personal Access Token (PAT)** + git credential helper в файл.

1. На GitHub: **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token (classic)**.
   - Scopes: `repo` (полный).
   - Срок: 90 дней (потом перевыпустишь).
2. Скопируй токен (начинается с `ghp_...`).

> 🛑 **Этот токен — секрет.** В репо НЕ коммитится. В `.env` НЕ кладётся.
> Хранится **только** внутри n8n credentials.

### 4. Добавляем credential в n8n

В n8n: **Credentials → Create credential → Generic Credential Type → Header Auth**.

- Имя: `GitHub Vault Token`
- Header Name: `Authorization`
- Header Value: `Bearer ghp_...`

(Использоваться будет в Execute Command узле через переменную окружения
`GH_TOKEN_VAULT`.)

### 5. Mount Vault в контейнер n8n

В `.env` укажи:

```env
OBSIDIAN_VAULT_PATH=C:\Users\<твой_пользователь>\Documents\Vault
```

В `docker-compose.yml` уже добавлен volume:

```yaml
- ${OBSIDIAN_VAULT_PATH:-./vault-placeholder}:/vault
```

Пересоздай контейнер: `docker compose up -d --force-recreate n8n`.

Проверка — внутри контейнера должен появиться `/vault/.git`:

```powershell
docker exec automind-n8n ls -la /vault | Select-String ".git"
```

### 6. Внутри контейнера — однократная настройка git identity

```powershell
docker exec automind-n8n sh -c '
  apk add --no-cache git 2>/dev/null || true   # на n8nio/n8n уже есть, но на всякий
  git config --global user.email "ai@automind"
  git config --global user.name  "АвтоMind AI"
  git config --global --add safe.directory /vault
'
```

(Это нужно сделать один раз; если контейнер пересоздаётся — повторить, либо
вынести в кастомный Dockerfile.)

### 7. Workflow `13-obsidian-git-commit.json`

Sub-workflow, который вызывается другими AI-агентами. Принимает на вход:

```json
{
  "message": "AI: добавил заметку про X",
  "files": ["_AI/inbox/something.md"]   // опционально, если пусто — git add .
}
```

Выполняет внутри контейнера:

```bash
cd /vault
git fetch origin
git checkout ai-staging
git pull --rebase origin ai-staging
git add ${FILES:-.}
git commit -m "$MESSAGE" --allow-empty
git push https://x-oauth-basic:${GH_TOKEN_VAULT}@github.com/i72590904-spec/automind-vault.git ai-staging
```

Где `${GH_TOKEN_VAULT}` — секрет, проброшенный из credential. Он **не** записан
в JSON workflow, ты его подключаешь сам после импорта.

### 8. Защита `main` от bot-коммитов

На GitHub в репо `automind-vault`: **Settings → Branches → Branch protection rules**.

Добавь rule для `main`:
- **Require a pull request before merging** ✅
- **Require status checks to pass** (если будут) ✅
- **Restrict who can push to matching branches**: добавь себя, исключи bot-аккаунт

Дополнительно можно настроить GitHub Actions, который автоматически создаёт
PR из `ai-staging` в `main` каждое утро — будем делать в Фазе 5.

## Контрольный список

- [ ] Vault — git-репо, есть ветки `main` и `ai-staging`
- [ ] PAT создан, добавлен в n8n как credential `GitHub Vault Token`
- [ ] `OBSIDIAN_VAULT_PATH` в `.env` указывает на папку Vault
- [ ] `docker compose up -d --force-recreate n8n` — vault примонтирован в `/vault`
- [ ] git identity настроена внутри контейнера
- [ ] Workflow `13-obsidian-git-commit` импортирован и тестово вызывается
- [ ] Branch protection на `main` включён
