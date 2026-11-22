from fastapi import FastAPI

from app.routers import auth, operations

app = FastAPI(title="Sterilink API")

app.include_router(auth.router)
app.include_router(operations.router)


@app.get("/health")
def health():
    return {"status": "ok"}
