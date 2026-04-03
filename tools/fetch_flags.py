#!/usr/bin/env python3
"""fetch_flags.py — Downloads circular 64×64 flag PNGs for all countries.
Source: flagcdn.com (free, no API key required).
Output: assets/flags/<ISO2>.png (e.g., assets/flags/US.png)
"""

import json, os, sys, time
from pathlib import Path
from io import BytesIO

try:
    import requests
    from PIL import Image, ImageDraw
except ImportError:
    print("Install dependencies: pip install requests Pillow")
    sys.exit(1)

COUNTRIES_JSON = Path(__file__).parent.parent / "data" / "countries.json"
FLAGS_DIR      = Path(__file__).parent.parent / "assets" / "flags"
FLAG_SIZE      = 64
# flagcdn serves w320 PNGs by ISO-2 lowercase
CDN_URL        = "https://flagcdn.com/w320/{iso2}.png"


def make_circular(img: Image.Image, size: int) -> Image.Image:
    """Crop image to a circle with transparency."""
    img = img.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    if not COUNTRIES_JSON.exists():
        print(f"Error: {COUNTRIES_JSON} not found. Run fetch_country_data.py first.")
        sys.exit(1)

    with open(COUNTRIES_JSON, encoding="utf-8") as f:
        countries = json.load(f)

    FLAGS_DIR.mkdir(parents=True, exist_ok=True)

    # Collect iso2 codes
    iso2_list = []
    for c in countries:
        iso2 = c.get("iso2", "")
        iso3 = c.get("iso", "")
        if iso2:
            iso2_list.append((iso2, iso3, c.get("name", "")))

    print(f"Downloading {len(iso2_list)} flags to {FLAGS_DIR}/")

    downloaded = 0
    skipped = 0
    failed = 0

    for iso2, iso3, name in iso2_list:
        out_path = FLAGS_DIR / f"{iso2}.png"

        # Skip if already downloaded
        if out_path.exists() and out_path.stat().st_size > 100:
            skipped += 1
            continue

        url = CDN_URL.format(iso2=iso2.lower())
        try:
            resp = requests.get(url, timeout=10)
            if resp.status_code != 200:
                print(f"  SKIP {iso2} ({name}): HTTP {resp.status_code}")
                failed += 1
                continue

            img = Image.open(BytesIO(resp.content)).convert("RGBA")
            circular = make_circular(img, FLAG_SIZE)
            circular.save(out_path, "PNG")
            downloaded += 1

            if downloaded % 20 == 0:
                print(f"  ... {downloaded} downloaded")

            # Be polite to the CDN
            time.sleep(0.05)

        except Exception as e:
            print(f"  FAIL {iso2} ({name}): {e}")
            failed += 1

    print(f"\nDone: {downloaded} downloaded, {skipped} cached, {failed} failed")
    print(f"Flags saved to: {FLAGS_DIR}/")


if __name__ == "__main__":
    main()
