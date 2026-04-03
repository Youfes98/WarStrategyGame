"""
geojson_to_godot.py
===================
Step 2 of the data pipeline.
Downloads Natural Earth GeoJSON for countries and admin-1 provinces,
generates:

  provinces.png               — unique detect-colors per province (O(1) click detection)
  data/provinces.json         — province data (id, name, parent_iso, polygon, centroid, detect_color)
  data/province_adjacencies.json  — province-level border graph
  data/countries.json         — updated with better centroids from GeoJSON

Requirements:
  pip install Pillow
  pip install numpy            (optional but recommended for adjacency detection)

Usage:
  python geojson_to_godot.py
"""

import json
import urllib.request
import sys
from pathlib import Path
from collections import defaultdict

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)

DATA_DIR   = Path(__file__).parent.parent / "data"
ASSETS_DIR = Path(__file__).parent.parent / "assets" / "map"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

COUNTRIES_JSON    = DATA_DIR / "countries.json"
PROVINCES_JSON    = DATA_DIR / "provinces.json"
PROVINCE_ADJ_JSON = DATA_DIR / "province_adjacencies.json"
PROVINCES_PNG     = ASSETS_DIR / "provinces.png"

MAP_WIDTH  = 16384
MAP_HEIGHT = 8192

ADMIN0_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_0_countries.geojson"
)
ADMIN1_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_10m_admin_1_states_provinces.geojson"
)


# ── Projection ─────────────────────────────────────────────────────────────────

def lat_lon_to_pixel(lat: float, lon: float) -> tuple:
    x = (lon + 180.0) / 360.0 * MAP_WIDTH
    y = (90.0 - lat)  / 180.0 * MAP_HEIGHT
    return x, y


def project_ring(ring: list) -> list:
    return [lat_lon_to_pixel(pt[1], pt[0]) for pt in ring]


def extract_rings(geometry: dict) -> list:
    """Return outer rings of all polygons in a geometry."""
    rings = []
    gtype = geometry.get("type", "")
    coords = geometry.get("coordinates", [])
    if gtype == "Polygon":
        if coords:
            rings.append(project_ring(coords[0]))
    elif gtype == "MultiPolygon":
        for poly in coords:
            if poly:
                rings.append(project_ring(poly[0]))
    return rings


def polygon_centroid(ring: list) -> tuple:
    if not ring:
        return (MAP_WIDTH / 2, MAP_HEIGHT / 2)
    x = sum(pt[0] for pt in ring) / len(ring)
    y = sum(pt[1] for pt in ring) / len(ring)
    return x, y


def polygon_area(ring: list) -> float:
    """Shoelace formula — returns approximate screen area."""
    n = len(ring)
    if n < 3:
        return 0.0
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += ring[i][0] * ring[j][1]
        area -= ring[j][0] * ring[i][1]
    return abs(area) / 2.0


# ── Detect-color encoding ──────────────────────────────────────────────────────

def index_to_detect_color(idx: int) -> tuple:
    """1-based index → unique RGB tuple. Index 0 reserved for ocean (black)."""
    r = (idx >> 16) & 0xFF
    g = (idx >> 8)  & 0xFF
    b =  idx        & 0xFF
    return (r, g, b)


# ── Province ID generation ─────────────────────────────────────────────────────

def make_province_id(props: dict, parent_iso: str, fallback_idx: int) -> str:
    iso2 = (props.get("iso_3166_2") or "").strip()
    if iso2 and iso2 not in ("-99", "None") and len(iso2) >= 4:
        return iso2
    adm1 = (props.get("adm1_code") or "").strip()
    if adm1 and adm1 not in ("-99", "None") and len(adm1) >= 3:
        return adm1
    name_raw = (props.get("name") or "").strip().upper()[:8].replace(" ", "_")
    return f"{parent_iso}_{name_raw or str(fallback_idx)}"


# ── Download helper ────────────────────────────────────────────────────────────

