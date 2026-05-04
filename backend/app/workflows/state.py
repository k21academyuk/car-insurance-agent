"""LangGraph state definition.

Single source of truth that flows through every node in the graph.
"""
from typing import Annotated, Literal, TypedDict, Optional
from langgraph.graph.message import add_messages


class AgentState(TypedDict):
    """State that flows through the LangGraph workflow."""

    # Conversation history (auto-merged via the add_messages reducer)
    messages: Annotated[list, add_messages]

    # Routing
    intent: Optional[Literal["quote", "claim", "policy_qa", "general"]]
    next_agent: Optional[str]

    # Domain context — populated by agents as the conversation progresses
    vehicle: Optional[dict]
    customer: Optional[dict]
    quote_result: Optional[dict]
    claim_result: Optional[dict]

    # Damage photo for claim flow (base64 string)
    damage_image_b64: Optional[str]
