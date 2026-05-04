"""Indian motor insurance premium calculator.

Implements actual IRDAI-compliant math:
- IDV (Insured Declared Value) with depreciation slabs
- OD (Own Damage) premium based on IDV
- TP (Third Party) premium per IRDAI tariff
- NCB (No Claim Bonus) discount on OD
- GST 18%
- Zero Depreciation add-on
"""

# IRDAI depreciation slabs (% off ex-showroom price)
DEPRECIATION_SLABS = [
    (0.5, 0.05),    # 0–6 months: 5%
    (1.0, 0.15),    # 6m–1yr:    15%
    (2.0, 0.20),    # 1–2 yr:    20%
    (3.0, 0.30),    # 2–3 yr:    30%
    (4.0, 0.40),    # 3–4 yr:    40%
    (5.0, 0.50),    # 4–5 yr:    50%
]

# IRDAI Third-Party premium tariff (₹/year) by engine cc
TP_TARIFF = {
    "lt_1000": 2094,
    "1000_1500": 3416,
    "gt_1500": 7897,
}

# NCB ladder (claim-free years -> discount %)
NCB_LADDER = {0: 0.0, 1: 0.20, 2: 0.25, 3: 0.35, 4: 0.45, 5: 0.50}

OD_BASE_RATE = 0.03    # 3% of IDV (industry standard)
ZERO_DEP_RATE = 0.15   # 15% loading on OD
GST_RATE = 0.18


def calculate_idv(ex_showroom_price: int, vehicle_age_years: float) -> int:
    """Calculate IDV per IRDAI depreciation slabs."""
    depreciation_pct = 0.50
    for max_age, dep_pct in DEPRECIATION_SLABS:
        if vehicle_age_years <= max_age:
            depreciation_pct = dep_pct
            break
    return int(ex_showroom_price * (1 - depreciation_pct))


def get_tp_premium(engine_cc: int) -> int:
    if engine_cc < 1000:
        return TP_TARIFF["lt_1000"]
    elif engine_cc <= 1500:
        return TP_TARIFF["1000_1500"]
    return TP_TARIFF["gt_1500"]


def calculate_premium(
    ex_showroom_price: int,
    vehicle_age_years: float,
    engine_cc: int,
    ncb_years: int = 0,
    plan: str = "comprehensive",
) -> dict:
    """Calculate full premium breakdown for a single plan."""
    idv = calculate_idv(ex_showroom_price, vehicle_age_years)
    tp_premium = get_tp_premium(engine_cc)

    if plan == "third_party":
        subtotal = tp_premium
        return {
            "plan": "Third Party Only",
            "idv": 0,
            "od_premium": 0,
            "tp_premium": tp_premium,
            "ncb_discount": 0,
            "zero_dep_addon": 0,
            "subtotal": subtotal,
            "gst": int(subtotal * GST_RATE),
            "total": int(subtotal * (1 + GST_RATE)),
        }

    od_premium = int(idv * OD_BASE_RATE)
    ncb_pct = NCB_LADDER.get(min(ncb_years, 5), 0.0)
    ncb_discount = int(od_premium * ncb_pct)
    od_after_ncb = od_premium - ncb_discount

    zero_dep_addon = int(od_after_ncb * ZERO_DEP_RATE) if plan == "zero_dep" else 0

    subtotal = od_after_ncb + tp_premium + zero_dep_addon
    gst = int(subtotal * GST_RATE)

    plan_name = {
        "comprehensive": "Comprehensive",
        "zero_dep": "Comprehensive + Zero Depreciation",
    }.get(plan, plan)

    return {
        "plan": plan_name,
        "idv": idv,
        "od_premium": od_premium,
        "tp_premium": tp_premium,
        "ncb_discount": ncb_discount,
        "zero_dep_addon": zero_dep_addon,
        "subtotal": subtotal,
        "gst": gst,
        "total": subtotal + gst,
    }


def get_three_quotes(
    ex_showroom_price: int,
    vehicle_age_years: float,
    engine_cc: int,
    ncb_years: int = 0,
) -> list[dict]:
    """Return all three plan options."""
    return [
        calculate_premium(ex_showroom_price, vehicle_age_years, engine_cc, ncb_years, p)
        for p in ("third_party", "comprehensive", "zero_dep")
    ]
