from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm

from app.auth import create_access_token, verify_password
from app.db import get_conn
from app.schemas import LoginResponse

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=LoginResponse)
def login(form: OAuth2PasswordRequestForm = Depends()):
    with get_conn() as conn:
        user = conn.execute(
            "SELECT user_id, username, password_hash, role FROM users WHERE username = %s",
            (form.username,),
        ).fetchone()

    if user is None or not verify_password(form.password, user["password_hash"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
        )

    token = create_access_token(user["user_id"], user["username"], user["role"])
    return LoginResponse(access_token=token, role=user["role"], username=user["username"])
