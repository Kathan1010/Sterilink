-- Sterilink schema — Day 1 slice: register operation -> generate sterilisation batch.
-- external_facilities and failure/replanning tables come in a later slice.

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------------
-- Master data
-- ---------------------------------------------------------------------------

CREATE TABLE users (
    user_id         SERIAL PRIMARY KEY,
    username        VARCHAR(50) NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL,
    password_hash   TEXT NOT NULL,
    role            VARCHAR(20) NOT NULL
        CHECK (role IN ('ENT_SCHEDULER', 'STERILISATION_STAFF', 'ADMIN'))
);

CREATE TABLE procedures (
    procedure_id    SERIAL PRIMARY KEY,
    procedure_name  VARCHAR(100) NOT NULL UNIQUE,
    duration_min    INTEGER NOT NULL CHECK (duration_min > 0)
);

CREATE TABLE sterilisation_processes (
    process_id      SERIAL PRIMARY KEY,
    process_name    VARCHAR(50) NOT NULL UNIQUE,
    temperature_c   NUMERIC(5,1) NOT NULL CHECK (temperature_c > 0),
    duration_min    INTEGER NOT NULL CHECK (duration_min > 0)
);

CREATE TABLE equipments (
    equipment_id    SERIAL PRIMARY KEY,
    equipment_name  VARCHAR(100) NOT NULL,
    category        VARCHAR(20) NOT NULL CHECK (category IN ('INSTRUMENT', 'LINEN')),
    process_id      INTEGER NOT NULL REFERENCES sterilisation_processes(process_id),
    total_quantity  INTEGER NOT NULL CHECK (total_quantity >= 0)
);

CREATE TABLE procedure_requirements (
    procedure_id    INTEGER NOT NULL REFERENCES procedures(procedure_id),
    equipment_id    INTEGER NOT NULL REFERENCES equipments(equipment_id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (procedure_id, equipment_id)
);

CREATE TABLE autoclaves (
    autoclave_id    SERIAL PRIMARY KEY,
    autoclave_name  VARCHAR(50) NOT NULL UNIQUE,
    process_id      INTEGER NOT NULL REFERENCES sterilisation_processes(process_id),
    capacity        INTEGER NOT NULL CHECK (capacity > 0),
    status          VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (status IN ('AVAILABLE', 'RUNNING', 'FAILED', 'MAINTENANCE')),
    available_from  TIMESTAMPTZ
);

-- ---------------------------------------------------------------------------
-- Operational data
-- ---------------------------------------------------------------------------

CREATE TABLE scheduled_operations (
    operation_id    SERIAL PRIMARY KEY,
    procedure_id    INTEGER NOT NULL REFERENCES procedures(procedure_id),
    user_id         INTEGER NOT NULL REFERENCES users(user_id),
    scheduled_start TIMESTAMPTZ NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED'
        CHECK (status IN ('SCHEDULED', 'PLANNED', 'READY', 'AT_RISK',
                           'DELAYED', 'COMPLETED', 'CANCELLED'))
);

CREATE TABLE sterilisation_batches (
    batch_id        SERIAL PRIMARY KEY,
    operation_id    INTEGER NOT NULL REFERENCES scheduled_operations(operation_id),
    autoclave_id    INTEGER NOT NULL REFERENCES autoclaves(autoclave_id),
    start_time      TIMESTAMPTZ NOT NULL,
    expected_end    TIMESTAMPTZ NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PLANNED'
        CHECK (status IN ('PLANNED', 'RUNNING', 'COMPLETED', 'FAILED',
                           'AFFECTED', 'CANCELLED')),
    CHECK (expected_end > start_time),
    EXCLUDE USING gist (
        autoclave_id WITH =,
        tstzrange(start_time, expected_end) WITH &&
    ) WHERE (status IN ('PLANNED', 'RUNNING'))
);

CREATE TABLE batch_contents (
    batch_id        INTEGER NOT NULL REFERENCES sterilisation_batches(batch_id),
    equipment_id    INTEGER NOT NULL REFERENCES equipments(equipment_id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (batch_id, equipment_id)
);

CREATE INDEX idx_batches_autoclave ON sterilisation_batches(autoclave_id);
CREATE INDEX idx_batches_operation ON sterilisation_batches(operation_id);
CREATE INDEX idx_operations_start ON scheduled_operations(scheduled_start);
