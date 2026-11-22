-- Sterilink — validation demo script.
-- Each block should FAIL with the stated Postgres error. Run block by block
-- (not as one transaction) so one failure doesn't roll back the valid setup.

BEGIN;

-- Minimal valid master data to hang the failure tests off.
INSERT INTO users (username, name, password_hash, role)
VALUES ('demo_admin', 'Demo Admin', 'x', 'ADMIN');

INSERT INTO sterilisation_processes (process_name, temperature_c, duration_min)
VALUES ('STEAM_134', 134.0, 30);

INSERT INTO equipments (equipment_name, category, process_id, total_quantity)
VALUES ('ENT Basic Set', 'INSTRUMENT', 1, 2);

INSERT INTO autoclaves (autoclave_name, process_id, capacity, status)
VALUES ('Autoclave-1', 1, 5, 'AVAILABLE');

INSERT INTO procedures (procedure_name, duration_min)
VALUES ('Tonsillectomy', 60);

INSERT INTO scheduled_operations (procedure_id, user_id, scheduled_start)
VALUES (1, 1, now() + interval '2 hours');

INSERT INTO sterilisation_batches (operation_id, autoclave_id, start_time)
VALUES (1, 1, now());   -- expected_end auto-computed by trigger = start + 30 min

COMMIT;

-- =============================================================================
-- TEST 1: negative quantity -> CHECK constraint
-- =============================================================================
INSERT INTO batch_contents (batch_id, equipment_id, quantity) VALUES (1, 1, -1);
-- Expect: ERROR  new row for relation "batch_contents" violates check constraint
--         "batch_contents_quantity_check"

-- =============================================================================
-- TEST 2: invalid status value -> CHECK constraint
-- =============================================================================
UPDATE autoclaves SET status = 'BROKEN' WHERE autoclave_id = 1;
-- Expect: ERROR  new row for relation "autoclaves" violates check constraint
--         "autoclaves_status_check"

-- =============================================================================
-- TEST 3: over-capacity batch -> trg_check_batch_capacity
-- =============================================================================
-- Autoclave-1 capacity = 5. Requesting 10 units of an item that only needs 2
-- already exceeds it on its own.
INSERT INTO batch_contents (batch_id, equipment_id, quantity) VALUES (1, 1, 10);
-- Expect: ERROR  Batch 1 exceeds autoclave capacity (10 > 5)

-- =============================================================================
-- TEST 4: equipment over-booked beyond total_quantity -> trg_check_equipment_availability
-- =============================================================================
-- "ENT Basic Set" total_quantity = 2. First commit 2 (valid), then a second
-- batch on a DIFFERENT autoclave (so the autoclave EXCLUDE constraint doesn't
-- mask this check) but with an overlapping busy window asks for 1 more.
INSERT INTO batch_contents (batch_id, equipment_id, quantity) VALUES (1, 1, 2);
-- (this one succeeds, capacity ok: 2 <= 5)

INSERT INTO autoclaves (autoclave_name, process_id, capacity, status)
VALUES ('Autoclave-2', 1, 5, 'AVAILABLE');

INSERT INTO scheduled_operations (procedure_id, user_id, scheduled_start)
VALUES (1, 1, now() + interval '2 hours 30 minutes');

INSERT INTO sterilisation_batches (operation_id, autoclave_id, start_time)
VALUES (2, 2, now() + interval '5 minutes');   -- different autoclave, overlapping busy window

INSERT INTO batch_contents (batch_id, equipment_id, quantity) VALUES (2, 1, 1);
-- Expect: ERROR  Equipment 1 unavailable: 2 already committed + 1 requested > 2 total

-- =============================================================================
-- TEST 5: double-booked autoclave -> EXCLUDE USING gist (overlapping time ranges)
-- =============================================================================
INSERT INTO scheduled_operations (procedure_id, user_id, scheduled_start)
VALUES (1, 1, now() + interval '3 hours');

INSERT INTO sterilisation_batches (operation_id, autoclave_id, start_time)
VALUES (3, 1, now() + interval '10 minutes');  -- overlaps batch 1's cycle on Autoclave-1
-- Expect: ERROR  conflicting key value violates exclusion constraint
--         "sterilisation_batches_autoclave_id_tstzrange_excl"

-- =============================================================================
-- TEST 6: wrong sterilisation process for equipment -> trg_check_process_match
-- =============================================================================
INSERT INTO sterilisation_processes (process_name, temperature_c, duration_min)
VALUES ('LOW_TEMP_PLASMA', 55.0, 45);

INSERT INTO equipments (equipment_name, category, process_id, total_quantity)
VALUES ('Linen Set', 'LINEN', 2, 5);   -- requires process 2, but Autoclave-1 runs process 1

INSERT INTO batch_contents (batch_id, equipment_id, quantity) VALUES (1, 2, 1);
-- Expect: ERROR  Equipment 2 requires a different sterilisation process than
--         batch 1 autoclave supports
