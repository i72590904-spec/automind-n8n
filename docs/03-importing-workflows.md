# Импорт / экспорт workflow

## Импорт через UI

1. Открой <http://localhost:5678>.
2. **Workflows → Add workflow → меню `...` → Import from File**.
3. Выбери JSON из `workflows/`.
4. После импорта подключи Credentials в красных узлах.

## Экспорт через UI

1. Открой нужный workflow.
2. Меню `...` (правый верхний угол) → **Download**.
3. Положи файл в `backups/<дата>-<workflow-name>.json` для снапшота
   или сразу в `workflows/` после ревью.

## Импорт массово через CLI (опционально)

Внутри контейнера n8n есть CLI:

```powershell
docker exec -it automind-n8n n8n import:workflow --input=/workflows/01-booking-bot.json
docker exec -it automind-n8n n8n import:workflow --input=/workflows/02-reminder-bot.json
```

Папка `./workflows/` примонтирована в контейнер по пути `/workflows`
(см. `docker-compose.yml`).

## Экспорт массово

```powershell
docker exec -it automind-n8n n8n export:workflow --all --output=/workflows-export
docker cp automind-n8n:/workflows-export ./backups/auto-export
```

## Кредишены

Кредишены **не экспортируются** в JSON workflow по соображениям безопасности.
В JSON остаются только их `id` + `name`. Поэтому:

- При первом импорте на новой машине придётся вручную создать credentials с
  теми же **именами**, что зашиты в JSON (`Telegram Bot — АвтоMind`,
  `Postgres — automind app`).
- n8n сам подцепит их по имени.

Если хочется бэкапить и кредишены тоже:

```powershell
docker exec -it automind-n8n n8n export:credentials --all --output=/cred-export.json --decrypted
```

> ⚠️ Этот файл содержит токены в открытом виде. **Никогда** не коммить в git.
