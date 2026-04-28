-- =============================================================================
-- АвтоMind — Фаза 4: RAG + outreach
-- Включаем pgvector, добавляем таблицы для embeddings и аутрич-сообщений.
-- =============================================================================

\connect automind

CREATE EXTENSION IF NOT EXISTS vector;

SET ROLE automind;

-- ---------------------------------------------------------------------------
-- Добавляем updated_at в leads (нужно для аутрич-воркфлоу).
-- ---------------------------------------------------------------------------
ALTER TABLE leads ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- ---------------------------------------------------------------------------
-- Заметки из Obsidian Vault (raw markdown) — снапшоты содержимого.
-- Используется RAG-пайплайном для отслеживания изменений и переиндексации.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notes (
    id              SERIAL PRIMARY KEY,
    path            TEXT NOT NULL UNIQUE,
    content_hash    TEXT NOT NULL,
    content         TEXT NOT NULL,
    frontmatter     JSONB NOT NULL DEFAULT '{}'::jsonb,
    tags            TEXT[] NOT NULL DEFAULT '{}',
    indexed_at      TIMESTAMPTZ,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS notes_indexed_idx ON notes (indexed_at);

-- ---------------------------------------------------------------------------
-- Чанки заметки + векторы (text-embedding-3-small = 1536 dim).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS note_chunks (
    id              BIGSERIAL PRIMARY KEY,
    note_id         INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    chunk_idx       INTEGER NOT NULL,
    content         TEXT NOT NULL,
    embedding       vector(1536),
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (note_id, chunk_idx)
);

-- IVFFlat index для cosine similarity. lists=100 — компромисс recall/speed.
-- При <1000 чанков можно опустить index (sequential scan быстрее), но мы
-- сразу закладываем под рост.
CREATE INDEX IF NOT EXISTS note_chunks_embedding_idx
    ON note_chunks
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);

-- ---------------------------------------------------------------------------
-- Outreach: переписка с лидами (отдельно от messages, чтобы не смешивать
-- с диалогами клиентов в Telegram-боте).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS outreach_messages (
    id              BIGSERIAL PRIMARY KEY,
    lead_id         INTEGER NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    direction       TEXT NOT NULL,                  -- in | out
    channel         TEXT NOT NULL,                  -- vk | telegram | email
    text            TEXT NOT NULL,
    payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
    sent_by         TEXT,                           -- 'ai-first-contact' | 'ai-sales-manager' | 'human:<email>'
    error           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS outreach_lead_idx ON outreach_messages (lead_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- AI sessions — короткая память диалогов AI-агентов (window N последних).
-- Используется как memory для AI Agent через Postgres credential.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_sessions (
    id              BIGSERIAL PRIMARY KEY,
    session_key     TEXT NOT NULL,                  -- например, "telegram:{chat_id}" или "vk:{user_id}"
    role            TEXT NOT NULL,                  -- system | user | assistant | tool
    content         TEXT NOT NULL,
    name            TEXT,
    metadata        JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_sessions_key_idx ON ai_sessions (session_key, created_at DESC);
