"""
fetch_terrain.py
================
Full terrain pipeline for 16K map with biome classification.
Generates 10 texture files in assets/map/.

Requirements:
  pip install Pillow numpy
"""

import io
import sys
import zipfile
import urllib.request
from pathlib import Path

try:
    from PIL import Image, ImageFilter, ImageEnhance
    Image.MAX_IMAGE_PIXELS = 300_000_000  # Allow 10800x21600 rasters
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)

try:
    import numpy as np
except ImportError:
    print("ERROR: numpy not installed. Run: pip install numpy")
    sys.exit(1)

ASSETS_DIR = Path(__file__).parent.parent / "assets" / "map"
ASSETS_DIR.mkdir(parents=True, exist_ok=True)

TARGET_W = 16384
TARGET_H = 8192

T_OCEAN = 0
T_PLAINS = 30
T_FOREST = 60
T_DESERT = 90
T_MOUNTAIN = 120
T_TUNDRA = 150
T_JUNGLE = 210

TERRAIN_URLS = [
    ("https://naciscdn.org/naturalearth/10m/raster/NE1_HR_LC_SR_W_DR.zip",
     "NE1 High-Res with Rivers (~185MB)"),
    ("https://naciscdn.org/naturalearth/10m/raster/NE1_HR_LC_SR_W.zip",
     "NE1 High-Res without Rivers (~170MB)"),
    ("https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip",
     "NE1 50m fallback (~50MB)"),
]


