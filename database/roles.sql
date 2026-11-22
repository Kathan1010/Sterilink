-- Restricted read-only role for the future NL->SQL assistant.
-- Can SELECT from tables/views but cannot INSERT/UPDATE/DELETE or see
-- password hashes, keeping the LLM's blast radius to "read current state".

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'sterilink_readonly') THEN
        EXECUTE 'DROP OWNED BY sterilink_readonly';
        EXECUTE 'DROP ROLE sterilink_readonly';
    END IF;
END $$;

CREATE ROLE sterilink_readonly WITH LOGIN PASSWORD 'readonly_change_me' NOSUPERUSER NOCREATEDB NOCREATEROLE;

GRANT CONNECT ON DATABASE sterilink TO sterilink_readonly;
GRANT USAGE ON SCHEMA public TO sterilink_readonly;

-- Table-level SELECT on everything except users, which gets column-level
-- SELECT instead so password_hash is never readable. A table-level GRANT
-- would cover all columns regardless of any later column-level REVOKE, so
-- users must be excluded from the blanket grant, not patched after it.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO sterilink_readonly;
REVOKE SELECT ON users FROM sterilink_readonly;
GRANT SELECT (user_id, username, name, role) ON users TO sterilink_readonly;

-- Any tables/views created later are readable automatically.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO sterilink_readonly;
