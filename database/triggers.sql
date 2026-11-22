-- Sterilink triggers — Day 1 slice.

-- ---------------------------------------------------------------------------
-- 1. Auto-compute expected_end = start_time + autoclave's process duration
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trg_compute_batch_end_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_duration INTEGER;
BEGIN
    SELECT sp.duration_min INTO v_duration
    FROM autoclaves a
    JOIN sterilisation_processes sp ON sp.process_id = a.process_id
    WHERE a.autoclave_id = NEW.autoclave_id;

    IF v_duration IS NULL THEN
        RAISE EXCEPTION 'Autoclave % has no associated process', NEW.autoclave_id;
    END IF;

    NEW.expected_end := NEW.start_time + make_interval(mins => v_duration);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_compute_batch_end
BEFORE INSERT OR UPDATE OF start_time, autoclave_id ON sterilisation_batches
FOR EACH ROW
EXECUTE FUNCTION trg_compute_batch_end_fn();

-- ---------------------------------------------------------------------------
-- 2. Equipment's process must match the batch's autoclave process
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trg_check_process_match_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_autoclave_process INTEGER;
    v_equipment_process  INTEGER;
BEGIN
    SELECT a.process_id INTO v_autoclave_process
    FROM sterilisation_batches b
    JOIN autoclaves a ON a.autoclave_id = b.autoclave_id
    WHERE b.batch_id = NEW.batch_id;

    SELECT e.process_id INTO v_equipment_process
    FROM equipments e
    WHERE e.equipment_id = NEW.equipment_id;

    IF v_autoclave_process IS DISTINCT FROM v_equipment_process THEN
        RAISE EXCEPTION 'Equipment % requires a different sterilisation process than batch % autoclave supports',
            NEW.equipment_id, NEW.batch_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_process_match
BEFORE INSERT OR UPDATE ON batch_contents
FOR EACH ROW
EXECUTE FUNCTION trg_check_process_match_fn();

-- ---------------------------------------------------------------------------
-- 3. Total quantity in a batch must not exceed the autoclave's capacity
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trg_check_batch_capacity_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_capacity INTEGER;
    v_total    INTEGER;
BEGIN
    SELECT a.capacity INTO v_capacity
    FROM sterilisation_batches b
    JOIN autoclaves a ON a.autoclave_id = b.autoclave_id
    WHERE b.batch_id = NEW.batch_id;

    SELECT COALESCE(SUM(quantity), 0) INTO v_total
    FROM batch_contents
    WHERE batch_id = NEW.batch_id;

    IF v_total > v_capacity THEN
        RAISE EXCEPTION 'Batch % exceeds autoclave capacity (% > %)',
            NEW.batch_id, v_total, v_capacity;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_check_batch_capacity
AFTER INSERT OR UPDATE ON batch_contents
FOR EACH ROW
EXECUTE FUNCTION trg_check_batch_capacity_fn();

-- ---------------------------------------------------------------------------
-- 4. Equipment availability: quantity committed to overlapping busy windows
--    (batch start_time -> operation's scheduled_start + procedure duration)
--    must not exceed the equipment's total_quantity.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION trg_check_equipment_availability_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_total_quantity INTEGER;
    v_busy_start     TIMESTAMPTZ;
    v_busy_end       TIMESTAMPTZ;
    v_committed      INTEGER;
BEGIN
    SELECT total_quantity INTO v_total_quantity
    FROM equipments WHERE equipment_id = NEW.equipment_id;

    SELECT b.start_time, so.scheduled_start + make_interval(mins => p.duration_min)
    INTO v_busy_start, v_busy_end
    FROM sterilisation_batches b
    JOIN scheduled_operations so ON so.operation_id = b.operation_id
    JOIN procedures p ON p.procedure_id = so.procedure_id
    WHERE b.batch_id = NEW.batch_id;

    SELECT COALESCE(SUM(bc.quantity), 0) INTO v_committed
    FROM batch_contents bc
    JOIN sterilisation_batches b ON b.batch_id = bc.batch_id
    JOIN scheduled_operations so ON so.operation_id = b.operation_id
    JOIN procedures p ON p.procedure_id = so.procedure_id
    WHERE bc.equipment_id = NEW.equipment_id
      AND bc.batch_id <> NEW.batch_id
      AND b.status IN ('PLANNED', 'RUNNING')
      AND tstzrange(b.start_time, so.scheduled_start + make_interval(mins => p.duration_min))
          && tstzrange(v_busy_start, v_busy_end);

    IF v_committed + NEW.quantity > v_total_quantity THEN
        RAISE EXCEPTION 'Equipment % unavailable: % already committed + % requested > % total',
            NEW.equipment_id, v_committed, NEW.quantity, v_total_quantity;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_check_equipment_availability
AFTER INSERT OR UPDATE ON batch_contents
FOR EACH ROW
EXECUTE FUNCTION trg_check_equipment_availability_fn();
