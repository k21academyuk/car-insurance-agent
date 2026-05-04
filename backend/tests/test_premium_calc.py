"""Unit tests for premium calculator."""
import pytest
from app.services.premium_calc import (
    calculate_idv,
    get_tp_premium,
    calculate_premium,
    get_three_quotes,
)


class TestIDV:
    def test_new_car(self):
        # 0–6 months: 5% depreciation
        assert calculate_idv(1_000_000, 0.3) == 950_000

    def test_one_year_old(self):
        # 6m–1y: 15%
        assert calculate_idv(1_000_000, 0.9) == 850_000

    def test_three_year_old(self):
        # 2–3y: 30%
        assert calculate_idv(1_000_000, 2.5) == 700_000

    def test_five_year_old(self):
        # 4–5y: 50%
        assert calculate_idv(1_000_000, 4.9) == 500_000


class TestTPPremium:
    def test_small_car(self):
        assert get_tp_premium(800) == 2094

    def test_mid_car(self):
        assert get_tp_premium(1197) == 3416

    def test_large_car(self):
        assert get_tp_premium(2000) == 7897


class TestPremium:
    def test_third_party_only(self):
        result = calculate_premium(650_000, 2.0, 1197, 0, "third_party")
        assert result["plan"] == "Third Party Only"
        assert result["od_premium"] == 0
        assert result["tp_premium"] == 3416
        assert result["total"] == int(3416 * 1.18)  # GST

    def test_comprehensive_with_ncb(self):
        result = calculate_premium(650_000, 2.0, 1197, 1, "comprehensive")
        assert result["plan"] == "Comprehensive"
        # IDV = 650000 * 0.7 (2-3yr slab — actually 2.0 falls in 1-2yr slab = 0.8)
        # Actually 2.0 is exactly the boundary; loop will hit 2.0 first => 20%
        assert result["idv"] == 520_000  # 650k * 0.8
        # OD = 3% of 520k = 15600
        # NCB at 1 year = 20% off OD = 3120
        # OD after NCB = 12480
        assert result["od_premium"] == 15600
        assert result["ncb_discount"] == 3120

    def test_zero_dep_loading(self):
        comp = calculate_premium(650_000, 2.0, 1197, 0, "comprehensive")
        zd = calculate_premium(650_000, 2.0, 1197, 0, "zero_dep")
        assert zd["zero_dep_addon"] > 0
        assert zd["total"] > comp["total"]


class TestThreeQuotes:
    def test_three_plans_returned(self):
        quotes = get_three_quotes(650_000, 2.0, 1197, 1)
        assert len(quotes) == 3
        assert quotes[0]["plan"] == "Third Party Only"
        assert quotes[1]["plan"] == "Comprehensive"
        assert quotes[2]["plan"] == "Comprehensive + Zero Depreciation"

    def test_pricing_order(self):
        # TP < Comprehensive < Zero-Dep
        quotes = get_three_quotes(650_000, 2.0, 1197, 1)
        assert quotes[0]["total"] < quotes[1]["total"] < quotes[2]["total"]
