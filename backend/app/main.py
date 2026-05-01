"""FastAPI entrypoint. Wires routes, middleware, lifespan, tracing."""
from fastapi import FastAPI

app = FastAPI(title="AutoShield AI", version="0.1.0")

@app.get("/health")
async def health():
    return {"status": "ok", "service": "autoshield-ai"}
