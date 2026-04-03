"""
fetch_country_data.py
=====================
Step 1 of the data pipeline.
Downloads country data from REST Countries API and Natural Earth GeoJSON,
merges them, normalises values for gameplay, and writes:

  ../data/countries.json   — all country data Godot needs
  ../data/adjacencies.json — border graph

Usage:
  pip install requests
  python fetch_country_data.py
"""

import json
import math
import random
import urllib.request
import urllib.error
import sys
from pathlib import Path

OUT_DIR = Path(__file__).parent.parent / "data"
OUT_DIR.mkdir(exist_ok=True)

COUNTRIES_OUT    = OUT_DIR / "countries.json"
ADJACENCIES_OUT  = OUT_DIR / "adjacencies.json"

# API requires ?fields= and rejects too many fields at once — fetch in two batches
REST_COUNTRIES_URL_A = "https://restcountries.com/v3.1/all?fields=name,cca3,cca2,capital,region,subregion"
REST_COUNTRIES_URL_B = "https://restcountries.com/v3.1/all?fields=cca3,population,area,latlng,landlocked,borders"

MAP_WIDTH  = 16384
MAP_HEIGHT = 8192


# ── Helpers ───────────────────────────────────────────────────────────────────

def log_scale(value: float, min_val: float, max_val: float) -> float:
    """Compress a wide range into 1–1000 via log10."""
    if value <= 0:
        return 1.0
    log_v   = math.log10(max(value, min_val))
    log_min = math.log10(min_val)
    log_max = math.log10(max_val)
    return round(max(1.0, min(1000.0, (log_v - log_min) / (log_max - log_min) * 1000)))


def lat_lon_to_pixel(lat: float, lon: float) -> list[float]:
    """Equirectangular projection → pixel coords on MAP_WIDTH×MAP_HEIGHT."""
    x = (lon + 180.0) / 360.0 * MAP_WIDTH
    y = (90.0 - lat) / 180.0 * MAP_HEIGHT
    return [round(x, 2), round(y, 2)]


def assign_power_tier(gdp_norm: float, mil_norm: float, pop_norm: float) -> str:
    score = gdp_norm * 0.5 + mil_norm * 0.3 + pop_norm * 0.2
    if score >= 850:  return "S"
    if score >= 650:  return "A"
    if score >= 400:  return "B"
    if score >= 200:  return "C"
    return "D"


COUNTRY_COLORS: dict[str, list[int]] = {
    "USA": [80, 120, 180],    "CHN": [190, 160, 70],
    "RUS": [140, 100, 80],    "GBR": [180, 60, 70],
    "FRA": [80, 100, 170],    "DEU": [120, 120, 130],
    "JPN": [200, 180, 180],   "IND": [60, 140, 80],
    "BRA": [80, 160, 60],     "CAN": [180, 80, 80],
    "AUS": [180, 160, 80],    "ITA": [100, 170, 100],
    "ESP": [200, 180, 60],    "MEX": [160, 160, 50],
    "TUR": [170, 130, 100],   "SAU": [160, 170, 80],
    "IRN": [150, 100, 120],   "ISR": [120, 180, 190],
    "EGY": [190, 170, 100],   "NGA": [80, 130, 60],
    "ZAF": [130, 110, 80],    "ARG": [130, 170, 200],
    "KOR": [160, 130, 170],   "IDN": [140, 110, 70],
    "PAK": [80, 120, 70],     "POL": [200, 140, 140],
    "UKR": [180, 180, 80],    "NOR": [140, 60, 70],
    "SWE": [80, 120, 150],    "JOR": [180, 130, 140],
    "IRQ": [150, 120, 90],    "ARE": [130, 150, 120],
    "COL": [170, 150, 60],    "PER": [160, 100, 80],
    "CHL": [120, 70, 70],     "VEN": [170, 140, 50],
    "CUB": [140, 80, 80],     "ETH": [90, 140, 90],
    "KEN": [120, 90, 60],     "THA": [160, 120, 160],
    "VNM": [170, 100, 70],    "MYS": [100, 130, 100],
    "PHL": [130, 130, 170],   "AFG": [130, 120, 100],
    "SYR": [160, 140, 120],   "LBN": [160, 100, 110],
    "PSE": [120, 150, 120],   "LBY": [150, 150, 100],
    "SDN": [140, 120, 80],    "MAR": [150, 90, 80],
    "DZA": [120, 140, 100],   "TUN": [130, 120, 150],
}


