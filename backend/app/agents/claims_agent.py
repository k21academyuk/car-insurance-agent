"""Claims Agent — FNOL handler.

Uses vision-based damage analysis as its showcase capability.
"""
from langchain_openai import ChatOpenAI
from langchain_core.messages import SystemMessage, HumanMessage

from app.workflows.state import AgentState
from app.tools.claims_tools import CLAIMS_TOOLS


CLAIMS_AGENT_PROMPT = """You are a Claims Specialist for AutoShield Motor Insurance.

You handle FNOL (First Notice of Loss). Your job is to take a customer through
filing a motor insurance claim quickly and empathetically.

INFORMATION YOU NEED:
1. Policy number (format: POL-YYYY-NNNNN, e.g., POL-2026-12345)
2. What happened — brief incident description
3. When and where it happened
4. A photo of the damage (the user can upload this through the UI)

WORKFLOW:
- Start with empathy ("Sorry to hear about the incident")
- Ask for the policy number → use `verify_policy` to confirm coverage
- Ask for incident description (date, location, what happened)
- IF a damage image is available in the conversation context → use `analyze_damage_image`
  with the customer's incident description. The image will be available as base64.
- Once you have repair cost estimate from vision → use `estimate_payout` with the policy IDV
- Present a clear claim summary:
  * Damage assessed (what parts, severity)
  * Estimated repair cost
  * Estimated payout (after depreciation + deductible)
  * Out-of-pocket cost the customer should expect
  * Next steps (a claim ID, network garage referral, surveyor visit if needed)

CRITICAL:
- If estimated payout > ₹50,000, mention that a human surveyor will visit before approval
- Format INR with Indian commas: ₹1,23,456
- Be calm, clear, professional. Don't dump tool JSON.

When you analyze a damage image, ALWAYS call `analyze_damage_image` followed by
`estimate_payout` in the same response — chain them.
"""


def claims_agent_node(state: AgentState) -> dict:
    """Claims agent — vision + payout estimation."""
    llm = ChatOpenAI(model="gpt-4o", temperature=0).bind_tools(CLAIMS_TOOLS)

    # If a damage image is in state, surface it to the agent so it knows to call the vision tool
    extra_context = ""
    if state.get("damage_image_b64"):
        extra_context = (
            "\n\n[SYSTEM NOTE: A damage image has been uploaded by the customer "
            "and is available. When you call `analyze_damage_image`, "
            "use image_b64='__USE_STATE_IMAGE__' as a placeholder — the system "
            "will substitute the actual image bytes at runtime.]"
        )

    messages = [SystemMessage(content=CLAIMS_AGENT_PROMPT + extra_context)] + state["messages"]
    response = llm.invoke(messages)

    return {"messages": [response]}
