-- Read-only role for Analytics agent (workflow 35 — sql_query tool).
-- Принципы:
--   - Только SELECT на основные аналитические таблицы.
--   - Никаких INSERT/UPDATE/DELETE/DDL — даже если AI попытается их сгенерировать,
--     роль их физически не сможет выполнить.
--   - Создаётся отдельный пользователь, поэтому пароль читается из APP_DB_PASSWORD.
--   - Если пароль не задан — роль создаётся без пароля (это ок для контейнера в той же сети).

\connect automind

DO $$
DECLARE
    pwd text := COALESCE(NULLIF(current_setting('automind.readonly_password', true), ''), '');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'automind_ro') THEN
        IF pwd <> '' THEN
            EXECUTE format('CREATE ROLE automind_ro LOGIN PASSWORD %L', pwd);
        ELSE
            EXECUTE 'CREATE ROLE automind_ro LOGIN';
        END IF;
    END IF;
END
$$;

GRANT CONNECT ON DATABASE automind TO automind_ro;
GRANT USAGE  ON SCHEMA public TO automind_ro;
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO automind_ro;

-- Будущие таблицы тоже получат SELECT.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO automind_ro;

-- Никаких прав на изменение sequences/функций/процедур (на всякий случай явно):
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM automind_ro;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM automind_ro;