def unique_color(index: int, total: int, iso: str = "") -> list[int]:
    """Generate a visually distinct color for each country."""
    if iso in COUNTRY_COLORS:
        return COUNTRY_COLORS[iso]
    hue = (index / total) * 360.0
    h = hue / 60.0
    i = int(h)
    f = h - i
    s, v = 0.45, 0.72
    p = int(v * (1 - s) * 255)
    q = int(v * (1 - s * f) * 255)
    t = int(v * (1 - s * (1 - f)) * 255)
    vi = int(v * 255)
    combos = [(vi,t,p),(q,vi,p),(p,vi,t),(p,q,vi),(t,p,vi),(vi,p,q)]
    r, g, b = combos[i % 6]
    return [r, g, b]


# ── Real GDP estimates (billions USD, 2026 approximate) ──────────────────────
# Used to seed GDP since REST Countries doesn't include GDP.
# Covers top 60 economies; rest get population-derived estimates.
GDP_ESTIMATES: dict[str, float] = {
    "USA": 28000, "CHN": 18500, "DEU": 4500, "JPN": 4200, "IND": 3900,
    "GBR": 3200, "FRA": 3100, "ITA": 2200, "CAN": 2100, "KOR": 1800,
    "BRA": 2100, "AUS": 1700, "RUS": 1850, "ESP": 1600, "MEX": 1500,
    "IDN": 1400, "NLD": 1100, "SAU": 1050, "TUR": 1000, "CHE": 900,
    "POL": 780,  "SWE": 620,  "BEL": 610,  "ARG": 590,  "THA": 550,
    "NOR": 540,  "ARE": 530,  "ZAF": 420,  "EGY": 410,  "IRN": 380,
    "VNM": 370,  "ISR": 360,  "MYS": 430,  "DNK": 390,  "SGP": 420,
    "PHL": 450,  "HKG": 360,  "CHL": 330,  "FIN": 310,  "AUT": 530,
    "IRQ": 260,  "COL": 340,  "NZL": 250,  "PRT": 290,  "CZE": 310,
    "ROU": 320,  "PER": 260,  "NGA": 390,  "BGD": 430,  "PAK": 380,
    "KAZ": 220,  "HUN": 210,  "UKR": 160,  "KWT": 180,  "QAT": 230,
    "ETH": 160,  "GHA": 80,   "TZA": 90,   "KEN": 120,  "AGO": 95,
}

MILITARY_ESTIMATES: dict[str, float] = {
    "USA": 1000, "CHN": 850,  "RUS": 780,  "IND": 620,  "GBR": 560,
    "FRA": 550,  "KOR": 500,  "JPN": 480,  "DEU": 440,  "ISR": 480,
    "SAU": 420,  "PAK": 410,  "TUR": 430,  "IRN": 400,  "BRA": 360,
    "ITA": 340,  "EGY": 380,  "AUS": 360,  "CAN": 320,  "ESP": 300,
}

# Manual tier overrides — real geopolitical weight, not just GDP math
TIER_OVERRIDES: dict[str, str] = {
    "USA": "S", "CHN": "S",
    "RUS": "A", "GBR": "A", "FRA": "A", "DEU": "A", "JPN": "A", "IND": "A",
    "BRA": "B", "TUR": "B", "SAU": "B", "IRN": "B", "ISR": "B",
    "KOR": "B", "AUS": "B", "ITA": "B", "CAN": "B", "PAK": "B",
    "EGY": "B", "IDN": "B", "POL": "B", "ESP": "B", "NGA": "B",
    "MEX": "B", "ARE": "B", "ZAF": "B", "UKR": "B", "THA": "B",
    "ARG": "B", "NLD": "B", "CHE": "B", "NOR": "B",
    "JOR": "C", "QAT": "C", "KWT": "C", "BHR": "C", "OMN": "C",
    "LBN": "C", "TUN": "C", "HUN": "C", "CZE": "C", "ROU": "C",
    "PRT": "C", "GRC": "C", "NZL": "C", "IRL": "C", "SGP": "C",
    "MYS": "C", "PHL": "C", "VNM": "C", "CHL": "C", "COL": "C",
    "PER": "C", "CUB": "C", "SWE": "C", "FIN": "C",
    "DNK": "C", "BEL": "C", "AUT": "C",
    "BGD": "C", "MMR": "C", "ETH": "C", "KEN": "C",
    "MAR": "C", "DZA": "C", "IRQ": "C", "SYR": "C", "LBY": "C",
    "SOM": "D", "HTI": "D", "YEM": "D", "SSD": "D", "AFG": "D",
    "CAF": "D", "TCD": "D", "MLI": "D", "BFA": "D", "NER": "D",
    "ERI": "D", "SLE": "D", "LBR": "D", "GNB": "D", "COD": "D",
}

