"""Tools used by the Quote Agent."""
from langchain_core.tools import tool
from pydantic import BaseModel, Field

from app.services.premium_calc import get_three_quotes
from app.services.vehicle_catalog import lookup_vehicle, list_supported_vehicles


class VehicleLookupInput(BaseModel):
    model_config = {"protected_namespaces": ()}
    model_query: str = Field(
        description="Vehicle model name to look up (e.g., 'Swift', 'Creta', 'Nexon')"
    )


@tool("vehicle_lookup", args_schema=VehicleLookupInput)
def vehicle_lookup_tool(model_query: str) -> dict:
    """Look up vehicle specs (make, model, engine cc, ex-showroom price).

    Use this when the user mentions a car model. Returns vehicle metadata
    needed to calculate the premium.
    """
    vehicle = lookup_vehicle(model_query)
    if vehicle is None:
        return {
            "found": False,
            "supported_models": list_supported_vehicles()[:15],
            "message": f"Model '{model_query}' not found. Try one of the supported models.",
        }
    return {"found": True, **vehicle}


class PremiumInput(BaseModel):
    ex_showroom_price: int = Field(description="Vehicle ex-showroom price in INR")
    vehicle_age_years: float = Field(description="Vehicle age in years (e.g. 2.5)")
    engine_cc: int = Field(description="Engine capacity in cc")
    ncb_years: int = Field(default=0, description="Claim-free years (0–5)")


@tool("calculate_premium", args_schema=PremiumInput)
def calculate_premium_tool(
    ex_showroom_price: int,
    vehicle_age_years: float,
    engine_cc: int,
    ncb_years: int = 0,
) -> dict:
    """Calculate motor insurance premium quotes for all 3 plans.

    Returns Third-Party, Comprehensive, and Comprehensive+ZeroDep quotes
    with full breakdown (IDV, OD, TP, NCB, GST, total) per IRDAI rules.
    """
    quotes = get_three_quotes(ex_showroom_price, vehicle_age_years, engine_cc, ncb_years)
    return {"quotes": quotes, "currency": "INR"}


# Mock pincode risk data — in production this would call a real risk API
HIGH_RISK_PINCODES = {"400001", "400002", "110001", "110002", "560001"}
MEDIUM_RISK_PINCODES = {"400070", "400071", "560037", "600001"}


class PincodeInput(BaseModel):
    pincode: str = Field(description="6-digit Indian pincode")


@tool("pincode_risk", args_schema=PincodeInput)
def pincode_risk_tool(pincode: str) -> dict:
    """Check accident/theft risk tier for an Indian pincode.

    Returns risk tier (low / medium / high) and any premium loading.
    Used during underwriting to adjust quotes for high-risk areas.
    """
    pincode = pincode.strip()
    if pincode in HIGH_RISK_PINCODES:
        return {"pincode": pincode, "risk_tier": "high", "loading_pct": 10,
                "note": "Urban metro with high theft/accident rate"}
    if pincode in MEDIUM_RISK_PINCODES:
        return {"pincode": pincode, "risk_tier": "medium", "loading_pct": 5,
                "note": "Moderate risk area"}
    return {"pincode": pincode, "risk_tier": "low", "loading_pct": 0,
            "note": "Standard risk"}


QUOTE_TOOLS = [vehicle_lookup_tool, calculate_premium_tool, pincode_risk_tool]