def fetch_geojson(url: str, label: str) -> dict:
    print(f"  Downloading {label}...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode())
        print(f"    {len(data.get('features', []))} features.")
        return data
    except Exception as e:
        print(f"ERROR: Could not download {label}: {e}")
        sys.exit(1)


# ── Adjacency scan ─────────────────────────────────────────────────────────────

def build_adjacency(img: Image.Image, color_to_pid: dict) -> dict:
    """Scan image pixels to find province neighbours."""
    adj = defaultdict(set)
    print("  Scanning adjacency (this may take a moment)...")
    try:
        import numpy as np
        arr = np.array(img)

        def scan_direction(a, b):
            diff = np.any(a != b, axis=2)
            ys, xs = np.where(diff)
            for y, x in zip(ys.tolist(), xs.tolist()):
                c1 = tuple(int(v) for v in a[y, x])
                c2 = tuple(int(v) for v in b[y, x])
                id1 = color_to_pid.get(c1)
                id2 = color_to_pid.get(c2)
                if id1 and id2:
                    adj[id1].add(id2)
                    adj[id2].add(id1)

        scan_direction(arr[:, :-1], arr[:, 1:])   # horizontal
        scan_direction(arr[:-1, :], arr[1:, :])   # vertical
        print(f"    Found adjacency for {len(adj)} provinces (numpy).")
    except ImportError:
        print("    numpy not available — install it for adjacency: pip install numpy")
        print("    Skipping adjacency scan. Units will use country-level movement.")

    return {pid: sorted(list(nb)) for pid, nb in adj.items()}


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    print("=== War Strategy Game — Data Pipeline Step 2 (Provinces) ===\n")

    if not COUNTRIES_JSON.exists():
        print("ERROR: countries.json not found. Run fetch_country_data.py first.")
        sys.exit(1)

    with open(COUNTRIES_JSON, encoding="utf-8") as f:
        countries: list = json.load(f)
    iso_index = {c["iso"]: i for i, c in enumerate(countries)}
    # ISO-2 → ISO-3 fallback for Natural Earth features that lack adm0_a3
    iso3_from_iso2 = {c.get("iso2", ""): c["iso"] for c in countries if c.get("iso2", "")}
    # Natural Earth uses non-standard ISO codes for disputed/breakaway territories
    TERRITORY_REMAP = {
        "SOL": "SOM",  # Somaliland → Somalia
        "KOS": "XKX",  # Kosovo (if present)
        "CYN": "CYP",  # Northern Cyprus → Cyprus
        "KAB": "MAR",  # Kabylian → Morocco (if ever tagged)
        "SAH": "MAR",  # Western Sahara → Morocco (NE sometimes)
    }
    print(f"Loaded {len(countries)} countries.\n")

    # ── Download GeoJSON ───────────────────────────────────────────────────────
    admin0 = fetch_geojson(ADMIN0_URL, "ne_50m_admin_0_countries")
    admin1 = fetch_geojson(ADMIN1_URL, "ne_50m_admin_1_states_provinces")
    print()

    # ── Build country-polygon index (for fallback single-province countries) ───
    country_rings: dict = defaultdict(list)
    for feat in admin0["features"]:
        props = feat.get("properties", {})
        geo   = feat.get("geometry", {})
        iso3  = (props.get("ADM0_A3") or props.get("ISO_A3") or props.get("adm0_a3") or "").strip()
        if not iso3 or iso3 == "-99" or iso3 not in iso_index:
            continue
        for ring in extract_rings(geo):
            if len(ring) >= 3:
                country_rings[iso3].append((ring, polygon_area(ring)))
    # Sort each country's rings by area descending
    for iso3 in country_rings:
        country_rings[iso3].sort(key=lambda x: x[1], reverse=True)

    # Update country centroids from GeoJSON data
    for iso3, ring_list in country_rings.items():
        idx = iso_index.get(iso3)
        if idx is None:
            continue
        largest = ring_list[0][0]
        cx, cy  = polygon_centroid(largest)
        countries[idx]["centroid"] = [round(cx, 1), round(cy, 1)]
        countries[idx]["polygon"]  = [[round(p[0], 1), round(p[1], 1)] for p in largest]

    # ── Process admin-1 features ───────────────────────────────────────────────
    province_features: dict = defaultdict(list)
    for feat in admin1["features"]:
        props = feat.get("properties", {})
        geo   = feat.get("geometry", {})
        iso3  = (props.get("adm0_a3") or "").strip()
        iso3  = TERRITORY_REMAP.get(iso3, iso3)
        if not iso3 or iso3 not in iso_index:
            # Fallback: derive ISO-3 from ISO-2 country code
            iso2 = (props.get("iso_a2") or "").strip()
            iso3 = iso3_from_iso2.get(iso2, "")
        if not iso3 or iso3 not in iso_index:
            continue
        rings = extract_rings(geo)
        if not rings:
            continue
        best = max(rings, key=lambda r: polygon_area(r))
        if len(best) < 3:
            continue
        province_features[iso3].append({
            "props": props,
            "ring":  best,
            "area":  polygon_area(best),
        })

    for iso3 in province_features:
        province_features[iso3].sort(key=lambda x: x["area"], reverse=True)

    countries_with_admin1 = set(province_features.keys())
    print(f"Admin-1 data found for {len(countries_with_admin1)} countries.")

    # Log unmatched features so we know what's being dropped
    unmatched = 0
    for feat in admin1["features"]:
        props = feat.get("properties", {})
        iso3 = (props.get("adm0_a3") or "").strip()
        iso3 = TERRITORY_REMAP.get(iso3, iso3)
        if not iso3 or iso3 not in iso_index:
            iso2 = (props.get("iso_a2") or "").strip()
            iso3 = iso3_from_iso2.get(iso2, "")
        if not iso3 or iso3 not in iso_index:
            name = props.get("name", "?")
            a3 = props.get("adm0_a3", "?")
            a2 = props.get("iso_a2", "?")
            if unmatched < 20:
                print(f"  UNMATCHED: {name} -- adm0_a3={a3}, iso_a2={a2}")
            unmatched += 1
    if unmatched:
        print(f"  Total unmatched: {unmatched} admin-1 features (not in countries.json)")

    # ── Assign detect colors and build province list ───────────────────────────
    provinces: list = []
    color_to_pid: dict = {}
    used_ids:  set = set()
    province_idx = 1   # 0 = ocean (black)

    def add_province(pid: str, name: str, parent_iso: str, ring: list) -> None:
        nonlocal province_idx
        base_pid = pid
        suffix = 0
        while pid in used_ids:
            suffix += 1
            pid = f"{base_pid}_{suffix}"
        used_ids.add(pid)

        color = index_to_detect_color(province_idx)
        cx, cy = polygon_centroid(ring)
        provinces.append({
            "id":           pid,
            "name":         name,
            "parent_iso":   parent_iso,
            "polygon":      [[round(p[0], 1), round(p[1], 1)] for p in ring],
            "centroid":     [round(cx, 1), round(cy, 1)],
            "detect_color": list(color),
        })
        color_to_pid[color] = pid
        province_idx += 1

    # Add admin-1 provinces
    for iso3, feat_list in province_features.items():
        for i, feat in enumerate(feat_list):
            props = feat["props"]
            name  = (props.get("name") or props.get("NAME") or iso3).strip()
            pid   = make_province_id(props, iso3, i)
            add_province(pid, name, iso3, feat["ring"])

    # Fallback: single province per country with no admin-1 data
    for iso3, ring_list in country_rings.items():
        if iso3 in countries_with_admin1:
            continue
        largest = ring_list[0][0]
        idx = iso_index[iso3]
        name = countries[idx].get("name", iso3)
        add_province(f"{iso3}_0", name, iso3, largest)
        # Include significant islands
        for ring, area in ring_list[1:]:
            if area > 500 and len(ring) >= 10:   # rough area threshold
                add_province(f"{iso3}_I{province_idx}", name, iso3, ring)

    print(f"Total provinces:  {len(provinces)}")
    print(f"Building provinces.png ({MAP_WIDTH}×{MAP_HEIGHT})...")

    # ── Draw provinces.png with detect colors ──────────────────────────────────
    img = Image.new("RGB", (MAP_WIDTH, MAP_HEIGHT), (0, 0, 0))   # black = ocean
    draw = ImageDraw.Draw(img)

    for p in provinces:
        ring  = [tuple(pt) for pt in p["polygon"]]
        color = tuple(p["detect_color"])
        if len(ring) >= 3:
            draw.polygon(ring, fill=color, outline=color)
            # 1px outline expansion to close micro-gaps between adjacent provinces
            draw.line(ring + [ring[0]], fill=color, width=2)

    # ─�� Fill single-pixel gaps between provinces (vectorized) ────────────────
    try:
        import numpy as np
        from scipy.ndimage import maximum_filter
        print("  Filling border gaps...")
        arr = np.array(img)
        black = np.all(arr == 0, axis=2)
        # Dilate non-black by 1px — any black pixel that gets covered was a gap
        non_black = ~black
        dilated = maximum_filter(non_black, size=3)
        gaps = black & dilated
        gap_ys, gap_xs = np.where(gaps)
        filled = 0
        for y, x in zip(gap_ys.tolist(), gap_xs.tolist()):
            # Count non-black neighbors
            neighbors = []
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dy == 0 and dx == 0:
                        continue
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < arr.shape[0] and 0 <= nx < arr.shape[1]:
                        nc = tuple(arr[ny, nx].tolist())
                        if nc != (0, 0, 0):
                            neighbors.append(nc)
            if len(neighbors) >= 3:
                from collections import Counter
                arr[y, x] = Counter(neighbors).most_common(1)[0][0]
                filled += 1
        img = Image.fromarray(arr)
        print(f"  Filled {filled} gap pixels")
    except ImportError:
        print("  scipy not available — skipping gap fill (pip install scipy)")

    img.save(PROVINCES_PNG)
    print(f"  OK: Saved provinces.png")

    # ── Build province adjacency ───────────────────────────────────────────────
    province_adj = build_adjacency(img, color_to_pid)

    # ── Bake terrain type + coastal flag into each province ──────────────────
    terrain_path = ASSETS_DIR / "terrain_types.png"
    if terrain_path.exists():
        print("  Baking terrain classification into provinces...")
        terrain_img = Image.open(terrain_path)
        tw, th = terrain_img.size
        terrain_px = terrain_img.load()
        TERRAIN_CLASSES = {
            0: "ocean", 30: "plains", 60: "forest", 90: "desert",
            120: "mountain", 150: "tundra", 180: "jungle",
        }
        def classify_terrain(r_val):
            best, best_dist = "plains", 999
            for tv, name in TERRAIN_CLASSES.items():
                d = abs(r_val - tv)
                if d < best_dist:
                    best_dist = d
                    best = name
            return best

        for prov in provinces:
            cx, cy = int(prov["centroid"][0]), int(prov["centroid"][1])
            cx = max(0, min(cx, tw - 1))
            cy = max(0, min(cy, th - 1))
            px = terrain_px[cx, cy]
            r_val = px[0] if isinstance(px, tuple) else px
            terrain = classify_terrain(r_val)
            if terrain == "ocean":
                terrain = "plains"  # province on land, default to plains
            prov["terrain"] = terrain

        # Coastal detection: check if province has ocean neighbors in adjacency
        ocean_provinces = set()
        # A province is coastal if any of its adjacency neighbors is ocean
        # OR if its polygon is near the map edge / water
        for pid, neighbors in province_adj.items():
            pass  # We'll use a pixel-based approach instead

        # Pixel-based coastal detection: sample a few points around centroid
        prov_img_px = img.load()
        for prov in provinces:
            cx, cy = int(prov["centroid"][0]), int(prov["centroid"][1])
            is_coastal = False
            # Check pixels in a radius around centroid for ocean (black = 0,0,0)
            for dx in range(-30, 31, 10):
                for dy in range(-30, 31, 10):
                    px_x = max(0, min(cx + dx, MAP_WIDTH - 1))
                    px_y = max(0, min(cy + dy, MAP_HEIGHT - 1))
                    r, g, b = prov_img_px[px_x, px_y][:3]
                    if r == 0 and g == 0 and b == 0:
                        is_coastal = True
                        break
                if is_coastal:
                    break
            prov["coastal"] = is_coastal

        coastal_count = sum(1 for p in provinces if p.get("coastal", False))
        terrain_counts = {}
        for p in provinces:
            t = p.get("terrain", "plains")
            terrain_counts[t] = terrain_counts.get(t, 0) + 1
        print(f"  Terrain: {terrain_counts}")
        print(f"  Coastal provinces: {coastal_count}")
    else:
        print("  WARNING: terrain_types.png not found, skipping terrain bake")
        for prov in provinces:
            prov["terrain"] = "plains"
            prov["coastal"] = False

    # ── Write output files ─────────────────────────────────────────────────────
    with open(PROVINCES_JSON, "w", encoding="utf-8") as f:
        json.dump(provinces, f, indent=2, ensure_ascii=False)
    print(f"  OK: Wrote provinces.json  ({len(provinces)} provinces)")

    with open(PROVINCE_ADJ_JSON, "w", encoding="utf-8") as f:
        json.dump(province_adj, f, indent=2)
    print(f"  OK: Wrote province_adjacencies.json  ({len(province_adj)} entries)")

    with open(COUNTRIES_JSON, "w", encoding="utf-8") as f:
        json.dump(countries, f, indent=2, ensure_ascii=False)
    print(f"  OK: Updated countries.json")

    print("\nData pipeline complete!")
    print(f"Open Godot — the map will now show {len(provinces)} individual provinces.")
    print("Tip: install numpy for province-level movement adjacency:")
    print("     pip install numpy")


if __name__ == "__main__":
    main()
