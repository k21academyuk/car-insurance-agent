"""Mock VAHAN vehicle database with realistic Indian car prices.

In production, this would call the actual VAHAN API. For the capstone,
we ship a catalog of common Indian cars.
"""

VEHICLE_CATALOG = {
    # Maruti Suzuki
    "swift": {
        "make": "Maruti Suzuki", "model": "Swift", "fuel": "Petrol",
        "engine_cc": 1197, "ex_showroom_price": 650000,
    },
    "baleno": {
        "make": "Maruti Suzuki", "model": "Baleno", "fuel": "Petrol",
        "engine_cc": 1197, "ex_showroom_price": 720000,
    },
    "wagonr": {
        "make": "Maruti Suzuki", "model": "WagonR", "fuel": "Petrol",
        "engine_cc": 998, "ex_showroom_price": 580000,
    },
    "brezza": {
        "make": "Maruti Suzuki", "model": "Brezza", "fuel": "Petrol",
        "engine_cc": 1462, "ex_showroom_price": 980000,
    },
    "ertiga": {
        "make": "Maruti Suzuki", "model": "Ertiga", "fuel": "Petrol",
        "engine_cc": 1462, "ex_showroom_price": 1050000,
    },
    # Hyundai
    "i20": {
        "make": "Hyundai", "model": "i20", "fuel": "Petrol",
        "engine_cc": 1197, "ex_showroom_price": 750000,
    },
    "creta": {
        "make": "Hyundai", "model": "Creta", "fuel": "Petrol",
        "engine_cc": 1497, "ex_showroom_price": 1150000,
    },
    "venue": {
        "make": "Hyundai", "model": "Venue", "fuel": "Petrol",
        "engine_cc": 1197, "ex_showroom_price": 850000,
    },
    # Tata
    "nexon": {
        "make": "Tata", "model": "Nexon", "fuel": "Petrol",
        "engine_cc": 1199, "ex_showroom_price": 850000,
    },
    "punch": {
        "make": "Tata", "model": "Punch", "fuel": "Petrol",
        "engine_cc": 1199, "ex_showroom_price": 660000,
    },
    "harrier": {
        "make": "Tata", "model": "Harrier", "fuel": "Diesel",
        "engine_cc": 1956, "ex_showroom_price": 1650000,
    },
    # Honda
    "city": {
        "make": "Honda", "model": "City", "fuel": "Petrol",
        "engine_cc": 1498, "ex_showroom_price": 1250000,
    },
    "amaze": {
        "make": "Honda", "model": "Amaze", "fuel": "Petrol",
        "engine_cc": 1199, "ex_showroom_price": 720000,
    },
    # Kia
    "seltos": {
        "make": "Kia", "model": "Seltos", "fuel": "Petrol",
        "engine_cc": 1497, "ex_showroom_price": 1180000,
    },
    "sonet": {
        "make": "Kia", "model": "Sonet", "fuel": "Petrol",
        "engine_cc": 1197, "ex_showroom_price": 850000,
    },
    # Toyota
    "innova": {
        "make": "Toyota", "model": "Innova Crysta", "fuel": "Diesel",
        "engine_cc": 2393, "ex_showroom_price": 2050000,
    },
    "fortuner": {
        "make": "Toyota", "model": "Fortuner", "fuel": "Diesel",
        "engine_cc": 2755, "ex_showroom_price": 3450000,
    },
    # Mahindra
    "xuv700": {
        "make": "Mahindra", "model": "XUV700", "fuel": "Petrol",
        "engine_cc": 1999, "ex_showroom_price": 1450000,
    },
    "thar": {
        "make": "Mahindra", "model": "Thar", "fuel": "Diesel",
        "engine_cc": 2184, "ex_showroom_price": 1550000,
    },
    "scorpio": {
        "make": "Mahindra", "model": "Scorpio-N", "fuel": "Diesel",
        "engine_cc": 2198, "ex_showroom_price": 1450000,
    },
}


def lookup_vehicle(query: str) -> dict | None:
    """Fuzzy lookup by model name."""
    q = query.lower().strip()
    # Direct match
    if q in VEHICLE_CATALOG:
        return VEHICLE_CATALOG[q]
    # Substring match
    for key, vehicle in VEHICLE_CATALOG.items():
        if q in key or q in vehicle["model"].lower():
            return vehicle
    return None


def list_supported_vehicles() -> list[str]:
    """Return human-readable list of supported vehicles."""
    return sorted({f"{v['make']} {v['model']}" for v in VEHICLE_CATALOG.values()})
