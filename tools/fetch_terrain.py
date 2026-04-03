"""
fetch_terrain.py
================
Step 3 of the data pipeline (optional but recommended for visual quality).
Downloads Natural Earth raster terrain data and produces:

  assets/map/terrain.png    — colour terrain base layer (8192×4096)
  assets/map/heightmap.png  — grayscale elevation for lighting (8192×4096)
  assets/map/noise.png      — small tileable noise texture (256×256)

Requirements:
  pip install Pillow numpy

Usage:
  python fetch_terrain.py
"""

import io
import sys
import zipfile
import urllib.request
from pathlib import Path

try:
    from PIL import Image, ImageFilter
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

TARGET_W = 8192
TARGET_H = 4096

# Natural Earth 1 with Shaded Relief, Water, and Drainages
# Beautiful stylized terrain — perfect for strategy games
TERRAIN_URL = "https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip"
TERRAIN_URL_ALT = "https://naciscdn.org/naturalearth/50m/raster/HYP_50M_SR_W.zip"


def download_raster(url: str, label: str) -> Image.Image:
    print(f"  Downloading {label}...")
    print(f"  URL: {url[:80]}...")
    print(f"  (This may take a few minutes — ~50MB)")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = resp.read()
    print(f"  Downloaded {len(data) / 1_000_000:.1f} MB")

    # Extract the image from the ZIP
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for name in zf.namelist():
            low = name.lower()
            if low.endswith((".tif", ".tiff", ".png", ".jpg", ".jpeg")):
                print(f"  Extracting: {name}")
                img_data = zf.read(name)
                return Image.open(io.BytesIO(img_data)).convert("RGB")
    raise RuntimeError("No image found in ZIP")


def generate_noise(size: int = 256) -> Image.Image:
    """Generate a tileable noise texture using octave noise."""
    arr = np.zeros((size, size, 3), dtype=np.float64)
    for octave in range(4):
        scale = 2 ** octave
        freq = size // (4 * scale)
        if freq < 2:
            freq = 2
        noise = np.random.rand(freq, freq, 3)
        # Upscale with smooth interpolation
        from PIL import Image as PILImage
        for ch in range(3):
            small = PILImage.fromarray((noise[:, :, ch] * 255).astype(np.uint8), mode="L")
            big = small.resize((size, size), PILImage.Resampling.BICUBIC)
            arr[:, :, ch] += np.array(big, dtype=np.float64) / (255.0 * (2 ** octave))

    # Normalize to 0-255
    arr = arr / arr.max() * 255.0
    return Image.fromarray(arr.astype(np.uint8))


def main():
    print("=== War Strategy Game — Terrain Data Pipeline ===\n")

    terrain_path   = ASSETS_DIR / "terrain.png"
    heightmap_path = ASSETS_DIR / "heightmap.png"
    noise_path     = ASSETS_DIR / "noise.png"

    # ── Download terrain raster ───────────────────────────────────────────────
    if terrain_path.exists():
        print(f"terrain.png already exists — loading from disk.")
        terrain = Image.open(terrain_path).convert("RGB")
    else:
        try:
            terrain = download_raster(TERRAIN_URL, "Natural Earth 1 terrain")
        except Exception as e:
            print(f"  Primary download failed ({e}), trying alternate...")
            terrain = download_raster(TERRAIN_URL_ALT, "Hypsometric terrain")

    # ── Resize to target ──────────────────────────────────────────────────────
    print(f"  Resizing terrain to {TARGET_W}x{TARGET_H}...")
    terrain = terrain.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)
    terrain.save(terrain_path, "PNG", optimize=True)
    print(f"  OK: Saved terrain.png ({terrain_path.stat().st_size / 1_000_000:.1f} MB)")

    # ── Generate heightmap from terrain ───────────────────────────────────────
    print(f"  Generating heightmap...")
    heightmap = terrain.convert("L")  # Grayscale
    # Enhance contrast for better shading
    arr = np.array(heightmap, dtype=np.float64)
    arr = (arr - arr.min()) / (arr.max() - arr.min() + 1e-6) * 255.0
    heightmap = Image.fromarray(arr.astype(np.uint8), mode="L")
    heightmap = heightmap.filter(ImageFilter.GaussianBlur(radius=2))
    heightmap.save(heightmap_path, "PNG")
    print(f"  OK: Saved heightmap.png")

    # ── Generate noise texture ────────────────────────────────────────────────
    print(f"  Generating noise texture (256x256)...")
    noise = generate_noise(256)
    noise.save(noise_path, "PNG")
    print(f"  OK: Saved noise.png")

    print(f"\nTerrain pipeline complete!")
    print(f"Files saved to: {ASSETS_DIR}")
    print(f"\nNext: re-run geojson_to_godot.py to regenerate provinces at {TARGET_W}x{TARGET_H}")


if __name__ == "__main__":
    main()
