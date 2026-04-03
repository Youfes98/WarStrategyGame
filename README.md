# War Strategy Game

A real-time grand strategy game set in **modern 2026**, built with **Godot 4.6** (GDScript). Real world map with 4584 sub-national provinces, GPU shader rendering, and AI-driven geopolitics.

Inspired by Victoria 3, Hearts of Iron 4, and Age of History 3.

## Screenshots

*Coming soon — game is in active development.*

## Features

**Map**
- 8192x4096 world map with 4584 real provinces (Natural Earth admin-1 data)
- GPU shader rendering: terrain base + country color overlay + elevation shading + coast glow + noise variation + province/country borders
- Endless horizontal scrolling (3-tile wrapping)
- O(1) pixel-color click detection
- Zoom-responsive labels with overlap rejection

**Gameplay**
- 250 real countries with GDP, population, military, stability, government type
- Province-level territory control and conquest
- Independent army system (multiple armies per country, move independently)
- AI system: 194 countries make monthly decisions (build military, invest infrastructure, diplomacy, trade, declare war)
- War declaration and peace treaties
- Neutral territory movement blocking

**Infrastructure**
- F5 quicksave / F9 quickload (JSON serialization)
- Multi-rate tick system (hour/day/week/month/year signals)
- 5 game speed levels with pause
- Event-driven architecture via signals

## Setup

### Requirements

- [Godot 4.6](https://godotengine.org/download/) (GL Compatibility renderer)
- Python 3.10+ with packages:

```bash
pip install Pillow numpy requests
```

### First-Time Setup

Clone the repo and generate the game data:

```bash
git clone https://github.com/Youfes98/WarStrategyGame.git
cd WarStrategyGame/tools

# Step 1: Download country data from REST Countries API
python fetch_country_data.py

# Step 2: Generate provinces.png + provinces.json from Natural Earth GeoJSON
python geojson_to_godot.py

# Step 3 (optional but recommended): Download terrain textures
python fetch_terrain.py
```

Then open the project in Godot 4.6 and run.

### What the Pipeline Generates

| Script | Output | Size |
|--------|--------|------|
| `fetch_country_data.py` | `data/countries.json`, `data/adjacencies.json` | ~1 MB |
| `geojson_to_godot.py` | `data/provinces.json`, `data/province_adjacencies.json`, `assets/map/provinces.png` | ~15 MB |
| `fetch_terrain.py` | `assets/map/terrain.png`, `assets/map/heightmap.png`, `assets/map/noise.png` | ~50 MB |

These files are gitignored because they're large and fully reproducible from the pipeline.

## Project Structure

```
WarStrategyGame/
  assets/
    icons/          App icon
    map/            provinces.png, terrain.png, heightmap.png, noise.png (generated)
    shaders/        map.gdshader (GPU layered map renderer)
  data/             countries.json, provinces.json, adjacencies (generated)
  scenes/           Godot scene files (.tscn)
  scripts/
    autoloads/      GameClock, GameState, UIManager, ProvinceDB, SaveSystem, WorldMemoryDB
    map/            MapRenderer, MapCamera, LabelLayer, BorderLayer, UnitLayer
    systems/        MilitarySystem, AISystem, EconomySystem
    ui/             CountryCard, CountryPicker, MilitaryPanel, NotificationFeed, etc.
  tools/            Python data pipeline scripts
```

## Architecture

**Autoloads** (singletons loaded before any scene):
- `GameClock` — tick system with hour/day/week/month/year signals
- `GameState` — single source of truth for all game data
- `ProvinceDB` — map data, click detection, province/country lookups
- `MilitarySystem` — units, armies, movement, combat
- `AISystem` — monthly AI decision loop for all non-player countries
- `UIManager` — panel states, notifications
- `SaveSystem` — F5/F9 quicksave/quickload
- `WorldMemoryDB` — event memory system (planned)

**Map Rendering**: A single GPU shader (`map.gdshader`) reads `provinces.png` (detect-color encoded) and maps each pixel to a display color via a 1D lookup texture (LUT). Terrain, elevation, coast glow, noise, and borders are all computed in the shader. Color changes (selection, war, conquest) update one pixel in the LUT — no polygon nodes needed.

## Controls

| Key | Action |
|-----|--------|
| Space | Pause / unpause |
| 1-5 | Game speed |
| W/A/S/D | Pan map |
| Scroll wheel | Zoom in/out |
| Right-click drag | Pan map |
| Left-click | Select country / move army |
| Escape | Deselect |
| F5 | Quicksave |
| F9 | Quickload |

## Roadmap

**MVP v1 (Current)**: Map + basic economy + diplomacy + one military unit type (auto-resolve combat). Focus on the economic leverage gameplay loop.

**MVP v2**: Commander system, proper combat, governance, elections.

**Full Release**: Gray zone conflict, narrative warfare, world memory, black swan events, technology R&D.

## License

All rights reserved. This is a proprietary project in active development.

## Built With

- [Godot 4.6](https://godotengine.org/) — game engine
- [Natural Earth](https://www.naturalearthdata.com/) — map data and terrain textures
- [REST Countries API](https://restcountries.com/) — country metadata
- [Claude Code](https://claude.ai/claude-code) — AI pair programming