# Stability based on Fragile States Index 2024 (inverted & normalized to 0-100).
# FSI scores: 0 = most stable, 120 = most fragile.
# Our scale: stability = max(5, min(95, int(100 - fsi * 0.83)))
# Manual adjustments for 2025-2026 context where FSI data lags.
STABILITY_OVERRIDES: dict[str, int] = {
    # Very stable — FSI < 25 (75-95)
    "FIN": 93, "NOR": 92, "CHE": 92, "DNK": 91, "ISL": 93, "LUX": 91,
    "NZL": 90, "SWE": 89, "IRL": 88, "AUS": 87, "CAN": 86, "NLD": 85,
    "AUT": 85, "DEU": 83, "PRT": 82, "JPN": 82, "SGP": 84, "GBR": 80,
    "BEL": 79, "CZE": 78, "USA": 76, "ESP": 76, "KOR": 75, "FRA": 75,
    "ITA": 73, "POL": 72, "CHL": 72, "URY": 80, "EST": 81, "SVN": 80,
    # Stable — FSI 25-50 (55-74)
    "ARE": 74, "QAT": 75, "OMN": 72, "KWT": 70, "JOR": 66, "BHR": 64,
    "SAU": 63, "MYS": 66, "CHN": 68, "RWA": 60, "BWA": 68, "CRI": 70,
    "PAN": 65, "IDN": 62, "VNM": 62, "MAR": 59, "THA": 58,
    "HUN": 65, "ROU": 63, "GRC": 70, "ARG": 55, "BRA": 55,
    "GHA": 57, "SEN": 56, "TUR": 54, "ISR": 52, "CUB": 55,
    "MEX": 50, "RUS": 48, "KAZ": 56, "AZE": 50, "BLR": 48,
    # Moderately unstable — FSI 50-75 (35-54)
    "EGY": 45, "DZA": 46, "TUN": 50, "IND": 48, "PER": 48, "COL": 48,
    "PHL": 44, "UKR": 38, "IRN": 42, "BGD": 38, "PRY": 45,
    "KEN": 42, "NGA": 38, "PAK": 35, "NIC": 38, "VEN": 32,
    "KHM": 42, "UGA": 38, "TZA": 42, "ZMB": 40,
    "LBN": 30, "IRQ": 33, "PSE": 30, "GTM": 35, "HND": 36,
    # Unstable — FSI 75-95 (15-34)
    "SYR": 28, "MMR": 22, "LBY": 25, "ETH": 25, "CMR": 30,
    "MOZ": 28, "COG": 28, "GNQ": 30, "ERI": 25, "ZWE": 28,
    "COD": 20, "BDI": 22, "GIN": 25, "TCD": 22, "NER": 24,
    "BFA": 20, "MLI": 20, "HTI": 15, "CAF": 15,
    # Very unstable / active conflict — FSI > 95 (5-14)
    "SOM": 8, "YEM": 10, "SSD": 8, "SDN": 12, "AFG": 15,
}