def download_raster(url: str, label: str) -> Image.Image:
    print(f"  Downloading {label}...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        total = resp.headers.get("Content-Length")
        data = bytearray()
        downloaded = 0
        while True:
            chunk = resp.read(256 * 1024)
            if not chunk:
                break
            data.extend(chunk)
            downloaded += len(chunk)
            mb = downloaded / 1_000_000
            if total:
                print(f"\r  {mb:.1f} MB ({downloaded / int(total) * 100:.0f}%)", end="", flush=True)
            else:
                print(f"\r  {mb:.1f} MB", end="", flush=True)
        data = bytes(data)
    print(f"\n  Complete: {len(data) / 1_000_000:.1f} MB")
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for name in zf.namelist():
            if name.lower().endswith((".tif", ".tiff", ".png", ".jpg", ".jpeg")):
                print(f"  Extracting: {name}")
                return Image.open(io.BytesIO(zf.read(name))).convert("RGB")
    raise RuntimeError("No image found in ZIP")


def classify_terrain(terrain: Image.Image, heightmap_gray: Image.Image) -> Image.Image:
    print(f"  Classifying terrain types...")
    w, h = terrain.size
    t_arr = np.array(terrain, dtype=np.float32)
    h_arr = np.array(heightmap_gray, dtype=np.float32)
    r, g, b = t_arr[:,:,0], t_arr[:,:,1], t_arr[:,:,2]
    total = r + g + b + 1.0
    green_ratio = g / total
    blue_ratio = b / total
    ys = np.arange(h, dtype=np.float32)[:, None]
    lat_factor = np.abs(ys / h - 0.5) * 2.0
    lat_factor = np.broadcast_to(lat_factor, (h, w))

    terrain_type = np.full((h, w), T_PLAINS, dtype=np.uint8)
    ocean = (blue_ratio > 0.38) & (b > r + 15) & (b > g + 10) & (h_arr < 50)
    terrain_type[ocean] = T_OCEAN
    desert = (green_ratio < 0.34) & (r > 130) & (h_arr < 160) & (lat_factor < 0.55)
    terrain_type[desert] = T_DESERT
    forest = (green_ratio > 0.36) & (g > 90) & (h_arr > 20) & (h_arr < 190) & (lat_factor < 0.7)
    terrain_type[forest] = T_FOREST
    jungle = (green_ratio > 0.39) & (g > 120) & (h_arr < 120) & (lat_factor < 0.25)
    terrain_type[jungle] = T_JUNGLE
    mountain = h_arr > 185
    terrain_type[mountain] = T_MOUNTAIN
    tundra = (lat_factor > 0.6) & (h_arr > 30) & (h_arr < 200) & (green_ratio < 0.36)
    terrain_type[tundra] = T_TUNDRA
    terrain_type[ocean] = T_OCEAN

    out = np.zeros((h, w, 3), dtype=np.uint8)
    out[:,:,0] = terrain_type
    out[:,:,1] = np.clip(green_ratio * 400, 0, 255).astype(np.uint8)
    out[:,:,2] = np.clip(b * 0.7, 0, 255).astype(np.uint8)

    for name, val in [("plains", T_PLAINS), ("forest", T_FOREST), ("desert", T_DESERT),
                      ("mountain", T_MOUNTAIN), ("tundra", T_TUNDRA), ("jungle", T_JUNGLE)]:
        pct = np.sum(terrain_type == val) / (w * h) * 100
        print(f"    {name}: {pct:.1f}%")
    return Image.fromarray(out)


def generate_biome_details():
    print("  Generating biome detail textures...")
    biomes = {
        "plains":   {"base": (145, 165, 110), "scale": 4, "contrast": 0.25, "octaves": 4},
        "forest":   {"base": (55, 95, 45),    "scale": 6, "contrast": 0.45, "octaves": 5},
        "desert":   {"base": (195, 175, 130),  "scale": 3, "contrast": 0.18, "octaves": 3},
        "mountain": {"base": (125, 115, 105),  "scale": 5, "contrast": 0.50, "octaves": 5},
        "tundra":   {"base": (165, 172, 178),  "scale": 3, "contrast": 0.20, "octaves": 3},
        "jungle":   {"base": (35, 85, 30),     "scale": 8, "contrast": 0.50, "octaves": 5},
    }
    size = 256
    for bname, props in biomes.items():
        arr = np.zeros((size, size, 3), dtype=np.float64)
        for octave in range(props["octaves"]):
            freq = max(2, props["scale"] * (2 ** octave))
            rng = np.random.RandomState(abs(hash(bname)) % (2**31) + octave)
            noise = rng.rand(freq, freq, 3)
            for ch in range(3):
                small = Image.fromarray((noise[:,:,ch] * 255).astype(np.uint8), mode="L")
                big = small.resize((size, size), Image.Resampling.BICUBIC)
                arr[:,:,ch] += np.array(big, dtype=np.float64) / (255.0 * (1.4 ** octave))
        arr = arr / (arr.max() + 1e-6)
        base = np.array(props["base"], dtype=np.float64) / 255.0
        final = np.clip((base[None,None,:] + (arr - 0.5) * props["contrast"]) * 255, 0, 255)
        Image.fromarray(final.astype(np.uint8)).save(ASSETS_DIR / f"detail_{bname}.png", "PNG")
        print(f"    OK: detail_{bname}.png")


def generate_generic_detail(size: int = 512) -> Image.Image:
    arr = np.zeros((size, size), dtype=np.float64)
    for octave in range(5):
        freq = max(2, size // (2 ** (octave + 1)))
        noise = np.random.RandomState(42 + octave).rand(freq, freq)
        small = Image.fromarray((noise * 255).astype(np.uint8), mode="L")
        big = small.resize((size, size), Image.Resampling.BICUBIC)
        arr += np.array(big, dtype=np.float64) / (1.5 ** octave)
    return Image.fromarray((arr / arr.max() * 255).astype(np.uint8), mode="L")


def generate_noise(size: int = 256) -> Image.Image:
    arr = np.zeros((size, size, 3), dtype=np.float64)
    for octave in range(4):
        freq = max(2, size // (4 * (2 ** octave)))
        noise = np.random.RandomState(99 + octave).rand(freq, freq, 3)
        for ch in range(3):
            small = Image.fromarray((noise[:,:,ch] * 255).astype(np.uint8), mode="L")
            big = small.resize((size, size), Image.Resampling.BICUBIC)
            arr[:,:,ch] += np.array(big, dtype=np.float64) / (255.0 * (2 ** octave))
    return Image.fromarray((arr / arr.max() * 255).astype(np.uint8))


def main():
    print(f"=== Terrain Pipeline (16K + Biomes) ===\n")

    terrain = None
    cache_path = Path(__file__).parent / "terrain_source_hr.png"
    if cache_path.exists():
        print(f"Loading cached high-res source...")
        terrain = Image.open(cache_path).convert("RGB")
        if terrain.width < 8000:
            terrain = None

    if terrain is None:
        for url, label in TERRAIN_URLS:
            try:
                terrain = download_raster(url, label)
                terrain.save(cache_path, "PNG")
                break
            except Exception as e:
                print(f"  Failed: {e}")
                continue
    if terrain is None:
        print("ERROR: Could not download terrain.")
        sys.exit(1)

    print(f"Source: {terrain.width}x{terrain.height}")

    print(f"\nResizing to {TARGET_W}x{TARGET_H}...")
    terrain_16k = terrain.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
    terrain_16k = ImageEnhance.Contrast(terrain_16k).enhance(1.12)
    terrain_16k = ImageEnhance.Color(terrain_16k).enhance(1.08)
    terrain_16k.save(ASSETS_DIR / "terrain.png", "PNG", optimize=False)
    print(f"  OK: terrain.png ({(ASSETS_DIR / 'terrain.png').stat().st_size / 1e6:.1f} MB)")

    print("\nGenerating heightmap...")
    heightmap = terrain_16k.convert("L")
    h_arr = np.array(heightmap, dtype=np.float64)
    h_arr = (h_arr - h_arr.min()) / (h_arr.max() - h_arr.min() + 1e-6) * 255
    heightmap = Image.fromarray(h_arr.astype(np.uint8), mode="L")
    heightmap = heightmap.filter(ImageFilter.GaussianBlur(radius=1.5))
    heightmap.save(ASSETS_DIR / "heightmap.png", "PNG")
    print("  OK: heightmap.png")

    print("\nClassifying terrain types...")
    classify_terrain(terrain_16k, heightmap).save(ASSETS_DIR / "terrain_types.png", "PNG")
    print(f"  OK: terrain_types.png")

    print("\nBiome detail textures...")
    generate_biome_details()

    print("\nBuilding biome atlas (3x2 grid)...")
    biome_names = ["plains", "forest", "desert", "mountain", "tundra", "jungle"]
    atlas = Image.new("RGB", (768, 512))
    for i, bname in enumerate(biome_names):
        tile = Image.open(ASSETS_DIR / f"detail_{bname}.png").convert("RGB")
        atlas.paste(tile, ((i % 3) * 256, (i // 3) * 256))
    atlas.save(ASSETS_DIR / "biome_atlas.png", "PNG")
    print("  OK: biome_atlas.png")

    print("\nGeneric detail + noise...")
    generate_generic_detail(512).save(ASSETS_DIR / "detail.png", "PNG")
    generate_noise(256).save(ASSETS_DIR / "noise.png", "PNG")
    print("  OK")

    print(f"\nPipeline complete! {TARGET_W}x{TARGET_H} + 6 biome textures")


if __name__ == "__main__":
    main()
