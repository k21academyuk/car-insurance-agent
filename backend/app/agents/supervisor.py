"""Supervisor — top-level router.

Classifies user intent and decides which specialist agent should respond.
Uses a fast, cheap model (gpt-4o-mini) since this is a classification task.
"""
import json
from langchain_openai import ChatOpenAI
from langchain_core.messages import SystemMessage, AIMessage

from app.workflows.state import AgentState


SUPERVISOR_PROMPT = """You are the supervisor of a car insurance AI system. Your only job is to classify
the user's intent and decide which specialist agent should handle their request.

You have 3 specialist agents:

1. **quote** — handles requests for premium quotes, vehicle insurance pricing, IDV/NCB calculations.
   Examples: "I want a quote for my Maruti Swift", "How much will insurance cost for a 2-year old Creta?",
             "Get me a premium for my car", "What's the IDV for a Honda City?"

2. **claims** — handles claim filing, damage assessment, policy verification for claims, payout estimates.
   Examples: "I had an accident", "I want to file a claim", "Help me with a claim",
             "My car got damaged", "I uploaded a photo of the damage"

3. **policy_qa** — answers questions about policy terms, coverage, exclusions, IRDAI rules,
   process questions, NCB rules, what's covered/not covered.
   Examples: "What is NCB?", "Is flood damage covered?", "How do I transfer my policy?",
             "What does IDV mean?", "What's covered under comprehensive insurance?"

Respond ONLY with valid JSON in this exact format (no markdown, no extra text):
{"intent": "quote" | "claim" | "policy_qa", "reasoning": "<one short sentence>"}

If the user's request is unclear or doesn't fit, default to "policy_qa".
"""


def supervisor_node(state: AgentState) -> dict:
    """Classify user intent and set the next_agent for routing."""
    llm = ChatOpenAI(model="gpt-4o-mini", temperature=0)

    # Get the latest user message
    user_messages = [m for m in state["messages"] if getattr(m, "type", None) == "human"]
    if not user_messages:
        return {"intent": "policy_qa", "next_agent": "policy_qa"}

    latest_user_msg = user_messages[-1].content

    # If a damage image is attached, this is unambiguously a claim
    if state.get("damage_image_b64"):
        return {"intent": "claim", "next_agent": "claims"}

    # If we already have an intent and the user is continuing the same flow,
    # keep them in the same agent (preserves multi-turn coherence)
    current_intent = state.get("intent")
    if current_intent in ("quote", "claim", "policy_qa"):
        # Check if this looks like a topic switch
        switch_keywords = {
            "quote": ["claim", "accident", "damage", "what is", "what's covered"],
            "claim": ["quote", "premium", "how much", "price"],
            "policy_qa": ["quote", "claim", "premium for"],
        }
        msg_lower = latest_user_msg.lower()
        if not any(k in msg_lower for k in switch_keywords.get(current_intent, [])):
            return {"intent": current_intent, "next_agent": _intent_to_agent(current_intent)}

    # Classify
    response = llm.invoke([
        SystemMessage(content=SUPERVISOR_PROMPT),
        {"role": "user", "content": latest_user_msg},
    ])
    content = response.content.strip()
    if content.startswith("```"):
        content = content.split("```")[1]
        if content.startswith("json"):
            content = content[4:]
        content = content.strip()

    try:
        decision = json.loads(content)
        intent = decision.get("intent", "policy_qa")
    except json.JSONDecodeError:
        intent = "policy_qa"

    if intent not in ("quote", "claim", "policy_qa"):
        intent = "policy_qa"

    return {"intent": intent, "next_agent": _intent_to_agent(intent)}


def _intent_to_agent(intent: str) -> str:
    return {"quote": "quote", "claim": "claims", "policy_qa": "policy_qa"}.get(intent, "policy_qa")


def route_from_supervisor(state: AgentState) -> str:
    """Conditional edge function — returns the name of the next node."""
    return state.get("next_agent") or "policy_qa"
