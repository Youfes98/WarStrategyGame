"""
fetch_terrain.py
================
Downloads high-resolution Natural Earth terrain data and produces:

  assets/map/terrain.png    — colour terrain with rivers/drainage (16384x8192)
  assets/map/heightmap.png  — grayscale elevation for shader lighting (16384x8192)
  assets/map/detail.png     — tileable micro-detail texture (512x512)
  assets/map/noise.png      — tileable noise texture (256x256)

Uses NE1_HR_LC_SR_W_DR — Natural Earth's highest quality raster:
  - Hypsometric tints (natural terrain colors)
  - Shaded relief (3D-like mountain shadows)
  - Water bodies rendered
  - Rivers and drainage networks included
  - Native resolution: 10800x5400 (much sharper than the 50m version)

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
    from PIL import Image, ImageFilter, ImageEnhance
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

TERRAIN_URLS = [
    ("https://naciscdn.org/naturalearth/10m/raster/NE1_HR_LC_SR_W_DR.zip",
     "NE1 High-Res with Rivers (best quality, ~185MB)"),
    ("https://naciscdn.org/naturalearth/10m/raster/NE1_HR_LC_SR_W.zip",
     "NE1 High-Res without Rivers (~170MB)"),
    ("https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip",
     "NE1 50m fallback (lower quality, ~50MB)"),
]


def download_raster(url: str, label: str) -> Image.Image:
    print(f"  Downloading {label}...")
    print(f"  URL: {url}")
    print(f"  This may take several minutes for high-res data.")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        total = resp.headers.get("Content-Length")
        data = bytearray()
        downloaded = 0
        block_size = 1024 * 256
        while True:
            chunk = resp.read(block_size)
            if not chunk:
                break
            data.extend(chunk)
            downloaded += len(chunk)
            mb = downloaded / 1_000_000
            if total:
                pct = downloaded / int(total) * 100
                print(f"\r  Downloaded {mb:.1f} MB ({pct:.0f}%)", end="", flush=True)
            else:
                print(f"\r  Downloaded {mb:.1f} MB", end="", flush=True)
        data = bytes(data)
    print(f"\n  Download complete: {len(data) / 1_000_000:.1f} MB")

    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for name in zf.namelist():
            low = name.lower()
            if low.endswith((".tif", ".tiff", ".png", ".jpg", ".jpeg")):
                print(f"  Extracting: {name}")
                img_data = zf.read(name)
                return Image.open(io.BytesIO(img_data)).convert("RGB")
    raise RuntimeError("No image found in ZIP")


def generate_detail_texture(size: int = 512) -> Image.Image:
    """Tileable micro-detail — adds paper/terrain grain at high zoom."""
    arr = np.zeros((size, size), dtype=np.float64)
    for octave in range(5):
        freq = max(2, size // (2 ** (octave + 1)))
        noise = np.random.RandomState(42 + octave).rand(freq, freq)
        small = Image.fromarray((noise * 255).astype(np.uint8), mode="L")
        big = small.resize((size, size), Image.Resampling.BICUBIC)
        weight = 1.0 / (1.5 ** octave)
        arr += np.array(big, dtype=np.float64) * weight
    arr = (arr / arr.max() * 255.0)
    return Image.fromarray(arr.astype(np.uint8), mode="L")


def generate_noise(size: int = 256) -> Image.Image:
    """Tileable noise texture."""
    arr = np.zeros((size, size, 3), dtype=np.float64)
    for octave in range(4):
        freq = max(2, size // (4 * (2 ** octave)))
        noise = np.random.RandomState(99 + octave).rand(freq, freq, 3)
        for ch in range(3):
            small = Image.fromarray((noise[:, :, ch] * 255).astype(np.uint8), mode="L")
            big = small.resize((size, size), Image.Resampling.BICUBIC)
            arr[:, :, ch] += np.array(big, dtype=np.float64) / (255.0 * (2 ** octave))
    arr = arr / arr.max() * 255.0
    return Image.fromarray(arr.astype(np.uint8))


def process_terrain(terrain: Image.Image) -> tuple:
    """Process raw terrain into game-ready textures."""
    print(f"  Source resolution: {terrain.width}x{terrain.height}")
    print(f"  Target resolution: {TARGET_W}x{TARGET_H}")

    print(f"  Resizing terrain to {TARGET_W}x{TARGET_H} (LANCZOS)...")
    terrain_16k = terrain.resize((TARGET_W, TARGET_H), Image.Resampling.LANCZOS)

    print(f"  Enhancing terrain colors...")
    terrain_16k = ImageEnhance.Contrast(terrain_16k).enhance(1.15)
    terrain_16k = ImageEnhance.Color(terrain_16k).enhance(1.1)

    print(f"  Generating heightmap...")
    heightmap = terrain_16k.convert("L")
    h_arr = np.array(heightmap, dtype=np.float64)
    h_min, h_max = h_arr.min(), h_arr.max()
    if h_max > h_min:
        h_arr = (h_arr - h_min) / (h_max - h_min) * 255.0
    heightmap = Image.fromarray(h_arr.astype(np.uint8), mode="L")
    heightmap = heightmap.filter(ImageFilter.GaussianBlur(radius=1.5))

    return terrain_16k, heightmap


def main():
    print(f"=== War Strategy Game -- Terrain Pipeline (16K) ===\n")

    terrain_path   = ASSETS_DIR / "terrain.png"
    heightmap_path = ASSETS_DIR / "heightmap.png"
    detail_path    = ASSETS_DIR / "detail.png"
    noise_path     = ASSETS_DIR / "noise.png"

    # Check for cached high-res source
    terrain = None
    cache_path = Path(__file__).parent / "terrain_source.png"
    if cache_path.exists():
        print(f"Loading cached terrain source from {cache_path}")
        terrain = Image.open(cache_path).convert("RGB")
        if terrain.width < 10000:
            print(f"  Cached source is low-res ({terrain.width}x{terrain.height}), re-downloading...")
            terrain = None

    if terrain is None:
        for url, label in TERRAIN_URLS:
            try:
                terrain = download_raster(url, label)
                print(f"  Caching source to {cache_path} for future runs...")
                terrain.save(cache_path, "PNG")
                break
            except Exception as e:
                print(f"  Failed: {e}")
                print(f"  Trying next source...")
                continue

    if terrain is None:
        print("\nERROR: Could not download any terrain source.")
        sys.exit(1)

    # Process
    terrain_16k, heightmap = process_terrain(terrain)

    print(f"  Saving terrain.png...")
    terrain_16k.save(terrain_path, "PNG", optimize=False)
    size_mb = terrain_path.stat().st_size / 1_000_000
    print(f"  OK: terrain.png ({size_mb:.1f} MB)")

    print(f"  Saving heightmap.png...")
    heightmap.save(heightmap_path, "PNG", optimize=False)
    print(f"  OK: heightmap.png")

    print(f"  Generating detail texture (512x512)...")
    generate_detail_texture(512).save(detail_path, "PNG")
    print(f"  OK: detail.png")

    print(f"  Generating noise texture (256x256)...")
    generate_noise(256).save(noise_path, "PNG")
    print(f"  OK: noise.png")

    print(f"\nTerrain pipeline complete!")
    print(f"  Resolution: {TARGET_W}x{TARGET_H}")
    print(f"  Source: {terrain.width}x{terrain.height} (upscale ratio: {TARGET_W/terrain.width:.1f}x)")


if __name__ == "__main__":
    main()
