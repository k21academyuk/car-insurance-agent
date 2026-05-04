"""Tools used by the Claims Agent.

Includes the showcase tool: GPT-4o Vision-based damage analysis.
"""
import base64
import json
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from pydantic import BaseModel, Field


class PolicyVerifyInput(BaseModel):
    policy_number: str = Field(description="Policy number, e.g. POL-2026-12345")


@tool("verify_policy", args_schema=PolicyVerifyInput)
def verify_policy_tool(policy_number: str) -> dict:
    """Verify a policy is active and within coverage period.

    In production: queries the policy database. For demo purposes,
    we accept any policy number matching the format POL-YYYY-NNNNN
    and return a mock active policy.
    """
    pn = policy_number.strip().upper()
    if not pn.startswith("POL-") or len(pn) < 12:
        return {
            "valid": False,
            "policy_number": pn,
            "reason": "Invalid policy number format. Expected: POL-YYYY-NNNNN",
        }
    # Mock active policy
    return {
        "valid": True,
        "policy_number": pn,
        "status": "ACTIVE",
        "plan": "Comprehensive",
        "idv": 850000,
        "expires_on": "2027-03-31",
        "vehicle": "Maruti Suzuki Swift VXI",
        "policyholder": "Test Customer",
    }


class DamageAnalysisInput(BaseModel):
    image_b64: str = Field(description="Base64-encoded damage photo (no data URL prefix)")
    incident_description: str = Field(
        default="", description="Optional description of how the incident occurred"
    )


@tool("analyze_damage_image", args_schema=DamageAnalysisInput)
def analyze_damage_image_tool(image_b64: str, incident_description: str = "") -> dict:
    """Analyze a damage photo using GPT-4o Vision and classify severity.

    Returns affected parts, severity per part, and overall severity rating.
    This is the showcase multimodal tool — uses real vision AI.
    """
    if not image_b64 or len(image_b64) < 100:
        return {"error": "No valid image provided"}

    # Strip data URL prefix if present
    if image_b64.startswith("data:"):
        image_b64 = image_b64.split(",", 1)[-1]

    vision_llm = ChatOpenAI(model="gpt-4o", temperature=0)

    prompt = f"""You are a motor insurance damage assessor. Analyze this car damage photo
and respond ONLY with valid JSON (no markdown fences, no extra text).

Incident description from customer: {incident_description or "(none provided)"}

Required JSON schema:
{{
  "affected_parts": [
    {{"part": "front bumper", "severity": "minor|moderate|severe"}},
    ...
  ],
  "overall_severity": "minor|moderate|severe|total_loss",
  "estimated_cost_inr": <integer estimate of repair cost in INR>,
  "description": "<one-sentence damage summary>",
  "repair_recommendation": "<repair|replace|total_loss>"
}}

Cost guidance:
- Minor scratch/dent: ₹3,000–15,000
- Moderate panel damage: ₹15,000–50,000
- Severe damage (panel + light + bumper): ₹50,000–150,000
- Total loss: > ₹400,000 or > 75% of vehicle IDV
"""

    try:
        response = vision_llm.invoke([{
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
                },
            ],
        }])
        content = response.content.strip()
        # Remove possible code fences
        if content.startswith("```"):
            content = content.split("```")[1]
            if content.startswith("json"):
                content = content[4:]
            content = content.strip()
        result = json.loads(content)
        return result
    except json.JSONDecodeError as e:
        return {"error": f"Vision response parse error: {e}",
                "raw_response": content[:500] if 'content' in dir() else ""}
    except Exception as e:
        return {"error": f"Vision analysis failed: {type(e).__name__}: {e}"}


class PayoutInput(BaseModel):
    estimated_repair_cost_inr: int = Field(description="Repair cost estimate from damage analysis")
    policy_idv: int = Field(description="Policy IDV (sum insured)")
    plan: str = Field(default="Comprehensive", description="Policy plan name")
    deductible_inr: int = Field(default=2500, description="Compulsory deductible (default ₹2,500)")


@tool("estimate_payout", args_schema=PayoutInput)
def estimate_payout_tool(
    estimated_repair_cost_inr: int,
    policy_idv: int,
    plan: str = "Comprehensive",
    deductible_inr: int = 2500,
) -> dict:
    """Calculate the estimated insurance payout for a claim.

    Considers the policy plan, IDV cap, depreciation (unless Zero-Dep),
    and compulsory deductible.
    """
    if "zero" in plan.lower() or "zero-dep" in plan.lower():
        # Zero-dep: no depreciation deduction
        depreciation_deduction = 0
        plan_note = "Zero Depreciation — no depreciation on parts"
    else:
        # Standard comprehensive: ~30% depreciation on plastic/metal parts on average
        depreciation_deduction = int(estimated_repair_cost_inr * 0.30)
        plan_note = "Standard Comprehensive — 30% depreciation applied"

    payout_before_cap = estimated_repair_cost_inr - depreciation_deduction - deductible_inr
    payout = max(0, min(payout_before_cap, policy_idv))

    # Total loss check
    is_total_loss = estimated_repair_cost_inr > (policy_idv * 0.75)

    return {
        "estimated_repair_cost_inr": estimated_repair_cost_inr,
        "depreciation_deduction_inr": depreciation_deduction,
        "deductible_inr": deductible_inr,
        "estimated_payout_inr": payout,
        "is_total_loss": is_total_loss,
        "plan_note": plan_note,
        "out_of_pocket_inr": estimated_repair_cost_inr - payout,
    }


CLAIMS_TOOLS = [verify_policy_tool, analyze_damage_image_tool, estimate_payout_tool]
