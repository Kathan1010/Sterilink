from fastapi import APIRouter, Depends

from app.auth import get_current_user
from app.db import get_conn

router = APIRouter(prefix="/procedures", tags=["procedures"])


@router.get("")
def list_procedures(user: dict = Depends(get_current_user)):
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT procedure_id, procedure_name, duration_min FROM procedures ORDER BY procedure_name"
        ).fetchall()
    return rows