GOVERNMENT_TYPES: dict[str, str] = {
    # Official self-designations — what each country calls itself
    # Presidential Republic
    "USA": "Federal Presidential Republic", "BRA": "Federal Presidential Republic",
    "MEX": "Federal Presidential Republic", "ARG": "Federal Presidential Republic",
    "KOR": "Presidential Republic", "IDN": "Presidential Republic",
    "PHL": "Presidential Republic", "COL": "Presidential Republic",
    "CHL": "Presidential Republic", "PER": "Presidential Republic",
    "NGA": "Federal Presidential Republic", "GHA": "Presidential Republic",
    "KEN": "Presidential Republic", "ZAF": "Parliamentary Republic",
    "TUR": "Presidential Republic", "UKR": "Presidential Republic",
    # Parliamentary
    "GBR": "Parliamentary Monarchy", "DEU": "Federal Parliamentary Republic",
    "ITA": "Parliamentary Republic", "CAN": "Parliamentary Monarchy",
    "AUS": "Parliamentary Monarchy", "JPN": "Parliamentary Monarchy",
    "IND": "Federal Parliamentary Republic", "ISR": "Parliamentary Republic",
    "NLD": "Parliamentary Monarchy", "BEL": "Parliamentary Monarchy",
    "SWE": "Parliamentary Monarchy", "NOR": "Parliamentary Monarchy",
    "DNK": "Parliamentary Monarchy", "FIN": "Parliamentary Republic",
    "IRL": "Parliamentary Republic", "NZL": "Parliamentary Monarchy",
    "GRC": "Parliamentary Republic", "CZE": "Parliamentary Republic",
    "POL": "Parliamentary Republic", "HUN": "Parliamentary Republic",
    "ROU": "Parliamentary Republic", "BGD": "Parliamentary Republic",
    "MYS": "Federal Parliamentary Monarchy", "SGP": "Parliamentary Republic",
    "PRT": "Parliamentary Republic", "ESP": "Parliamentary Monarchy",
    "AUT": "Federal Parliamentary Republic", "CHE": "Federal Republic",
    "IRQ": "Federal Parliamentary Republic", "LBN": "Parliamentary Republic",
    "TUN": "Parliamentary Republic", "PAK": "Federal Parliamentary Republic",
    "ETH": "Federal Parliamentary Republic", "THA": "Parliamentary Monarchy",
    # Semi-Presidential
    "FRA": "Semi-Presidential Republic",
    # Kingdom / Monarchy
    "JOR": "Constitutional Monarchy", "MAR": "Constitutional Monarchy",
    "KWT": "Constitutional Monarchy", "BHR": "Constitutional Monarchy",
    "SAU": "Kingdom", "ARE": "Federation",
    "QAT": "Emirate", "OMN": "Sultanate",
    "BRN": "Sultanate", "SWZ": "Kingdom",
    # Republic (official designation)
    "RUS": "Federal Republic", "BLR": "Presidential Republic",
    "AZE": "Presidential Republic", "TKM": "Presidential Republic",
    "TJK": "Presidential Republic", "UZB": "Presidential Republic",
    "KAZ": "Presidential Republic", "EGY": "Presidential Republic",
    "DZA": "Presidential Republic", "VEN": "Federal Presidential Republic",
    "NIC": "Presidential Republic", "KHM": "Parliamentary Monarchy",
    "RWA": "Presidential Republic", "UGA": "Presidential Republic",
    "TCD": "Presidential Republic", "CMR": "Presidential Republic",
    "COG": "Presidential Republic", "GNQ": "Presidential Republic",
    "ERI": "Presidential Republic", "SYR": "Presidential Republic",
    # People's Republic / Socialist
    "CHN": "People's Republic", "VNM": "Socialist Republic",
    "CUB": "Socialist Republic", "LAO": "People's Republic",
    # Islamic Republic
    "IRN": "Islamic Republic", "AFG": "Islamic Emirate",
    # Transitional / Provisional
    "MMR": "Provisional Government", "MLI": "Transitional Government",
    "BFA": "Transitional Government", "NER": "Transitional Government",
    "SDN": "Transitional Government", "GIN": "Transitional Government",
    "SOM": "Federal Republic", "LBY": "Transitional Government",
    "YEM": "Presidential Republic", "SSD": "Presidential Republic",
    "HTI": "Presidential Republic", "CAF": "Presidential Republic",
    # PSE
    "PSE": "Presidential Republic",
}


# ── Main ─────────────────────────────────────────────────────────────────────

