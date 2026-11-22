"""Earliest-deadline-first sterilisation batch planner.

For a scheduled operation, groups its required equipment by sterilisation
process, and for each group tries to book the earliest-available compatible
autoclave such that the batch finishes at least READY_BUFFER_MIN before the
operation starts. Autoclave rows are locked FOR UPDATE during assignment so
two concurrent plan attempts can't race for the same slot; the database's
own EXCLUDE constraint is the final authority on overlap.
"""
from datetime import timedelta

import psycopg

READY_BUFFER_MIN = 30


class PlanningError(Exception):
    pass


def plan_operation(conn: psycopg.Connection, operation_id: int) -> list[int]:
    operation = conn.execute(
        """
        SELECT so.operation_id, so.procedure_id, so.scheduled_start
        FROM scheduled_operations so
        WHERE so.operation_id = %s
        """,
        (operation_id,),
    ).fetchone()
    if operation is None:
        raise PlanningError(f"Operation {operation_id} not found")

    requirements = conn.execute(
        """
        SELECT e.equipment_id, e.process_id, pr.quantity, sp.duration_min
        FROM procedure_requirements pr
        JOIN equipments e ON e.equipment_id = pr.equipment_id
        JOIN sterilisation_processes sp ON sp.process_id = e.process_id
        WHERE pr.procedure_id = %s
        """,
        (operation["procedure_id"],),
    ).fetchall()
    if not requirements:
        raise PlanningError(f"Procedure {operation['procedure_id']} has no equipment requirements defined")

    by_process: dict[int, list[dict]] = {}
    for row in requirements:
        by_process.setdefault(row["process_id"], []).append(row)

    created_batch_ids: list[int] = []

    for process_id, items in by_process.items():
        duration_min = items[0]["duration_min"]
        deadline = operation["scheduled_start"] - timedelta(minutes=READY_BUFFER_MIN)
        start_time = deadline - timedelta(minutes=duration_min)

        candidates = conn.execute(
            """
            SELECT autoclave_id FROM autoclaves
            WHERE process_id = %s AND status = 'AVAILABLE'
            ORDER BY autoclave_id
            """,
            (process_id,),
        ).fetchall()
        if not candidates:
            raise PlanningError(f"No available autoclave supports process {process_id}")

        batch_id = _try_assign_batch(conn, operation_id, candidates, start_time, items)
        if batch_id is None:
            raise PlanningError(
                f"Could not book a batch for process {process_id}: "
                f"all candidate autoclaves are booked, over capacity, or equipment unavailable"
            )
        created_batch_ids.append(batch_id)

    return created_batch_ids


def _try_assign_batch(conn, operation_id, candidates, start_time, items) -> int | None:
    for candidate in candidates:
        autoclave_id = candidate["autoclave_id"]
        try:
            with conn.transaction():
                conn.execute(
                    "SELECT autoclave_id FROM autoclaves WHERE autoclave_id = %s FOR UPDATE",
                    (autoclave_id,),
                )
                batch = conn.execute(
                    """
                    INSERT INTO sterilisation_batches (operation_id, autoclave_id, start_time)
                    VALUES (%s, %s, %s)
                    RETURNING batch_id
                    """,
                    (operation_id, autoclave_id, start_time),
                ).fetchone()
                batch_id = batch["batch_id"]

                for item in items:
                    conn.execute(
                        """
                        INSERT INTO batch_contents (batch_id, equipment_id, quantity)
                        VALUES (%s, %s, %s)
                        """,
                        (batch_id, item["equipment_id"], item["quantity"]),
                    )
            return batch_id
        except psycopg.errors.Error:
            continue
    return None
