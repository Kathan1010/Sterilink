from fastapi import APIRouter, Depends, HTTPException, status

from app.auth import require_role
from app.db import get_conn
from app.schemas import BatchOut, OperationCreate, OperationOut, OperationPlanResult
from app.services.planner import PlanningError, plan_operation

router = APIRouter(prefix="/operations", tags=["operations"])


def _fetch_operation_out(conn, operation_id: int) -> OperationOut:
    row = conn.execute(
        """
        SELECT so.operation_id, so.procedure_id, p.procedure_name,
               so.user_id, so.scheduled_start, so.status
        FROM scheduled_operations so
        JOIN procedures p ON p.procedure_id = so.procedure_id
        WHERE so.operation_id = %s
        """,
        (operation_id,),
    ).fetchone()
    return OperationOut(**row)


def _fetch_batches(conn, operation_id: int) -> list[BatchOut]:
    rows = conn.execute(
        """
        SELECT b.batch_id, b.autoclave_id, a.autoclave_name,
               b.start_time, b.expected_end, b.status
        FROM sterilisation_batches b
        JOIN autoclaves a ON a.autoclave_id = b.autoclave_id
        WHERE b.operation_id = %s
        ORDER BY b.batch_id
        """,
        (operation_id,),
    ).fetchall()
    return [BatchOut(**row) for row in rows]


@router.post("", response_model=OperationPlanResult, status_code=status.HTTP_201_CREATED)
def register_operation(
    body: OperationCreate,
    user: dict = Depends(require_role("ENT_SCHEDULER", "ADMIN")),
):
    with get_conn() as conn:
        procedure = conn.execute(
            "SELECT procedure_id FROM procedures WHERE procedure_id = %s",
            (body.procedure_id,),
        ).fetchone()
        if procedure is None:
            raise HTTPException(status_code=422, detail=f"Unknown procedure_id {body.procedure_id}")

        operation = conn.execute(
            """
            INSERT INTO scheduled_operations (procedure_id, user_id, scheduled_start)
            VALUES (%s, %s, %s)
            RETURNING operation_id
            """,
            (body.procedure_id, user["user_id"], body.scheduled_start),
        ).fetchone()
        operation_id = operation["operation_id"]

    planning_status = "planned"
    message = None
    with get_conn() as conn:
        try:
            with conn.transaction():
                plan_operation(conn, operation_id)
                conn.execute(
                    "UPDATE scheduled_operations SET status = 'PLANNED' WHERE operation_id = %s",
                    (operation_id,),
                )
        except PlanningError as exc:
            planning_status = "failed"
            message = str(exc)

    with get_conn() as conn:
        operation_out = _fetch_operation_out(conn, operation_id)
        batches = _fetch_batches(conn, operation_id)

    return OperationPlanResult(
        operation=operation_out,
        planning_status=planning_status,
        message=message,
        batches=batches,
    )


@router.get("", response_model=list[OperationOut])
def list_operations(user: dict = Depends(require_role("ENT_SCHEDULER", "STERILISATION_STAFF", "ADMIN"))):
    with get_conn() as conn:
        rows = conn.execute(
            """
            SELECT so.operation_id, so.procedure_id, p.procedure_name,
                   so.user_id, so.scheduled_start, so.status
            FROM scheduled_operations so
            JOIN procedures p ON p.procedure_id = so.procedure_id
            ORDER BY so.scheduled_start
            """
        ).fetchall()
    return [OperationOut(**row) for row in rows]


@router.get("/{operation_id}", response_model=OperationPlanResult)
def get_operation(
    operation_id: int,
    user: dict = Depends(require_role("ENT_SCHEDULER", "STERILISATION_STAFF", "ADMIN")),
):
    with get_conn() as conn:
        row = conn.execute(
            "SELECT 1 FROM scheduled_operations WHERE operation_id = %s", (operation_id,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Operation not found")

        operation_out = _fetch_operation_out(conn, operation_id)
        batches = _fetch_batches(conn, operation_id)

    return OperationPlanResult(
        operation=operation_out,
        planning_status="planned" if operation_out.status == "PLANNED" else "failed",
        batches=batches,
    )
