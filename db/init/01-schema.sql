-- =============================================================================
-- АвтоMind — схема прикладной БД (automind)
-- Выполняется один раз при инициализации тома postgres_data.
-- Если уже инициализирован — применяй вручную:
--   docker exec -i automind-postgres psql -U automind -d automind < db/init/01-schema.sql
-- =============================================================================

\connect automind

-- Подключаемся под суперпользователем и переключаем владельца на app-юзера.
SET ROLE automind;

-- ---------------------------------------------------------------------------
-- Услуги (то, на что клиент записывается)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS services (
    id              SERIAL PRIMARY KEY,
    code            TEXT NOT NULL UNIQUE,           -- стабильный код для inline-кнопок (haircut, manicure, ...)
    title           TEXT NOT NULL,                  -- что показывать клиенту
    duration_min    INTEGER NOT NULL DEFAULT 60,    -- длительность услуги
    price_rub       INTEGER,                        -- цена (опционально)
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order      INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Дефолтные услуги для барбершопа/салона. Замени под свою нишу.
INSERT INTO services (code, title, duration_min, price_rub, sort_order) VALUES
    ('haircut',     'Стрижка',                60, 1500, 10),
    ('beard',       'Моделирование бороды',   30,  800, 20),
    ('haircut_beard','Стрижка + борода',      90, 2000, 30),
    ('coloring',    'Окрашивание',           120, 3500, 40)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Клиенты (Telegram-юзеры)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS clients (
    id              SERIAL PRIMARY KEY,
    tg_chat_id      BIGINT NOT NULL UNIQUE,
    tg_username     TEXT,
    full_name       TEXT,
    phone           TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS clients_phone_idx ON clients (phone);

-- ---------------------------------------------------------------------------
-- Состояние диалога с клиентом (state machine для бота)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversation_state (
    tg_chat_id      BIGINT PRIMARY KEY,
    step            TEXT NOT NULL DEFAULT 'idle',   -- idle | choose_service | choose_date | choose_time | enter_name | enter_phone | done
    draft           JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Бронирования
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bookings (
    id              SERIAL PRIMARY KEY,
    client_id       INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    service_id      INTEGER NOT NULL REFERENCES services(id),
    starts_at       TIMESTAMPTZ NOT NULL,
    ends_at         TIMESTAMPTZ NOT NULL,
    status          TEXT NOT NULL DEFAULT 'confirmed', -- confirmed | cancelled | completed | no_show
    reminder_24h_sent BOOLEAN NOT NULL DEFAULT FALSE,
    reminder_1h_sent  BOOLEAN NOT NULL DEFAULT FALSE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS bookings_starts_at_idx ON bookings (starts_at);
CREATE INDEX IF NOT EXISTS bookings_client_idx    ON bookings (client_id);
CREATE INDEX IF NOT EXISTS bookings_status_idx    ON bookings (status);

-- ---------------------------------------------------------------------------
-- Лиды (для парсера ВК и аутрича — Фаза 4-5)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leads (
    id              SERIAL PRIMARY KEY,
    source          TEXT NOT NULL,                  -- vk | telegram | manual | referral
    external_id     TEXT,                           -- vk user_id / group_id и т.д.
    title           TEXT NOT NULL,                  -- название салона / имя
    niche           TEXT,                           -- barbershop | beauty | cafe | clinic | school
    contact_url     TEXT,
    phone           TEXT,
    city            TEXT,
    score           INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'new',    -- new | contacted | qualified | meeting | won | lost
    last_action_at  TIMESTAMPTZ,
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source, external_id)
);

CREATE INDEX IF NOT EXISTS leads_status_idx ON leads (status);
CREATE INDEX IF NOT EXISTS leads_niche_idx  ON leads (niche);

-- ---------------------------------------------------------------------------
-- Сообщения (история взаимодействия с клиентом / лидом)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
    id              BIGSERIAL PRIMARY KEY,
    chat_id         BIGINT NOT NULL,
    direction       TEXT NOT NULL,                  -- in | out
    channel         TEXT NOT NULL DEFAULT 'telegram', -- telegram | vk | email
    text            TEXT,
    payload         JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS messages_chat_idx ON messages (chat_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Метрики (Фаза 6 — дашборд / Супервайзер)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS metrics (
    id              BIGSERIAL PRIMARY KEY,
    workflow        TEXT NOT NULL,
    metric          TEXT NOT NULL,
    value           NUMERIC NOT NULL,
    tags            JSONB NOT NULL DEFAULT '{}'::jsonb,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS metrics_workflow_idx ON metrics (workflow, recorded_at DESC);
