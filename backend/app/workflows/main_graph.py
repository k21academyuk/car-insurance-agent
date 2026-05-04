"""Main LangGraph workflow.

Wires the supervisor + 3 sub-agents + tool execution into a single graph.

Architecture:

    [START] → supervisor → (route by intent) → quote_agent / claims_agent / policy_qa_agent
                                                       ↓
                                                  tool_executor (if tools called)
                                                       ↓
                                              (loop back to same agent)
                                                       ↓
                                                    [END]
"""
import json
from langgraph.graph import StateGraph, END, START
from langgraph.checkpoint.memory import MemorySaver
from langchain_core.messages import ToolMessage, AIMessage

from app.workflows.state import AgentState
from app.agents.supervisor import supervisor_node, route_from_supervisor
from app.agents.quote_agent import quote_agent_node
from app.agents.claims_agent import claims_agent_node
from app.agents.policy_qa_agent import policy_qa_agent_node
from app.tools.quote_tools import QUOTE_TOOLS
from app.tools.claims_tools import CLAIMS_TOOLS
from app.tools.rag_tools import RAG_TOOLS


# Build a tool registry for execution
ALL_TOOLS = QUOTE_TOOLS + CLAIMS_TOOLS + RAG_TOOLS
TOOL_REGISTRY = {t.name: t for t in ALL_TOOLS}


def tool_executor_node(state: AgentState) -> dict:
    """Execute the tool calls from the most recent AI message.

    Custom executor (instead of LangGraph's prebuilt ToolNode) so we can
    inject the damage_image_b64 from state into the analyze_damage_image tool.
    """
    last_msg = state["messages"][-1]
    if not isinstance(last_msg, AIMessage) or not last_msg.tool_calls:
        return {}

    tool_messages = []
    for tool_call in last_msg.tool_calls:
        name = tool_call["name"]
        args = dict(tool_call["args"])

        # Special case: inject the actual image from state for the vision tool
        if name == "analyze_damage_image":
            if state.get("damage_image_b64"):
                args["image_b64"] = state["damage_image_b64"]
            else:
                tool_messages.append(ToolMessage(
                    content=json.dumps({"error": "No damage image found in state"}),
                    tool_call_id=tool_call["id"],
                    name=name,
                ))
                continue

        if name not in TOOL_REGISTRY:
            tool_messages.append(ToolMessage(
                content=json.dumps({"error": f"Unknown tool: {name}"}),
                tool_call_id=tool_call["id"],
                name=name,
            ))
            continue

        try:
            result = TOOL_REGISTRY[name].invoke(args)
            tool_messages.append(ToolMessage(
                content=json.dumps(result, default=str),
                tool_call_id=tool_call["id"],
                name=name,
            ))
        except Exception as e:
            tool_messages.append(ToolMessage(
                content=json.dumps({"error": f"{type(e).__name__}: {e}"}),
                tool_call_id=tool_call["id"],
                name=name,
            ))

    return {"messages": tool_messages}


def should_use_tools(state: AgentState) -> str:
    """Decide whether the agent's response needs tool execution or is final."""
    last_msg = state["messages"][-1]
    if isinstance(last_msg, AIMessage) and last_msg.tool_calls:
        return "tools"
    return "end"


def build_graph():
    """Construct the supervisor multi-agent LangGraph."""
    graph = StateGraph(AgentState)

    # Nodes
    graph.add_node("supervisor", supervisor_node)
    graph.add_node("quote", quote_agent_node)
    graph.add_node("claims", claims_agent_node)
    graph.add_node("policy_qa", policy_qa_agent_node)
    graph.add_node("tools", tool_executor_node)

    # Edges
    graph.add_edge(START, "supervisor")

    # Supervisor routes to one of three sub-agents
    graph.add_conditional_edges(
        "supervisor",
        route_from_supervisor,
        {"quote": "quote", "claims": "claims", "policy_qa": "policy_qa"},
    )

    # Each sub-agent either calls tools or finishes
    for agent in ("quote", "claims", "policy_qa"):
        graph.add_conditional_edges(
            agent,
            should_use_tools,
            {"tools": "tools", "end": END},
        )

    # After tools run, loop back to the agent that called them.
    # We use the intent in state to route back correctly.
    graph.add_conditional_edges(
        "tools",
        lambda state: {
            "quote": "quote",
            "claim": "claims",
            "policy_qa": "policy_qa",
        }.get(state.get("intent", "policy_qa"), "policy_qa"),
        {"quote": "quote", "claims": "claims", "policy_qa": "policy_qa"},
    )

    # Compile with in-memory checkpointing (resumable conversations)
    return graph.compile(checkpointer=MemorySaver())


# Singleton compiled graph
_GRAPH = None


def get_graph():
    global _GRAPH
    if _GRAPH is None:
        _GRAPH = build_graph()
    return _GRAPH
