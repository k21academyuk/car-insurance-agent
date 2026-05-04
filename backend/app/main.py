"""FastAPI entrypoint for Car Insurance AI."""
import logging
import os
import uuid
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from langchain_core.messages import HumanMessage, AIMessage, ToolMessage
from pydantic import BaseModel

from app.workflows.main_graph import get_graph

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("car-insurance-agent")


# ─── App setup ────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Car Insurance AI",
    description="Multi-agent car insurance assistant powered by LangGraph",
    version="1.0.0",
)

cors_origins = os.getenv("CORS_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve frontend static files
FRONTEND_DIR = Path(__file__).parent.parent.parent / "frontend"
if FRONTEND_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR / "static")), name="static")


# ─── Schemas ──────────────────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    message: str
    session_id: str | None = None
    damage_image_b64: str | None = None


class ChatResponse(BaseModel):
    session_id: str
    intent: str | None
    reply: str
    tool_calls: list[dict]


# ─── Routes ───────────────────────────────────────────────────────────────────
@app.get("/")
async def root():
    """Serve the chat UI."""
    index = FRONTEND_DIR / "index.html"
    if index.exists():
        return FileResponse(str(index))
    return {"status": "ok", "service": "car-insurance-agent"}


@app.get("/health")
async def health():
    return {"status": "ok", "service": "car-insurance-agent"}


@app.post("/api/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    """Send a message to the multi-agent system and get a response."""
    if not req.message.strip() and not req.damage_image_b64:
        raise HTTPException(400, "Empty message")

    session_id = req.session_id or str(uuid.uuid4())
    config = {"configurable": {"thread_id": session_id}}

    graph = get_graph()

    # Build the input state
    input_state: dict = {
        "messages": [HumanMessage(content=req.message or "I've uploaded a damage photo.")],
    }
    if req.damage_image_b64:
        input_state["damage_image_b64"] = req.damage_image_b64

    log.info(f"[{session_id}] message='{req.message[:80]}' "
             f"image={'yes' if req.damage_image_b64 else 'no'}")

    try:
        result = await graph.ainvoke(input_state, config=config)
    except Exception as e:
        log.exception("Graph invocation failed")
        raise HTTPException(500, f"Agent error: {type(e).__name__}: {e}")

    # Extract the final AI response (last AIMessage with content)
    reply_text = ""
    for msg in reversed(result["messages"]):
        if isinstance(msg, AIMessage) and msg.content:
            reply_text = msg.content
            break

    # Collect tool calls for the UI
    tool_calls_summary = []
    for msg in result["messages"]:
        if isinstance(msg, AIMessage) and msg.tool_calls:
            for tc in msg.tool_calls:
                tool_calls_summary.append({"name": tc["name"], "args": tc["args"]})

    return ChatResponse(
        session_id=session_id,
        intent=result.get("intent"),
        reply=reply_text or "I'm here to help. Could you tell me more?",
        tool_calls=tool_calls_summary,
    )


@app.post("/api/reset")
async def reset_session(session_id: str):
    """Clear a session (frontend convenience)."""
    return {"session_id": session_id, "status": "reset"}