def fetch(url: str) -> dict | list:
    print(f"  Fetching {url[:80]}...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def build_countries() -> tuple[list, dict]:
    print("Fetching REST Countries API (batch A)...")
    raw_a = fetch(REST_COUNTRIES_URL_A)
    print("Fetching REST Countries API (batch B)...")
    raw_b = fetch(REST_COUNTRIES_URL_B)

    # Merge by cca3
    b_by_iso = {e["cca3"]: e for e in raw_b if "cca3" in e}
    for entry in raw_a:
        iso = entry.get("cca3", "")
        if iso in b_by_iso:
            entry.update({k: v for k, v in b_by_iso[iso].items() if k != "cca3"})

    raw = raw_a
    total = len(raw)

    # First pass: compute raw GDP for normalization bounds
    gdp_raw: dict[str, float] = {}
    pop_raw: dict[str, int]   = {}
    for entry in raw:
        iso3 = entry.get("cca3", "")
        pop  = entry.get("population", 100000)
        gdp  = GDP_ESTIMATES.get(iso3, max(0.5, pop / 1_000_000 * 1.5))
        gdp_raw[iso3] = gdp
        pop_raw[iso3] = pop

    # Normalization bounds
    gdp_min, gdp_max = 0.05, 28000.0
    pop_min, pop_max = 800, 1_400_000_000

    countries    = []
    adjacencies  = {}

    for idx, entry in enumerate(raw):
        iso3 = entry.get("cca3", "")
        if not iso3:
            continue

        name   = entry.get("name", {}).get("common", iso3)
        latlng = entry.get("latlng", [0.0, 0.0])
        lat    = latlng[0] if len(latlng) > 0 else 0.0
        lon    = latlng[1] if len(latlng) > 1 else 0.0
        pop    = entry.get("population", 100000)
        gdp    = gdp_raw.get(iso3, 1.0)
        mil    = MILITARY_ESTIMATES.get(iso3, max(1.0, gdp * 0.02))

        gdp_norm = log_scale(gdp, gdp_min, gdp_max)
        pop_norm = log_scale(pop, pop_min, pop_max)
        mil_norm = log_scale(mil, 0.1, 1000.0)

        borders = entry.get("borders", [])   # list of cca3 codes
        adjacencies[iso3] = borders

        country = {
            "iso":               iso3,
            "iso2":              entry.get("cca2", ""),
            "name":              name,
            "capital":           (entry.get("capital") or [""])[0],
            "region":            entry.get("region", ""),
            "subregion":         entry.get("subregion", ""),
            "population":        pop,
            "area_km2":          entry.get("area", 0),
            "landlocked":        entry.get("landlocked", False),
            "latlng":            [lat, lon],
            "centroid":          lat_lon_to_pixel(lat, lon),
            "borders":           borders,
            # Gameplay values (normalised)
            "gdp_normalized":    gdp_norm,
            "population_normalized": pop_norm,
            "military_normalized":   mil_norm,
            "stability":         STABILITY_OVERRIDES.get(iso3, max(20, min(90, int(gdp_norm / 12 + 30 + random.uniform(-5, 5))))),
            "power_tier":        TIER_OVERRIDES.get(iso3, assign_power_tier(gdp_norm, mil_norm, pop_norm)),
            # Map rendering
            "map_color":         unique_color(idx, total, iso3),
            "flag_emoji":        "",   # filled by geojson_to_godot.py from flag SVG name
            # Economy starting values
            "gdp_raw_billions":  round(gdp, 2),
            "debt_to_gdp":       round(random.uniform(20, 80), 1),
            "credit_rating":     max(10, min(100, int(gdp_norm / 10))),
            "infrastructure":    max(10, min(95, int(gdp_norm / 12 + 20))),
            "literacy_rate":     max(30, min(99, int(gdp_norm / 12 + 40))),
            # Government
            "government_type":   GOVERNMENT_TYPES.get(iso3, "Republic"),
        }
        countries.append(country)

    return countries, adjacencies


def main():
    print("=== War Strategy Game — Data Pipeline Step 1 ===\n")
    try:
        countries, adjacencies = build_countries()
    except Exception as e:
        print(f"\nERROR: Could not reach REST Countries API: {e}")
        print("Check your internet connection and try again.")
        sys.exit(1)

    with open(COUNTRIES_OUT, "w", encoding="utf-8") as f:
        json.dump(countries, f, indent=2, ensure_ascii=False)
    print(f"\nOK: Wrote {len(countries)} countries -> {COUNTRIES_OUT}")

    with open(ADJACENCIES_OUT, "w", encoding="utf-8") as f:
        json.dump(adjacencies, f, indent=2)
    print(f"OK: Wrote adjacency graph -> {ADJACENCIES_OUT}")
    print("\nNext step: python geojson_to_godot.py")


if __name__ == "__main__":
    main()
