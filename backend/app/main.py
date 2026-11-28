from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routers import auth, operations, procedures

app = FastAPI(title="Sterilink API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(operations.router)
app.include_router(procedures.router)


@app.get("/health")
def health():
    return {"status": "ok"}
