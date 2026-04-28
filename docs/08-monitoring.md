# Фаза 6 — Мониторинг (Loki + Grafana + Alerting)

## Что добавляется

### Сервисы (Docker)

| Сервис    | Порт      | Назначение                                                    |
|-----------|-----------|----------------------------------------------------------------|
| `loki`    | 3100      | Хранилище логов (TSDB, retention 7 дней).                     |
| `promtail`| —         | Сборщик логов из всех контейнеров `automind-*`.               |
| `grafana` | 3000      | Дашборды + Explore по логам и SQL.                            |

Все три сервиса в **профиле `monitoring`** — поднимаются командой:

```powershell
docker compose --profile monitoring up -d
```

или, если хочешь поднимать всё вместе всегда:

```powershell
docker compose --profile monitoring up -d
# Дальше docker compose ps покажет все сервисы.
```

### Workflow

| Файл                   | Назначение                                                   |
|------------------------|---------------------------------------------------------------|
| `40-alerting.json`     | Cron 15 мин: собирает health-метрики из БД, применяет правила, дедуплицирует и шлёт алерты в Telegram команды. |

### Постоянные паролі для readonly-роли

В `.env` нужно добавить:
```
GRAFANA_ADMIN_PASSWORD=<сильный_пароль>
POSTGRES_RO_PASSWORD=<сильный_пароль>
GRAFANA_PORT=3000
LOKI_PORT=3100
```

И установить пароль роли `automind_ro` (миграция `03-readonly.sql` создаёт её без пароля по умолчанию):

```powershell
docker exec -it automind-postgres psql -U postgres -d automind -c "ALTER ROLE automind_ro WITH PASSWORD '$Env:POSTGRES_RO_PASSWORD'"
```

## Как открыть Grafana

1. Подними стэк с профилем: `docker compose --profile monitoring up -d`
2. Открой http://localhost:3000
3. Логин: `admin` / `${GRAFANA_ADMIN_PASSWORD}`
4. Слева **Dashboards → АвтоMind**:
   - **АвтоMind Overview** — лиды, бронирования, воронка, конверсия
   - **AI Agents** — метрики по workflow, эскалации, recent errors из логов n8n
5. Слева **Explore** → datasource `Loki` → пиши запросы вида:
   - `{service="n8n"}` — все логи n8n
   - `{service="n8n"} |~ "(?i)error"` — только ошибки
   - `{container="automind-postgres"}` — логи Postgres

## Алерты

Workflow `40-alerting` каждые 15 минут проверяет:

| Код                  | Условие                                                                  | Уровень |
|----------------------|---------------------------------------------------------------------------|---------|
| `no_bookings_6h`     | За 6 часов в рабочее время (10-21) — 0 бронирований.                     | warn    |
| `many_escalations`   | ≥ 5 эскалаций к команде за час.                                          | warn    |
| `rag_stale`          | RAG не обновлялся ≥ 120 минут (workflow 23 завис или умер).              | warn    |
| `no_vk_leads_24h`    | 24 часа без новых лидов из ВК (токен истёк или ниши переполнены).         | warn    |

> n8n execution errors отдельно отслеживаются через **Loki Explore** (`{service="n8n"} |~ "(?i)error"`) и панель «n8n logs (level=error)» на дашборде AI Agents — у них своя БД, к которой alerting workflow не подключён.

Дедупликация: один и тот же алерт не повторяется чаще раза в час.

Алерты пишутся в `metrics(workflow='40-alerting', metric=<code>)` — потом видны на дашборде AI Agents и в Loki Explore.

## Расширение

### Добавить новый алерт
1. Допиши SQL в `Collect Health Metrics` (workflow 40).
2. Добавь правило в `Apply Rules` JS-узле.
3. Готово — дедупликация и отправка работают для всех правил автоматически.

### Добавить новый дашборд
Положи JSON в `monitoring/grafana/dashboards/`. Grafana подхватит файл за 30 секунд (см. provisioning).

### Добавить Opik для AI-trace (опционально)
Это не входит в этот PR. План:
1. Добавить сервис `opik` в `docker-compose.yml` (профиль `monitoring`).
2. В каждом AI Agent узле добавить custom callback URL `http://opik:5173/api/v1/spans`.
3. Открыть http://localhost:5173 для просмотра трасс.

Это полезно для дебаггинга длинных цепочек вызовов tool'ов в Supervisor → Sales Manager → search_knowledge → ... — в Opik они видны как древовидные spans с input/output на каждом шаге.

## Troubleshooting

### Grafana показывает «Postgres datasource: connection refused»
Контейнер Grafana пингует `postgres:5432` по docker network. Проверь:
- `docker network inspect automind` — Grafana в сети `automind`?
- `docker exec -it automind-grafana wget -qO- http://postgres:5432` — должно ответить.

### Loki «no logs found»
- `docker compose logs promtail | head` — Promtail видит контейнеры?
- Проверь, что docker socket смонтирован (`/var/run/docker.sock`).
- Без socket Promtail просто не находит контейнеры.

### Алерты не приходят
- Workflow 40 активен? (Workflows → 40 → toggle Active)
- В n8n credentials есть `Telegram Bot — АвтоMind`?
- В `.env` задан `TEAM_TELEGRAM_CHAT_ID`?

### Postgres readonly: «role automind_ro does not exist»
Миграция `03-readonly.sql` применилась только если volume был пустой при старте. Если БД уже создана:
```powershell
docker exec -i automind-postgres psql -U automind -d automind < db/init/03-readonly.sql
docker exec -it automind-postgres psql -U postgres -d automind -c "ALTER ROLE automind_ro WITH PASSWORD '$Env:POSTGRES_RO_PASSWORD'"
```
