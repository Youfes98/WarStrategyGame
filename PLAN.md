# War Strategy Game — Implementation Plan
**Engine:** Godot 4.4+  
**Language:** GDScript (90%) + GDExtension/C++ hooks (heavy systems, later)  
**Genre:** Real-time Grand Strategy (HoI4 + Victoria 3 + Call of War + Age of History 3)  
**Setting:** Modern 2026 — Real world map, current geopolitics  
**Target:** Steam via GodotSteam GDExtension  

---

### Architecture: GDScript-First, C++ Boundary Later

Write everything in GDScript. Design heavy systems behind clean interfaces so they can be dropped into C++ GDExtension later without touching game logic.

```
┌─────────────────────────────────────────┐
│           Game Logic (GDScript)         │
│  GameClock · GameState · UIManager      │
│  EconomySystem · DiplomacySystem        │
│  ResearchSystem · ElectionSystem        │
└──────────────┬──────────────────────────┘
               │  clean interface boundary
               ▼
┌─────────────────────────────────────────┐
│     Heavy Systems (GDScript now,        │
│     GDExtension/C++ if needed later)    │
│                                         │
│  PathfindingEngine   ← army movement    │
│  CombatResolver      ← battle calc      │
│  AdjacencyGraph      ← map topology     │
│  AIDecisionEngine    ← country AI       │
│  MapRenderer         ← province bitmap  │
└─────────────────────────────────────────┘
```

**Rules for the boundary:**
- Heavy systems expose a simple GDScript-callable API: `Pathfinding.find_path(from, to)`, `Combat.resolve(a, b)` 
- No game state lives inside heavy systems — they are pure functions / stateless processors
- When a system becomes a performance bottleneck (profile first), swap the internals for C++ without changing callers

**When to consider GDExtension:**
- Pathfinding across 5,000+ province adjacency graph with 50+ simultaneous armies
- Combat resolution running 100+ simultaneous battles per tick
- AI decision engine evaluating 195 countries per tick at Speed 5
- Map pixel-lookup at very high zoom/detail level

Everything else stays GDScript forever — it's fast enough and far easier to iterate on.

---

## Core Design Pillars

### Freedom of Play
War is **one option among many**, not the default. Players can win — or simply thrive — through:

| Path | How |
|------|-----|
| **Military** | Conquest, occupation, arms deals, nuclear deterrence |
| **Economic** | Loans, debt leverage, owning foreign infrastructure, trade dominance |
| **Soft Power** | Cultural influence, media, foreign aid, education investment |
| **Diplomatic** | Alliances, puppets, UN voting blocs, embargo coalitions |
| **Development** | Industrialize, grow GDP, become a regional hub |

### Country Power Tiers & Difficulty
Starting difficulty scales to real-world country power. Tier affects: starting GDP, military, stability, international relations.

| Tier | Examples | Starting State |
|------|----------|---------------|
| **S — Superpower** | USA, China | Massive economy, global reach, everyone watches you |
| **A — Great Power** | Russia, EU nations, UK, India, Japan | Strong regional influence, medium-large economy |
| **B — Regional Power** | Brazil, Turkey, Saudi Arabia, Nigeria | Dominant in their region, limited global reach |
| **C — Minor Nation** | Hungary, Vietnam, Ecuador | Functional state, limited influence |
| **D — Weak State** | Libya, Haiti, Myanmar | Instability, poverty, civil war risk, hard mode |

Dynamic difficulty: as a weak nation grows powerful, great powers start applying **pressure** (sanctions, proxy wars, coups). As a superpower, you manage **overextension**, debt, and domestic unrest.

### No Forced Victory Condition
Players set their own goals. Optional objectives:
- Dominate X region economically
- Become top GDP nation
- Form a customs union / political union
- Nuclear deterrence — be feared but never attacked
- Peacefully unite a continent through diplomacy
- Classic: conquer the world

---

## Foundational Systems Design

---

### 1. Data Normalization

Real-world data is used as a **baseline only**, then normalized for gameplay. Raw numbers are never shown directly in game systems — only in flavor text ("World's 3rd largest economy").

#### GDP Normalization
```python
import math

def normalize_gdp(gdp_usd_billions: float) -> float:
    # Real range: $0.05B (Tuvalu) → $28,000B (USA)
    # Log-compress, then scale to 0–1000
    log_val = math.log10(max(gdp_usd_billions, 0.1))   # log10: 0.05B→-1.3, 28000B→4.4
    normalized = (log_val + 1.3) / (4.4 + 1.3) * 1000  # maps to 0–1000
    return round(clamp(normalized, 1, 1000))

# Results:
# USA       $28,000B → ~1000
# Germany   $4,400B  → ~880
# Brazil    $2,100B  → ~830
# Nigeria   $500B    → ~740
# Somalia   $8B      → ~490
# Tuvalu    $0.05B   → ~1
```

#### Other Normalized Scales
| Stat | Real Range | Game Range | Method |
|------|-----------|------------|--------|
| GDP | $0.05B–$28,000B | 1–1000 | Log10 scale |
| Population | 800 – 1,400,000,000 | 1–1000 | Log10 scale |
| Military Power | GFP index 0.001–5.0 | 1–1000 | Inverse log (lower = stronger in GFP) |
| Stability | 0–100% | 0–100 | Linear (already normalized) |
| Territory | 2 km² – 17M km² | 1–1000 | Log10 scale |
| Infrastructure | HDI proxy 0.3–0.95 | 0–100 | Linear clamp |
| Literacy | 25%–100% | 0–100 | Linear |
| Research Capacity | Derived | 0–100 | Derived from literacy × GDP × buildings |

**Key principle:** Players see **labels, not numbers** for most stats. Instead of "GDP: 847", they see "Strong Economy" or a bar. Raw numbers only visible in the detail panel for players who want them.

---

### 2. UI/UX — Progressive Disclosure

**The golden rule:** Never show a system before the player has a reason to care about it.

The game starts almost empty. Systems **surface themselves** when they become relevant.

#### Progression Gates

| In-game time / Trigger | What Unlocks |
|------------------------|-------------|
| **Game start** | Map only. Your country highlighted. Basic country card (name, flag, power tier). Pause/speed controls. |
| **First month passes** | Economy bar appears on country card. Simple GDP + stability indicators. |
| **First neighbor interaction** | Diplomacy panel unlocks. One action available: "View Relations". |
| **Build first building** | Construction queue appears. Only shows relevant building categories. |
| **Research building built** | Research panel appears for the first time. |
| **First election cycle approaches** | Election notification + governance panel unlocks. |
| **War declared (by anyone)** | Military command panel fully expands. Commander system explained. |
| **First espionage event fires** | Intelligence panel unlocks. |
| **Resource discovered / acquired** | Resource layer on map activates. |
| **Tech breakthrough** | Full research panel revealed. |
| **Year 2 of gameplay** | All systems fully visible. Player has been onboarded naturally. |

#### Panel Visibility States
Each panel has three states:
- **Hidden** — doesn't exist in the UI yet
- **Minimal** — small indicator or single button, no detail
- **Full** — complete panel with all options

```gdscript
enum PanelState { HIDDEN, MINIMAL, FULL }

class UIManager extends Node:
    var panel_states: Dictionary = {
        "economy":    PanelState.HIDDEN,
        "diplomacy":  PanelState.HIDDEN,
        "research":   PanelState.HIDDEN,
        "military":   PanelState.HIDDEN,
        "governance": PanelState.HIDDEN,
        "cabinet":    PanelState.HIDDEN,
        "intel":      PanelState.HIDDEN,
    }

    func unlock_panel(panel: String, state: PanelState = PanelState.MINIMAL):
        if panel_states[panel] < state:
            panel_states[panel] = state
            _animate_panel_in(panel)
            _show_tooltip_hint(panel)  # brief "New: Economy panel unlocked" toast
```

#### Always-Visible (from day 1)
- Map
- Country card (flag, name, power tier, 3 status bars: economy / stability / military)
- Pause + speed controls
- Date display
- Notification feed (right side, dismissable)

#### Notification Feed Design
Notifications are the game's primary teacher. They surface problems and opportunities without forcing the player into panels:
> *"Your oil reserves in the Gulf are untapped. Build a refinery to begin extraction."*  
> *"Germany has requested a trade deal. [View] [Dismiss]"*  
> *"Stability dropping in the north — consider raising social spending. [View] [Dismiss]"*

Player clicks [View] → relevant panel opens for the first time. This is the unlock moment.

---

### 3. Tick System

The simulation runs on a **multi-rate tick architecture**. Different systems update at different intervals. All driven by `GameClock.gd` which emits typed signals.

```
Real time → GameClock → scaled by speed_multiplier
                      → emits signals at simulation intervals
```

#### Tick Rates

| Signal | Simulation Interval | Real time @ Speed 1 | Systems That Subscribe |
|--------|-------------------|---------------------|----------------------|
| `tick_hour` | 1 in-game hour | ~0.04s | Army movement, combat resolution, air patrols |
| `tick_day` | 1 in-game day | ~1.0s | Unit supply/attrition, espionage progress, construction progress |
| `tick_week` | 7 in-game days | ~7.0s | Diplomatic relation drift, troop morale, resource extraction |
| `tick_month` | 30 in-game days | ~30.0s | GDP growth, research points, tax revenue, stability, population |
| `tick_year` | 365 in-game days | ~365.0s | Elections, tech diffusion, demographic shifts, debt interest |

#### GameClock Implementation
```gdscript
extends Node
# Autoload: GameClock

signal tick_hour(date: Dictionary)
signal tick_day(date: Dictionary)
signal tick_week(date: Dictionary)
signal tick_month(date: Dictionary)
signal tick_year(date: Dictionary)

const HOURS_PER_DAY    = 24
const DAYS_PER_MONTH   = 30
const MONTHS_PER_YEAR  = 12

# Speed: in-game hours per real second
const SPEED_TABLE = [0.0, 1.0, 3.0, 12.0, 48.0, 168.0]  # 0=paused, 1–5

var speed: int = 1
var paused: bool = false
var date = { "year": 2026, "month": 1, "day": 1, "hour": 0 }

var _hour_accum: float = 0.0

func _process(delta: float):
    if paused or speed == 0: return
    _hour_accum += delta * SPEED_TABLE[speed]
    while _hour_accum >= 1.0:
        _hour_accum -= 1.0
        _advance_hour()

func _advance_hour():
    emit_signal("tick_hour", date)
    date.hour += 1
    if date.hour >= HOURS_PER_DAY:
        date.hour = 0
        date.day += 1
        emit_signal("tick_day", date)
        if date.day % 7 == 0:
            emit_signal("tick_week", date)
        if date.day > DAYS_PER_MONTH:
            date.day = 1
            date.month += 1
            emit_signal("tick_month", date)
            if date.month > MONTHS_PER_YEAR:
                date.month = 1
                date.year += 1
                emit_signal("tick_year", date)
```

#### How Systems Subscribe
```gdscript
# EconomySystem.gd
func _ready():
    GameClock.tick_month.connect(_on_month)

func _on_month(date):
    for country in GameState.all_countries:
        _recalculate_gdp(country)
        _apply_tax_revenue(country)
        _update_stability(country)

# CombatSystem.gd
func _ready():
    GameClock.tick_hour.connect(_on_hour)

func _on_hour(date):
    for battle in active_battles:
        _resolve_combat_tick(battle)
```

#### Speed Reference Table (what "Speed 5" feels like)

| Speed | Multiplier | 1 month = | 1 year = | Feel |
|-------|-----------|-----------|----------|------|
| Paused | 0x | ∞ | ∞ | Planning mode |
| Speed 1 | 1x | ~30s | ~6 min | Slow, detailed |
| Speed 2 | 3x | ~10s | ~2 min | Normal |
| Speed 3 | 12x | ~2.5s | ~30s | Fast |
| Speed 4 | 48x | ~0.6s | ~7.5s | Very fast |
| Speed 5 | 168x | ~0.2s | ~2.2s | Blur (late game) |

Auto-pause triggers (always fire regardless of speed):
- War declared
- Election result
- Tech breakthrough
- Major stability event
- Commander requests reinforcements
- Foreign nation requests diplomatic action

---

## Phase 0: Documentation Discovery (COMPLETE)

### Allowed APIs (Verified)

| System | Node/API | Method |
|--------|----------|--------|
| Province rendering | `Polygon2D` | `set_polygon(PackedVector2Array)`, `color` property |
| Province clicking | `Image.get_pixelv(pos)` | Pixel-color → province ID lookup |
| Clickable fallback | `Area2D` + `CollisionPolygon2D` | `input_event` signal |
| Game clock | `_process(delta)` accumulator | `var scaled_delta = delta * speed` |
| Pause | `get_tree().paused = true/false` | Boolean property |
| Speed control | Custom multiplier (NOT `Engine.time_scale`) | `speed_multiplier: float` |
| Steam | `Steam.steamInitEx(APP_ID, true)` | GodotSteam GDExtension 4.18+ |

### Anti-Patterns to Avoid
- Do NOT use `Engine.time_scale` for game speed — causes particle stutter and doesn't affect `create_timer()`
- Do NOT use polygon containment tests for click detection — use pixel color lookup (O(1) vs O(n))
- Do NOT use `Timer` node for game ticks — `_process(delta)` accumulator is more scalable

### Data Sources (Verified)
- **Country polygons:** Natural Earth 1:10m GeoJSON — https://github.com/nvkelso/natural-earth-vector
- **Province system:** HoI4 standard — `provinces.bmp` + `definition.csv` + `adjacencies.csv`
- **Country data:** REST Countries API v3.1 — https://restcountries.com/
- **Coordinate projection:** Web Mercator (EPSG:3857) — manual GDScript implementation

---

## Phase 1: Project Setup & World Map

**Goal:** Godot 4 project running with a rendered, zoomable 2D world map showing countries as colored polygons.

### Tasks
1. Create Godot 4 project at `WarStrategyGame/`
2. Set up folder structure:
   ```
   res://
   ├── scenes/
   │   ├── Main.tscn
   │   ├── Map.tscn
   │   └── UI/
   ├── scripts/
   │   ├── GameClock.gd      # Autoload singleton
   │   ├── GameState.gd      # Autoload singleton
   │   ├── MapRenderer.gd
   │   └── ProvinceDB.gd
   ├── data/
   │   ├── countries.json    # From REST Countries API
   │   ├── provinces.json    # Parsed from Natural Earth GeoJSON
   │   └── adjacencies.json
   └── assets/
       └── map/
           └── provinces.png # Province color bitmap
   ```
3. Download Natural Earth 1:50m country GeoJSON
4. Write Python script (`tools/geojson_to_godot.py`) to convert GeoJSON → `provinces.json` with:
   - Country ISO code
   - Polygon vertices (Mercator projected, scaled to 4096×2048)
   - Centroid position
   - Color (unique per country, stored for pixel lookup)
5. Implement `MapRenderer.gd`:
   - Load `provinces.json`
   - Spawn one `Polygon2D` per country with its color
   - Apply Web Mercator projection formula
6. Implement camera pan (middle-mouse drag) and zoom (`scroll_wheel`) via `Camera2D`

### Verification
- [ ] Map renders ~195 countries as distinct colored polygons
- [ ] Camera pan and zoom work smoothly
- [ ] No console errors on scene load

### Key Code References
```gdscript
# Web Mercator projection (verified formula)
func lat_lon_to_pixel(lat: float, lon: float) -> Vector2:
    var lat_rad = deg_to_rad(lat)
    var x = (lon + 180.0) / 360.0 * MAP_WIDTH
    var y = (1.0 - log(tan(lat_rad) + 1.0 / cos(lat_rad)) / PI) / 2.0 * MAP_HEIGHT
    return Vector2(x, y)
```

---

## Phase 2: Province Clicking & Country Data

**Goal:** Click a country to select it. Show a side panel with country info.

### Tasks
1. Generate `provinces.png` — a bitmap where each pixel's RGB = unique country color
   - Use Python tool to rasterize polygons into bitmap
   - Size: 4096×2048 (manageable for `Image.get_pixelv()`)
2. Implement `ProvinceDB.gd` autoload:
   - Load color → country ISO lookup dictionary
   - Load `countries.json` (name, population, region, government, borders)
3. Implement click detection in `MapRenderer.gd`:
   ```gdscript
   func _unhandled_input(event):
       if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
           var map_pos = get_local_mouse_position()  # convert from screen via Camera2D
           var pixel = provinces_image.get_pixelv(Vector2i(map_pos))
           var country_iso = ProvinceDB.color_to_country(pixel)
           if country_iso != "":
               GameState.select_country(country_iso)
   ```
4. Build `CountryInfoPanel.tscn` — side panel showing:
   - Country name + flag emoji
   - Population, region
   - Government type (democracy / authoritarian / etc.)
   - Military strength (placeholder values)
5. Populate `countries.json` by fetching from REST Countries API (run once as a tool)

### Verification
- [ ] Clicking any country highlights it (change Polygon2D color)
- [ ] Side panel shows correct country name and data
- [ ] Clicking ocean / invalid area deselects

---

## Phase 3: Game Clock & Time Controls

**Goal:** Real-time simulation clock with pause and 5 speed levels. All future systems subscribe to this.

### Tasks
1. Implement `GameClock.gd` as an Autoload singleton:
   ```gdscript
   extends Node
   
   signal day_passed(date: Dictionary)
   signal hour_passed(date: Dictionary)
   
   const SPEEDS = [0.0, 1.0, 2.0, 5.0, 10.0, 30.0]  # seconds per in-game day
   var speed_index: int = 1
   var paused: bool = false
   var current_date = {"year": 2026, "month": 1, "day": 1, "hour": 0}
   var _accumulator: float = 0.0
   
   func _process(delta):
       if paused: return
       _accumulator += delta * SPEEDS[speed_index]
       while _accumulator >= 1.0:
           _accumulator -= 1.0
           _advance_hour()
   
   func _advance_hour():
       emit_signal("hour_passed", current_date)
       current_date.hour += 1
       if current_date.hour >= 24:
           current_date.hour = 0
           current_date.day += 1
           emit_signal("day_passed", current_date)
   ```
2. Build time controls UI bar (bottom of screen):
   - Pause button (spacebar shortcut)
   - Speed 1–5 buttons
   - Current date display (e.g. "Jan 1, 2026")
3. Connect UI to `GameClock` signals

### Verification
- [ ] Spacebar pauses/unpauses
- [ ] Speed buttons change tick rate visibly
- [ ] Date display advances in real time
- [ ] No ticks fire while paused

---

## Phase 4: Military Units & Map Movement

**Goal:** Place armies on the map. Select and order them to move to adjacent territories.

### Unit Types (2026 Modern Warfare)
| Unit | Icon | Movement | Combat Role |
|------|------|----------|-------------|
| Infantry | 🪖 | Land | Ground assault |
| Armor | 🛡 | Land (fast) | Breakthrough |
| Artillery | 💥 | Land (slow) | Siege support |
| Fighter Jet | ✈️ | Air (global range) | Air superiority |
| Bomber Drone | 🚁 | Air | Precision strike |
| Destroyer | ⚓ | Sea | Naval combat |
| Submarine | 🌊 | Sea (stealth) | Hidden warfare |
| Carrier | 🛳 | Sea | Mobile air base |
| ICBM | ☢️ | Strategic | Nuclear deterrent |

### Tasks
1. Implement `Unit.gd` resource:
   ```gdscript
   class_name Unit
   extends Resource
   var unit_type: String
   var owner_iso: String
   var location_country: String  # ISO code of current territory
   var movement_points: float
   var health: float = 100.0
   var strength: float  # combat value
   ```
2. Implement `UnitManager.gd` autoload — tracks all units, handles spawning
3. Add unit sprites at country centroids (simple colored icons for MVP)
4. Implement `AdjacencyGraph.gd` — loads `adjacencies.json` (borders array from REST Countries)
5. Implement movement orders:
   - Click unit → select it
   - Right-click target country → issue move order
   - Movement resolves over time via `GameClock.hour_passed`
6. Highlight valid move targets (adjacent countries) when unit is selected

### Verification
- [ ] Units appear on map at correct country positions
- [ ] Selecting a unit shows valid move targets highlighted
- [ ] Move orders execute over time (not instant)
- [ ] Units cannot move to non-adjacent territories

---

## Phase 5: Combat & Conquest

**Goal:** Armies fight when they meet enemy units. Winning army captures the territory.

### Tasks
1. Implement `CombatSystem.gd`:
   - Trigger when two enemy units occupy same territory
   - Combat resolution: `attacker_strength * random(0.8, 1.2)` vs `defender_strength * terrain_modifier`
   - Runs on `GameClock.hour_passed`
   - Losing unit retreats or is destroyed
2. Province capture: when defending army destroyed, territory switches owner
   - Update `Polygon2D.color` to new owner's color
   - Update `GameState.country_territories[iso]` array
3. War declaration system:
   - Countries start at peace
   - Player can declare war via country panel
   - AI declares war on neighbors (random for MVP)
4. Victory / elimination:
   - Country eliminated when all territories lost
   - Win condition: control X% of world (configurable)
5. Basic notifications: "War declared", "Territory captured", "Enemy eliminated"

### Verification
- [ ] Combat fires when enemy units meet
- [ ] Territory changes color on capture
- [ ] Eliminated countries no longer active
- [ ] Player can declare war via UI

---

## Phase 6: Economy & Development

**Goal:** Countries have real economies. Players can grow, industrialize, and dominate through wealth.

### Economic Model per Country
```gdscript
class_name CountryEconomy extends Resource
var gdp: float               # in billions USD (real 2026 values)
var gdp_growth: float        # % per year, affected by investment/stability
var debt: float              # total debt in billions
var debt_to_gdp: float       # computed ratio, affects credit rating
var credit_rating: int       # 0-100, affects loan interest rates
var infrastructure: float    # 0-100, affects growth multiplier
var industry_level: float    # 0-100, affects unit production speed
var stability: float         # 0-100, civil unrest risk below 30
var population: int
var literacy_rate: float     # affects tech research speed
```

### Tasks
1. Seed all ~195 countries with real 2026 GDP, population, debt data (from REST Countries + World Bank)
2. Implement `EconomySystem.gd` — ticks monthly via `GameClock`:
   - GDP grows based on: stability + infrastructure + trade partnerships + foreign investment
   - Instability events trigger below stability threshold (strikes, protests, coups)
3. **Development Actions** (player spends GDP):
   - Build Infrastructure (+growth, costs money, takes time)
   - Fund Education (+literacy, long-term tech benefit)
   - Industrialize (+military production, +GDP)
   - Bail out economy (emergency stability fix, adds debt)
4. **Debt system:**
   - Countries can take loans from others (bilateral) or "IMF" (internal game entity)
   - High debt-to-GDP triggers credit downgrade, higher interest, eventually default
   - Default = stability crash, foreign creditors get leverage
5. Country info panel expands to show economic dashboard

### Verification
- [ ] GDP grows/shrinks visibly over time
- [ ] Investing in infrastructure shows measurable growth boost
- [ ] High debt triggers negative events
- [ ] Economic data seeds correctly from real-world values

---

## Phase 7: Soft Power & Diplomacy

**Goal:** Influence other nations without firing a shot.

### Soft Power Mechanics
```gdscript
class_name Relation extends Resource
var country_a: String        # ISO code
var country_b: String        # ISO code
var diplomatic_score: int    # -100 (hostile) to +100 (ally)
var trade_volume: float      # annual trade in billions
var loans_owed: float        # country_b owes country_a
var infrastructure_owned: float  # % of country_b infra owned by country_a
var cultural_influence: float    # 0-100, affects their elections/stability
var military_access: bool    # military bases allowed
```

### Diplomatic Actions
| Action | Cost | Effect |
|--------|------|--------|
| Offer loan | GDP | +relations, other nation gains debt to you, you gain leverage |
| Invest in infrastructure | GDP | +their growth, +your influence, you own % of asset |
| Foreign aid | GDP | +relations, +stability in target, +your cultural influence |
| Sign trade deal | — | +trade volume, +both GDPs, +relations |
| Cultural exchange | GDP | +cultural influence, slowly shifts their political alignment |
| Offer military alliance | — | Mutual defense pact, shared wars |
| Offer non-aggression pact | — | Reduces war likelihood |
| Sanction | — | -their GDP, -relations, may trigger counter-sanctions |
| Embargo coalition | — | Convince allies to jointly sanction a target |
| Support opposition | Covert, costs money | Destabilize target, can trigger elections or coup |

### Leverage System
When you own infrastructure or hold loans in another country:
- You gain **leverage** score over them
- High leverage → unlock coercive actions: "Demand they vote with you", "Demand military access", "Demand trade concession"
- They can resist (costs them economically) or comply (costs them diplomatically with others)

### AI & Player Soft Power
1. AI nations pursue soft power based on their tier and personality type
2. Player sees a "Sphere of Influence" map layer showing who has leverage over whom
3. Relations panel shows all active agreements, debts, and influence scores

### Verification
- [ ] Loans flow between countries, debt tracked correctly
- [ ] High infrastructure ownership grants leverage actions
- [ ] Sanctions visibly reduce target GDP
- [ ] Sphere of influence map layer renders correctly

---

## Phase 7b: Technology — Organic R&D System

**Goal:** Technology is not a tree you click through. It emerges from what you build, who you educate, and what you fund — including programs nobody knows about.

### Design Philosophy
- No static tech tree with predetermined nodes
- **Research Capacity** is generated by real institutions you build and maintain
- **Breakthroughs** emerge stochastically when enough capacity accumulates in a domain
- **Secret Programs** exist in a hidden budget — other nations see your universities but not your Skunk Works

---

### Research Infrastructure (Buildable)

| Building | Domain | Effect |
|----------|--------|--------|
| University | Broad | +general research points, +literacy over time |
| Technical Institute | Applied | +engineering, +industry efficiency |
| Medical Research Center | Biotech/Social | +healthcare, +population growth |
| Military R&D Lab | Defense (public) | +conventional weapons, visible to others via intel |
| **Black Site / Skunk Works** | Defense (secret) | +classified research, hidden from other nations |
| Space Agency | Aerospace | +satellite tech, +ICBM accuracy, prestige |
| Cyber Command Center | Cyber | +offensive/defensive cyber capability |
| Energy Research Center | Energy | +efficiency, can unlock nuclear/fusion |
| Private Sector R&D Zone | Mixed | Invite corporations, faster civilian tech, less control |

Buildings take time to construct, cost upfront + ongoing funding. Defunding them causes brain drain.

---

### Research Points & Capacity

```gdscript
class_name ResearchSystem extends Resource

# Monthly research point generation per domain
var points: Dictionary = {
    "general":   0.0,  # from universities
    "military":  0.0,  # from mil labs (public)
    "secret":    0.0,  # from black sites — NOT visible to other nations
    "cyber":     0.0,
    "energy":    0.0,
    "aerospace": 0.0,
    "biotech":   0.0,
}

# Multipliers (all affect total points generated)
var literacy_multiplier: float      # 0.0–2.0, from education investment over years
var stability_multiplier: float     # < 0.5 stability = brain drain = reduced output
var funding_level: float            # budget allocation slider, 0.0–1.0
var brain_gain: float               # net scientist immigration bonus
```

**Research points accumulate** in each domain monthly. When a domain's accumulated points cross a **breakthrough threshold**, the game draws a technology from that domain's possibility pool — you never know exactly what emerges until it does. The threshold itself is randomized within a range, so timing is never predictable either.

---

### Breakthrough Draw System

```gdscript
class_name BreakthroughSystem

# When domain points cross threshold:
func _fire_breakthrough(country: Country, domain: String):
    var pool = TechDatabase.get_pool(domain)          # all techs in this domain
    var eligible = pool.filter(func(t): 
        return not country.has_tech(t.id)             # not already owned
        and _prerequisites_met(country, t)            # required prior techs exist
    )
    
    # Weight by: base_weight + (points_in_domain * domain_affinity) + luck_roll
    var weights = eligible.map(func(t):
        return t.base_weight 
            + (country.research.points[domain] * t.domain_affinity)
            + randf_range(0.0, t.luck_range)
    )
    
    var result = _weighted_random_pick(eligible, weights)
    country.grant_tech(result)
    _emit_breakthrough_event(country, result)
    
    # Reset domain points, randomize next threshold
    country.research.points[domain] = 0.0
    country.research.next_threshold[domain] = randf_range(
        TechDatabase.THRESHOLD_MIN[domain],
        TechDatabase.THRESHOLD_MAX[domain]
    )
```

**You invest in domains. The domain rewards you with something. You don't control what.**

The only exception: **Secret Programs** (see below) — where you explicitly target a technology by name, but at greater cost and with full secrecy risk.

---

### Technology Domains & Possibility Pools

Each domain has a pool of technologies. Higher investment shifts probability weights toward rarer/more powerful techs — but luck always plays a role.

| Domain | Common (high weight) | Uncommon | Rare |
|--------|---------------------|----------|------|
| **Military** | Smart Munitions, Active Defense | Advanced Armor, CIWS Upgrades | Directed Energy Weapons |
| **Aerospace** | Drone Swarms, ISTAR Satellites | GPS Jamming, Stealth UAVs | Anti-Satellite Weapons |
| **Cyber** | Firewall Systems, Signals Intelligence | Infrastructure Malware | AI-Driven Cyber Warfare |
| **Nuclear** | Reactor Efficiency, Radiation Hardening | Warhead Miniaturization | MIRV Technology |
| **Energy** | Grid Modernization, LNG Efficiency | Advanced Nuclear Reactors | Fusion Power (very rare) |
| **Biotech** | Disease Resistance, Crop Yields | Pandemic Preparedness | (secret only: bioweapons) |
| **General** | Logistics AI, Industrial Efficiency | Supply Chain Resilience | Economic Singularity Events |

**Rarity is not fixed** — a nation with enormous aerospace investment and high literacy has better odds at rare aerospace techs than a nation that just built one lab.

---

### Serendipity & Cross-Domain Discoveries

Occasionally, points in one domain trigger a breakthrough in an adjacent domain — modeling accidental discovery:
- High **Energy** research occasionally unlocks **Aerospace** (rocket propulsion serendipity)
- High **Cyber** research occasionally unlocks **Military** (autonomous weapons systems)
- High **General** research occasionally unlocks any domain (broad science spills over)

Probability of cross-domain: low (5–15%), increases with total national research capacity.

Breakthroughs are **events** — a notification fires with flavor text. Public techs are visible to rival intelligence services after a delay. Secret breakthroughs are invisible to everyone.

---

### Technology Domains & Example Breakthroughs

| Domain | Example Technologies Unlocked |
|--------|-------------------------------|
| **Military (public)** | Advanced Armor, Smart Munitions, Active Defense Systems |
| **Military (secret)** | Stealth Aircraft, Hypersonic Missiles, EMP Weapons, Tactical Nukes |
| **Cyber** | Cyber Espionage Tools, Infrastructure Attacks, AI-Aided Defense |
| **Aerospace** | Reconnaissance Satellites, GPS Jamming, Anti-Satellite Weapons |
| **Energy** | Nuclear Power (civilian), Fusion Research, Energy Independence |
| **Dual-Use** | Civilian nuclear → secretly accelerates nuclear weapon capability |
| **Biotech** | Disease resistance, Population growth bonus, (secret: bioweapons research) |
| **General** | Industrial Efficiency, Supply Chain Optimization, AI Governance |

Breakthroughs are **events** with flavor text. Secret breakthroughs only notify the player.

---

### Secret Research System

```gdscript
class_name SecretProgram extends Resource
var program_id: String            # e.g. "STEALTH_BOMBER", "NUCLEAR_WARHEAD_MK2"
var owner_iso: String
var domain: String                # which research domain feeds it
var progress: float               # 0.0 – 1.0
var discovered_by: Array[String]  # ISOs of nations that found out via espionage
var cover_story: String           # what it appears to be if partially detected
```

**How secrecy works:**
- Black Sites don't appear on public intel reports — other nations see "Unknown Facility"
- Espionage actions (Phase 8) can discover secret programs — partial intel gives cover story, full intel reveals true nature
- If discovered, rivals may issue warnings, sanctions, or preemptive strikes
- Completion triggers a **reveal event** — player chooses to announce publicly (deterrence) or keep hidden (surprise)

**Example secret programs:**
- Stealth Bomber Program → reveals new air unit type after completion
- Hypersonic Missile Program → unlocks long-range precision strike capability
- Nuclear Warhead Miniaturization → existing nukes become harder to intercept
- Cyber Warfare Division → unlocks offensive cyber actions against specific targets
- AI Combat Systems → passive combat bonus across all units

---

### Brain Drain & Brain Gain

- Scientists are a soft resource — they accumulate in educated, stable, well-funded nations
- **Brain Drain triggers:** low wages, instability > 70, active war, authoritarian crackdown
- **Brain Gain:** high literacy, high GDP per capita, research funding, peaceful reputation
- Diplomatic action: **Talent Visa Program** — actively poach scientists from other nations
- Espionage action: **Scientist Defection** — extract a key researcher, steal partial progress on their secret program

---

### Tech Diffusion (Global Spread)

Technologies don't stay exclusive forever:
- After a breakthrough, a **diffusion timer** starts (years, not days)
- When timer expires, tech becomes available to nations with sufficient general research capacity
- Nations can **license** technology to allies for income or diplomatic goodwill
- Nations can try to **block diffusion** through export controls and sanctions (reduces timer speed)

---

### Tasks for Implementation
1. `ResearchSystem.gd` — monthly tick, accumulate points per domain, apply multipliers
2. `BreakthroughSystem.gd` — check thresholds, fire breakthrough events with randomized timing
3. `SecretProgram.gd` — hidden programs, progress tracking, cover stories
4. `BuildingManager.gd` — construct/upgrade/defund research buildings, apply point bonuses
5. Research panel UI — shows domains with progress bars, lists discovered technologies, has a "Classified" section only the player sees
6. Brain drain/gain calculations in `EconomySystem.gd` monthly tick
7. Diffusion system — global tech spread timer per technology

### Verification
- [ ] Building a university visibly increases research point generation
- [ ] Breakthrough fires as a notification with correct tech name
- [ ] Secret program progress is invisible to other nations in intel reports
- [ ] Brain drain triggers when stability crashes
- [ ] Diffusion timer counts down and tech spreads to qualifying nations

---

## Phase 7c: Military Command — Commanders & AI Delegation

**Goal:** Players never have to manually move troops unless they want to. A command hierarchy of named characters executes your strategic intent.

---

### Command Hierarchy

```
Head of State (player)
        │
        ▼
Minister of Defense          ← strategic AI, you set objectives
        │
   ┌────┴────┐
   ▼         ▼
Theater    Theater           ← operational AI per front/region
Commander  Commander
   │
   ├── Army Commander A      ← tactical AI, controls individual armies
   └── Army Commander B
```

You can play at **any level** of this hierarchy:
- Full delegation: set objectives, watch it unfold, intervene only on major decisions
- Partial: control specific armies manually while delegating others
- Full control: ignore all AI suggestions, move every unit yourself

---

### Minister of Defense (MoD)

The MoD is a named character you appoint. You give him **Strategic Directives**:

| Directive | What MoD Does |
|-----------|--------------|
| **Defend Borders** | Fortifies frontiers, pulls back exposed units, requests more armor |
| **Secure [Region]** | Plans theater-level campaign to take/hold a region |
| **Project Power into [Country]** | Builds expeditionary force, plans logistics chain |
| **Naval Dominance — [Sea]** | Prioritizes naval buildup, establishes sea control |
| **Air Superiority — [Theater]** | Commits air assets, plans suppression of enemy air |
| **Ceasefire / Defensive Posture** | Halts all offensives, negotiates pauses |
| **Nuclear Readiness** | Raises alert level, positions deterrent assets |

MoD delivers **briefings** as in-game events:
> *"Minister Chen recommends advancing through the Zagros corridor before winter sets in. We estimate 60% success probability. Shall we proceed?"*

Player responds: **Approve / Modify / Reject**

```gdscript
class_name Minister extends Character
var title: String = "Minister of Defense"
var traits: Array[String]       # affects decisions and recommendations
var loyalty: float              # 0-100, drops if overridden constantly
var competence: float           # affects plan quality and outcome estimation
var hawkishness: float          # 0=dove, 1=hawk — shapes what they recommend
```

---

### Commander Traits

Commanders are named characters with trait combinations. Traits are **earned over time** — from battles, training, and education investments.

#### Personality Traits (affects decision-making)
| Trait | Behavior |
|-------|----------|
| **Aggressive** | Attacks at lower odds, pushes deep, higher casualties, faster advances |
| **Cautious** | Waits for 2:1 odds minimum, preserves manpower, slow but low loss |
| **Opportunist** | Exploits breakthroughs dynamically, reallocates forces mid-battle |
| **By-the-Book** | Follows doctrine strictly, predictable, reliable but not adaptive |
| **Defensive Specialist** | Excels in fortification and counter-attack, poor at offensive operations |
| **Gambler** | Makes high-risk high-reward decisions — great or catastrophic |

#### Skill Traits (affects specific operations)
| Trait | Effect |
|-------|--------|
| **Logistics Expert** | Reduces supply attrition by 30%, longer operational range |
| **Urban Warfare** | +25% effectiveness in city combat |
| **Combined Arms** | Coordinates infantry/armor/air as multiplier |
| **Naval Commander** | Unlocks advanced fleet formations and amphibious ops |
| **Cyber Integration** | Passively incorporates cyber ops into battle plans |
| **Air Power Advocate** | Prioritizes air cover, higher air support uptime |
| **Mountain Warfare** | Negates terrain penalty in highlands/mountains |
| **Intelligence Officer** | Better enemy estimation, reduced surprise events |

#### Background Traits (from character history)
| Trait | Origin | Effect |
|-------|--------|--------|
| **Battle-Hardened** | Survived multiple major engagements | +morale under pressure |
| **Political General** | Appointed for political reasons | -competence, +loyalty |
| **Foreign-Trained** | Educated abroad | +1 random foreign doctrine bonus |
| **Decorated Hero** | National military celebrity | +troop morale in their army |
| **Controversial** | Public scandal or past failure | -loyalty of troops, but may be brilliant |

---

### Commander AI Behavior Loop

Each commander runs a behavior loop on game tick:

```gdscript
func _on_tick(delta_days: float):
    var situation = _assess_situation()     # enemy strength, supply, terrain, weather
    var order = _get_current_order()        # from MoD or player
    var action = _decide_action(situation, order)   # trait-weighted decision
    _execute_action(action)
    _report_up(action)                      # brief MoD on what was done

func _decide_action(situation: Situation, order: Order) -> Action:
    # Aggressive trait: attack even at 1:1 odds
    # Cautious trait: request reinforcements if below 1.5:1
    # Opportunist: scan for exposed flanks, exploit if found
    # Gambler: random chance to attempt high-risk maneuver
    ...
```

Commanders can also **request things from MoD**:
- *"General Volkov requests 2 additional armored divisions for the push toward Kharkiv"*
- Player/MoD can approve, deny, or send partial support

---

### Trait Acquisition

Commanders don't start with all traits — they earn them:

| How | What They Gain |
|-----|---------------|
| Win 3+ battles | +Battle-Hardened |
| Successful encirclement | +Opportunist |
| Defensive hold under pressure | +Defensive Specialist |
| Graduate from Military Academy (built building) | Skill trait of your choice |
| Serve under a mentor commander | Inherit 1 of mentor's traits |
| Failed campaign | May gain **Cautious** or lose a positive trait |
| Espionage — foreign training program | +Foreign-Trained |

---

### Commander Loyalty & Tension

- Commanders have **loyalty** to the head of state
- Constantly overriding their plans reduces loyalty
- Very low loyalty: commander may **resign**, **defect**, or in authoritarian states — **stage a coup**
- High loyalty + high competence = valuable strategic asset
- Political trait commanders stay loyal even when overridden (they're political, not professional)

---

### Player Override at Any Time

The entire system is advisory and delegated — never forced:
- Click any army → override its current order
- Open MoD panel → countermand any directive
- Replace any commander at any time (with loyalty/morale cost to that army)
- Toggle "Full Manual" per theater — removes AI control for that front entirely

---

### Tasks for Implementation
1. `Commander.gd` resource — traits array, loyalty, competence, current orders
2. `MinisterOfDefense.gd` — strategic directive system, briefing event generator
3. `CommanderAI.gd` — behavior loop, trait-weighted decisions, situation assessment
4. `SituationAssessor.gd` — reads map state (unit positions, supply, terrain) → structured assessment
5. Commander appointment UI — hire/fire/assign commanders, view traits
6. Briefing event UI — MoD recommendations with approve/modify/reject
7. Trait acquisition events — fire on battle outcomes, training completion
8. Commander portrait system — procedurally named characters with portrait generation

### Verification
- [ ] MoD issues strategic recommendations as events
- [ ] Commanders move units autonomously toward objectives
- [ ] Aggressive commander visibly takes more risk than Cautious on same order
- [ ] Player can override any order at any time without breaking the system
- [ ] Trait events fire on correct triggers (battle wins, defensive holds, etc.)

---

## Phase 7d: Internal Governance — Elections, Cabinet, Taxes & Buildings

**Goal:** Your country has a functioning internal life. Players who want depth get full control. Players who don't get clean auto-manage with smart notifications.

**Design Rule:** Every system has an **Auto** toggle. When on, the game manages it reasonably. Player is only interrupted for decisions that matter strategically.

---

### Government Types

Government type determines what internal mechanics apply to your country.

| Type | Head of State | Head of Government | Elections? | Examples |
|------|--------------|-------------------|------------|---------|
| **Presidential Democracy** | President (player) | President | Yes, fixed term | USA, Brazil, France |
| **Parliamentary Democracy** | President / Monarch (figurehead) | Prime Minister | Yes, snap possible | UK, Germany, Japan |
| **Constitutional Monarchy** | King/Queen (figurehead) | Prime Minister | Yes | UK, Spain, Netherlands |
| **Absolute Monarchy** | King (player) | Appointed PM | No | Saudi Arabia, UAE |
| **Authoritarian** | President-for-life | Appointed cabinet | Staged/rigged | Russia, Belarus |
| **One-Party State** | General Secretary | Premier | Internal party only | China, Cuba |
| **Military Junta** | General | Appointed ministers | No | Myanmar, historical |
| **Theocracy** | Supreme Leader | President/PM | Limited | Iran |

Government type is seeded from real 2026 data. Can change via: revolution, coup, constitutional reform, foreign pressure.

---

### Cabinet System

Your cabinet is a roster of named characters you appoint. Each ministry has one seat. Characters come from a **pool of candidates** — visible when you open the appointment panel.

#### Ministries

| Ministry | Key Effect | Auto-manage behavior |
|----------|-----------|----------------------|
| **Head of State** | Prestige, foreign leader relations, rare veto power | Fixed (monarchy) or elected |
| **Prime Minister** | Overall governance bonus, stability multiplier | Auto picks highest competence available |
| **Minister of Finance** | Tax efficiency, GDP growth multiplier | Auto optimizes for growth |
| **Minister of Defense** | Military planning (full system in Phase 7c) | Auto executes your strategic directives |
| **Minister of Foreign Affairs** | Diplomacy action speed, relation bonuses | Auto maintains existing agreements |
| **Minister of Interior** | Stability, policing, civil unrest suppression | Auto keeps stability above 50 |
| **Minister of Science** | Research point multiplier, oversees tech buildings | Auto allocates domain funding evenly |
| **Minister of Trade** | Trade deal negotiation, export income | Auto accepts favorable trade deals |
| **Head of Intelligence** | Espionage ops, secret program security | Auto defends; player must approve offensives |

#### Character Traits for Staff

```gdscript
class_name StaffCharacter extends Resource
var full_name: String
var age: int
var portrait_seed: int          # for procedural portrait generation
var ministry_fit: Dictionary    # competence score per ministry type
var traits: Array[String]
var loyalty: float              # to the player/regime
var public_approval: float      # affects your approval if they're visible
var corruption_risk: float      # chance of scandal per year
```

**Staff Traits:**
| Trait | Effect |
|-------|--------|
| **Competent** | +20% ministry effectiveness |
| **Corrupt** | Siphons GDP, risk of scandal event |
| **Loyal** | Will not defect or leak, even under pressure |
| **Charismatic** | +public approval when appointed |
| **Technocrat** | Strong in their specific domain, weak outside it |
| **Party Loyalist** | Required in one-party states, reduces autonomy |
| **Independent** | Pushes back on bad decisions — may actually be good |
| **Foreign-Educated** | Bonus to international relations in their domain |
| **Military Background** | Defense/Interior bonuses, may push hawkish policies |
| **Reformist** | Boosts stability if given freedom, risks political tension |
| **Old Guard** | Stable, resistant to change, blocks radical reforms |

#### Candidate Pool
- 8–15 candidates visible at all times per country
- Pool refreshes slowly (new generation enters, old ones retire/die)
- Poach staff from other nations (diplomacy action — they defect with their traits)
- Educated population grows the quality of your candidate pool over time (literacy → better candidates)
- After major elections, losing party candidates may become available

---

### Elections

Only applies to democratic/parliamentary government types. Authoritarian states have **staged elections** (you can choose to rig them at stability cost or cancel them at bigger cost).

#### Election Cycle
- Presidential: fixed term (4–7 years depending on country)
- Parliamentary: fixed term OR snap election triggered (by player, by crisis, by losing confidence vote)

#### Election Mechanics (simplified)

```gdscript
class_name Election extends Resource
var date: Dictionary
var incumbent_approval: float   # your current approval rating
var opposition_strength: float  # generated from internal stability + events
var foreign_interference: float # other nations may be running ops against you
var result: float               # 0.0 = you lose, 1.0 = you win (landslide)
```

**Approval rating** is affected by:
- Stability (high stability = happy voters)
- Economic growth (GDP up = approval up)
- Active wars (controversial — some boost, some drain)
- Scandals (minister corruption events)
- Tax rate (high taxes = lower approval)
- Recent breakthroughs / achievements (moon shot, major infrastructure)

#### Player Election Actions (optional, spend Political Capital resource):
| Action | Cost | Effect |
|--------|------|--------|
| **Campaign Spending** | Money | +approval boost before election |
| **Policy Promise** | Commitment | +approval now, must deliver or lose trust later |
| **Suppress Opposition** | Stability cost | Reduce opposition strength (authoritarian only) |
| **Rig Results** | Stability + international pressure | Guarantee win, risk exposure |
| **Call Snap Election** | Political Capital | Force early election when your approval is high |

**Auto-manage:** Game handles campaigns automatically, notifies you of result. You only get asked if you want to spend Political Capital.

#### Election Results
- Win → continue current policies, approval reset to moderate
- Lose → opposition takes power:
  - **Auto-manage on:** AI picks reasonable opposition cabinet, you continue as before
  - **Auto-manage off:** You must appoint new cabinet from opposition pool, some policies may be blocked

---

### Tax System

Simple by design. Three levels of control:

**Level 1 — Auto (default):** AI sets taxes to optimize for your current Strategic Priority (set once):
- *Growth* → low taxes, incentivize investment
- *Military* → moderate taxes, fund army
- *Stability* → balanced, avoid unrest
- *Emergency* → high taxes, maximum revenue

**Level 2 — Sliders:** Player sets 3 main rates:

| Tax | Low | Medium | High |
|-----|-----|--------|------|
| **Income Tax** | +approval, -revenue | balanced | +revenue, -approval |
| **Corporate Tax** | +FDI, +GDP growth | balanced | +revenue, -investment |
| **Trade Tariffs** | +FDI, -trade revenue | balanced | +local industry, -trade volume |

**Level 3 — Sector breakdown** (deep micromanage, optional):
- Set different rates per economic sector (energy, manufacturing, agriculture, finance)
- Sector-specific effects on production and growth

**Tax Revenue** feeds the national budget. Budget allocations:
- Military spending %
- Social spending % (affects stability, literacy, healthcare)
- Infrastructure spending %
- Research funding %
- Debt servicing %

---

### Buildings

Construction queue per country. Buildings take in-game time to complete, cost upfront + ongoing maintenance.

#### Building Categories

**Economic**
| Building | Effect | Cost |
|----------|--------|------|
| Factory | +industrial output, +military production capacity | $$ |
| Power Plant | +energy, enables energy-dependent buildings | $ |
| Port Expansion | +trade volume, +naval capacity | $$ |
| Special Economic Zone | +FDI attraction, +GDP growth | $$$ |
| Stock Exchange | +tax revenue from finance sector | $$$ |

**Infrastructure**
| Building | Effect |
|----------|--------|
| Highway Network | +logistics speed, +army movement |
| Railway | +supply line range, +economic connectivity |
| Airport | +air unit capacity, +trade |
| Communications Grid | +research bonus, +intelligence capability |

**Social**
| Building | Effect |
|----------|--------|
| Hospital | +population growth, +stability |
| Public School Network | +literacy over time (slow but lasting) |
| University | +research points (general domain) |
| Housing Project | +stability, -unrest in cities |
| Media Network | +cultural influence, +soft power output |

**Military**
| Building | Effect |
|----------|--------|
| Military Base | +unit recruitment capacity, +supply hub |
| Air Base | +air unit capacity, required for jet operations |
| Naval Base | +naval unit capacity, required for fleet |
| Missile Silo | Required for ICBM deployment |
| Fortification | +defense in territory |
| Military Academy | +commander trait acquisition speed |

**Research** (already detailed in Phase 7b)

#### Auto-Build
Toggle **Auto-Build** and set a priority:
- **Economic Growth** → AI queues factories, SEZs, ports
- **Military Buildup** → AI queues bases, fortifications, military industry
- **Stability & Development** → AI queues hospitals, housing, schools
- **Research** → AI queues universities, labs, institutes

Player can always insert manual queue items that override auto.

---

### Political Capital

A soft resource that flows from: high approval + stable government + time in power.
Spent on: elections, policy changes, major diplomatic actions, overriding advisors, emergency measures.

Authoritarian states generate Political Capital differently — from loyalty networks and purging opposition rather than approval.

---

### Tasks for Implementation
1. `GovernmentSystem.gd` — government type, cabinet roster, ministry assignment
2. `StaffCharacter.gd` — character resource, trait system, candidate pool generation
3. `ElectionSystem.gd` — approval tracking, election scheduling, result calculation
4. `TaxSystem.gd` — three-level tax control, auto-optimize by strategic priority
5. `BuildingSystem.gd` — construction queue, building effects, auto-build AI
6. `PoliticalCapital.gd` — generation, spending, limits
7. **Cabinet Panel UI** — view all ministries, candidate list, appoint/fire
8. **Election Panel UI** — approval rating, countdown, action options, result screen
9. **Domestic Dashboard UI** — taxes, budget sliders, building queue, all with auto toggles
10. Government type seeded from real 2026 data in `countries.json`

### Verification
- [ ] Appointing a Corrupt minister triggers eventual scandal event
- [ ] Election fires on schedule, approval affects result
- [ ] Losing election with auto-manage on does not break anything
- [ ] Tax sliders visibly affect revenue and approval
- [ ] Building queue processes over time, building effects apply on completion
- [ ] Auto-manage handles all systems if player never touches them

---

## Phase 7e: The Game Behind the Game — Advanced Systems

---

### System 1: Gray Zone Conflict

Modern geopolitics isn't war or peace — it's **constant deniable pressure**. This layer sits between diplomacy and war on the escalation ladder.

```gdscript
class_name GrayZoneOp extends Resource
var op_type: String         # "fund_militia", "trigger_unrest", "sabotage_infra", 
                            #  "assassinate_official", "election_interference"
var actor_iso: String       # who's doing it (hidden)
var target_iso: String      # who's being targeted
var target_region: String   # specific province/region
var funding: float          # monthly cost
var detection_chance: float # increases with time, poor intel, leaks
var progress: float         # 0.0 – 1.0
var deniability: bool = true
```

#### Operations Available
| Operation | Effect | Detection Risk |
|-----------|--------|---------------|
| **Fund Militia** | Spawns irregular units in target territory, raises unrest | Medium |
| **Trigger Unrest Zone** | Slowly destabilizes a region (stability drain) | Low |
| **Sabotage Infrastructure** | Destroys a building without declaring war | Medium |
| **Election Interference** | Shifts election result probabilities | High (if exposed) |
| **Assassinate Official** | Removes a minister/commander | Very High |
| **Disinformation Campaign** | Damages target's global narrative | Low-Medium |
| **Proxy Army Supply** | Funds and equips an existing rebel/militia force | Medium |
| **Counter-Intel Sweep** | Defend against incoming ops, expose agents | — |

#### Detection & Response
When an op is detected (probability check each week):
- **Expose publicly** → massive diplomatic hit for the actor, UN condemnation, sanctions possible
- **Counter-fund** → start your own gray zone op in their territory
- **Retaliate in kind** → escalate to Level 2 on the Escalation Ladder
- **Ignore** → op continues, risk of further escalation

**Denial mechanics:** Even when caught, actor can deny. If their Narrative score is high enough, some nations believe the denial. Weak narrative = everyone believes the exposure.

---

### System 2: National Identity Drift

Countries aren't static. Policies, foreign influence, crises, and education slowly shift a country's fundamental character — affecting everything else.

#### Identity Axes (each 0–100)

```gdscript
class_name NationalIdentity extends Resource
var globalist_nationalist: float    # 0 = globalist, 100 = nationalist
var democratic_authoritarian: float # 0 = democratic, 100 = authoritarian
var secular_religious: float        # 0 = secular, 100 = religious
var open_protectionist: float       # 0 = open economy, 100 = protectionist
var progressive_conservative: float # 0 = progressive, 100 = conservative
```

#### What Shifts Identity

| Action | Effect on Identity |
|--------|--------------------|
| Invest in education | → more globalist, more secular |
| Build media network | → shifts toward your ideology if foreign-owned |
| Impose high tariffs | → more protectionist |
| Win a war | → more nationalist |
| Lose a war + occupation | → depends on occupier's identity |
| Economic crisis | → more nationalist, more protectionist |
| Foreign cultural investment | → toward investor's identity (soft power) |
| Religious building investment | → more religious |
| Authoritarian crackdown | → more authoritarian |
| Free elections over time | → more democratic |
| High literacy rate | → more secular, more globalist |

Identity shifts are **slow** — months to years, not days. They're visible as a gradual drift on the country card.

#### What Identity Affects

| Identity State | Effect |
|----------------|--------|
| High Nationalist | Harder to influence diplomatically, trade deals less likely |
| High Authoritarian | Elections suppressed, stability harder to maintain, easier purges |
| High Religious | Secular policies cause unrest, religious leaders have political power |
| High Protectionist | Tariffs auto-raised, foreign investment rejected more often |
| High Globalist | Open to alliances, trade-hungry, vulnerable to economic dependency |
| Aligned with yours | Easier diplomacy, faster soft power gain, natural ally |
| Opposed to yours | Harder diplomacy, gray zone ops more justified internally |

---

### System 3: Leader Relationships

Country-to-country relations already exist. But real diplomacy is personal.

```gdscript
class_name LeaderRelationship extends Resource
var leader_a: String           # character ID
var leader_b: String           # character ID
var personal_score: int        # -100 to +100, separate from country relations
var history: Array[String]     # ["betrayed_deal_2027", "allied_crisis_2026"]
var grudge: bool               # if true: diplomacy permanently harder until one leaves power
var rivalry: bool              # public antagonism, affects their populations too
var mutual_respect: bool       # earned through kept promises, shared crises
```

#### Relationship Events
- **Betrayal** — you break a deal with their leader → `grudge = true`, personal score crashes, may never recover while they're in power
- **Shared Crisis** — both nations face same threat → personal score rises, "crisis bond"
- **Public Insult** — narrative attack that names them specifically → rivalry flag, affects their domestic approval of any deal
- **Summit Meeting** — diplomatic action: spend Political Capital → personal score boost, unlock deeper deals
- **Leader Death / Removal** — relationship history stays in country memory but personal score resets with new leader (fresh start opportunity)
- **Former Allies** → shared history bonus, deals close faster, trust higher

#### Gameplay Dialogue
Leaders appear in event text with personality:
> *"President Okafor refuses to negotiate while your government remains in power. The grudge from the 2027 broken ceasefire runs deep."*

> *"Chancellor Weber, recalling your joint response to the 2026 financial crisis, is willing to consider an alliance proposal."*

---

### System 4: Information Control & Narrative Warfare

You have influence. Now you need **perception**. What people believe is as powerful as what's real.

#### Two Narrative Scores per Country

```gdscript
class_name NarrativeState extends Resource
var domestic_narrative: float   # 0–100: how well you control your own population's perception
var global_narrative: float     # 0–100: how credible you are internationally
var war_framing: String         # "defensive", "liberation", "aggression", "peacekeeping"
var active_campaigns: Array     # running narrative ops
```

#### Narrative Actions
| Action | Cost | Effect |
|--------|------|--------|
| **State Media Push** | Monthly GDP | +domestic narrative, requires Media Network building |
| **International Press Campaign** | GDP | +global narrative, frame your actions favorably |
| **Expose Enemy Scandal** | Intel resource | -their global narrative, requires evidence from espionage |
| **Frame War as Defensive** | Political Capital | Changes war_framing tag, affects war support + sanctions |
| **Hide Economic Failure** | Domestic narrative cost | Delays stability hit, but if exposed: larger crash |
| **Whistleblower Suppression** | Authoritarian countries only | Prevent domestic leaks |
| **Fund Foreign Media** | GDP | Slowly shifts target country's domestic narrative toward yours |

#### Narrative Effects
| Narrative Score | Effect |
|----------------|--------|
| Domestic > 70 | Population supports war even if losing, stability resistant |
| Domestic < 30 | War protests, instability risk, election risk |
| Global > 70 | Sanctions unlikely, allies give benefit of the doubt |
| Global < 30 | Every action scrutinized, easy to build coalitions against you |
| Exposed gray zone op + High Global Narrative | Some nations don't believe exposure |
| Exposed gray zone op + Low Global Narrative | Near-universal condemnation |

---

### System 5: Escalation Ladder

War is not a button. It's a **spectrum** that both sides climb together, with consequences at every step.

```gdscript
enum EscalationLevel {
    PEACE           = 0,   # Normal relations
    TENSIONS        = 1,   # Sanctions, expulsions, military posturing
    PROXY_CONFLICT  = 2,   # Gray zone active, deniable ops, militia war
    LIMITED_STRIKES = 3,   # Declared strikes on specific targets, not full war
    FULL_WAR        = 4,   # Conventional war, all units engage
    TOTAL_WAR       = 5,   # Full mobilization, civilian infrastructure targeted
    NUCLEAR_THRESHOLD = 6  # One or both sides have nukes ready, world watches
}
```

#### Escalation Mechanics

Moving **up** the ladder:
- Triggered by actions (strike, sanction, exposed op, broken deal)
- Both sides see the escalation notification
- A countdown timer allows de-escalation before it locks in
- Player choice: escalate further, hold, or back down

Moving **down** the ladder:
- Requires both sides to agree (ceasefire, deal, face-saving exit)
- Backing down at Level 3+ costs Domestic Narrative (seen as weakness)
- A strong leader relationship can fast-track de-escalation

#### Chicken Mechanic
At Levels 3–5, both sides are playing chicken:
- Each escalation costs resources and narrative
- Backing down first costs prestige
- Neither backing down → escalates to next level automatically
- Nuclear Threshold = world event fires, global pressure on both sides to stand down

#### Nuclear Deterrence at Level 6
- If both sides have nukes: **Mutually Assured Destruction** check
- AI nations almost always de-escalate at Level 6 (realistic)
- Player can choose to launch — triggers game-ending **Nuclear War** scenario
- Neighbors, allies, enemies all react to Level 6 tensions regardless of involvement

---

### System 6: World Events (The World Hits Back)

The world isn't just reacting to players. Semi-random but **logically triggered** events reshape the global landscape.

```gdscript
class_name WorldEvent extends Resource
var event_id: String
var trigger_conditions: Dictionary   # what makes this likely to fire
var probability_weight: float        # higher = more likely when conditions met
var affected_countries: Array        # who is impacted
var effects: Dictionary              # what changes
var player_choices: Array            # options player can take in response
```

#### Event Categories

**Economic**
- Global Recession — triggers when: 3+ major economies have debt-to-GDP > 120%, GDP growth negative globally
- Oil Price Shock — triggers when: major oil producer destabilized or at war
- Trade War Escalation — triggers when: 2+ nations in prolonged tariff conflict
- Tech Revolution — triggers when: 5+ nations reach high Research score in same domain (civilian spillover)

**Geopolitical**
- Great Power Summit — triggers when: 2 S-tier nations at Escalation Level 2+ for 6+ months
- Refugee Crisis — triggers when: war or major instability in high-population region
- Breakaway Region — triggers when: region has low stability + nationalist identity + historical tension data
- UN Vote / Sanctions Coalition — triggers when: global narrative against one nation is very low

**Environmental / Disaster**
- Pandemic — triggers when: global healthcare investment has been low for 5+ years
- Climate Disaster — triggers when: global energy still fossil-fuel-heavy after Year 10
- Drought / Famine — triggers when: agricultural investment low + regional conflict
- Natural Disaster — triggers anywhere, probability seeded by real geological/climate data

**Technology**
- AI Governance Crisis — triggers when: multiple nations reach AI tech without stability infrastructure
- Cyber Attack on Global Infrastructure — triggers when: Cyber domain highly developed globally

#### World Event Effects
Each event reshapes the power landscape:
- Creates **opportunities for small nations** (weak nation supplies emergency aid → massive soft power gain)
- Forces **adaptation** (ignore a pandemic → massive stability/population hit; respond early → prestige boost)
- **Reshuffles power** (global recession devastates high-debt nations, benefits low-debt ones)

---

### System 7b: Advisors Who Disagree With You

Your ministers aren't yes-men. They have opinions based on their traits, their read of the data, and their own ideology. They push back when you're making a mistake — and they're **actually smart**: they run the same situation assessment the AI uses, so their warnings are grounded in real game state.

#### How It Works

Every major player decision passes through an **Advisor Review**. Each minister evaluates it through their domain lens and their personality. If their assessment conflicts with your action, they speak up.

```gdscript
class_name AdvisorOpinion extends Resource
var minister: StaffCharacter
var stance: String          # "support", "concern", "oppose", "strongly_oppose"
var reasoning: String       # generated from actual game data
var risk_assessment: Dictionary  # what they calculated
var emotional_tone: String  # "professional", "alarmed", "resigned", "angry"
```

#### Advisor Intelligence — They Read the Data

Ministers don't argue randomly. They run a simplified version of the same models the game uses:

```gdscript
# Minister of Finance evaluating a war declaration:
func _assess_war_declaration(target: Country) -> AdvisorOpinion:
    var war_cost_estimate = CombatSystem.estimate_war_cost(player_country, target)
    var current_reserves = player_country.economy.reserves
    var debt_ratio = player_country.economy.debt_to_gdp
    
    if war_cost_estimate > current_reserves * 0.6 or debt_ratio > 120:
        return AdvisorOpinion.new({
            "stance": "strongly_oppose",
            "reasoning": "At current debt levels, a prolonged conflict risks sovereign default. 
                         Our reserves cover roughly %d months of war expenditure." 
                         % [months_covered],
            "emotional_tone": "alarmed"
        })
```

#### Example Advisor Dialogues

**Declaring war on a stronger nation:**
> *Finance Minister: "Our GDP is a third of theirs. This war will bankrupt us within 18 months. I strongly advise against this."*  
> *Minister of Defense: "Our military is unprepared. We have 3 armored divisions to their 12. I cannot recommend this action."*  
> *Foreign Minister: "We'll lose every ally we have the moment we fire first. The international response will be severe."*

**Raising taxes during a stability crisis:**
> *Minister of Interior: "Stability is already at 34. A tax hike right now will push us below the unrest threshold. We'll have riots within weeks."*

**Ignoring a gray zone op against you:**
> *Head of Intelligence: "We've identified Russian funding in the northern militias. Every week we wait, they get stronger. We need to act or expose them now."*

**After a string of good decisions:**
> *Prime Minister: "The economy has grown 12% this year. Our military is well-supplied. The ministers are in agreement — this is working."*

#### Player Response to Advisor Opposition

| Response | Effect |
|----------|--------|
| **Listen** — change or delay decision | Loyalty +5 to that minister, they feel heard |
| **Override with explanation** | Loyalty neutral, minister notes it in their record |
| **Override and ignore** | Loyalty -5, if repeated: minister may leak to press or resign |
| **Fire them** | Immediate silencing, but: loyalty crash across all ministers ("they'll fire anyone who disagrees"), candidate pool quality drops if done often, possible public scandal depending on how prominent they were |
| **Ask for more detail** | Opens deep breakdown panel — full numbers, scenarios, probability estimates |

#### Advisor Disagreement Threshold by Trait

Not every minister speaks up on everything:

| Trait | When They Speak Up |
|-------|-------------------|
| **Independent** | Always, on anything concerning their domain |
| **Loyal** | Only when the risk is catastrophic — they protect you, not themselves |
| **Technocrat** | Only on technical domain matters, ignores political/strategic issues |
| **Political General** | Rarely disagrees — tells you what you want to hear (danger) |
| **Reformist** | Speaks up on domestic rights, authoritarian policies |
| **Old Guard** | Resists rapid change, warns on anything unconventional |

**Sycophantic Cabinet Risk:** If you fire everyone who disagrees, your remaining cabinet is all loyalists. They tell you what you want to hear. The game quietly increases Black Swan risks — no one warned you. *This is intentional. It models real-world authoritarian failure modes.*

#### Collective Cabinet Votes

On major decisions (war, constitutional change, emergency powers) the full cabinet votes. You see a breakdown:

```
War Declaration — Cabinet Vote
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
■ Minister of Defense:     SUPPORT   "We're ready."
■ Finance Minister:        OPPOSE    "We can't afford this."
■ Foreign Minister:        CONCERN   "Timing is poor."
■ Minister of Interior:    OPPOSE    "Stability is fragile."
■ Prime Minister:          SUPPORT   "The nation demands action."

Result: 2 support, 2 oppose, 1 concern

[Proceed anyway]  [Delay 30 days]  [Cancel]
```

Proceeding against majority opposition: loyalty hit, domestic narrative drop ("leaked: cabinet split on war decision").

---

### System 7: Black Swan Events (Logical Chaos)

Rare, high-impact events. **Never purely random** — always probability-weighted by underlying conditions. The game creates a pressure-cooker and the Black Swan is what blows the lid.

```gdscript
class_name BlackSwanEvent extends Resource
var event_id: String
var rarity: float               # base probability per year (e.g. 0.02 = 2% per year)
var condition_multipliers: Dictionary  # conditions that multiply base probability

# Example: Military Mutiny
# rarity: 0.01 (1% per year baseline)
# condition_multipliers: {
#     "military_morale < 20":  5.0,   # 5x more likely
#     "economy_gdp_growth < -5": 3.0, # 3x more likely
#     "stability < 25":         4.0,  # 4x more likely
#     "losing_war":             6.0,  # 6x more likely
#     "commander_loyalty < 20": 3.0,  # 3x more likely
# }
# Combined worst case: 0.01 × 5 × 3 × 4 × 6 × 3 = 10.8% per year (~guaranteed eventually)
```

#### Black Swan Catalogue

| Event | Base Rate | Key Trigger Conditions |
|-------|-----------|----------------------|
| **Sudden Leader Death** | 1%/yr | Age > 70, active war, high enemy intel ops |
| **Military Mutiny** | 1%/yr | Morale < 20, losing war, GDP crash, low loyalty |
| **Economic Collapse** | 0.5%/yr | Debt/GDP > 200%, credit rating < 10, no reserves |
| **Coup d'état** | 1%/yr | Stability < 20, authoritarian regime, military power > civilian |
| **Revolution** | 0.5%/yr | Stability < 15, democratic identity high, authoritarian govt |
| **Tech Breakthrough Chain** | 2%/yr | High research + serendipity cross-domain (see Research system) |
| **Defection of Key Ally** | 1%/yr | Ally relations < 20, rival offering better deal, war losing |
| **Natural Resource Discovery** | 1%/yr | Unexplored territories, geology seed |
| **Pandemic Outbreak** | 0.5%/yr | Low healthcare, high population density, active conflict zones |
| **Nuclear Accident** | 0.2%/yr | Nuclear program active, low research quality, instability |
| **Assassination** | 0.5%/yr | Enemy intel ops active, low domestic narrative, public events |
| **Mass Protest → Government Change** | 1%/yr | Stability < 25, high literacy, democratic identity |

#### Player Response
Black Swans are **events with choices**, not silent stat changes:
> *"General Volkov's 3rd Army has refused orders. Soldiers are advancing on the capital. The general cites unpaid wages and three years of failed campaigns."*  
> **[Pay them immediately — costs $50B] [Send loyal units to intercept] [Negotiate — give Volkov a political role] [Flee the country]**

Each choice has consequences that ripple through other systems.

---

### System 8: Long-Term Consequences & World Memory

The world remembers what you do. Not just as a score — as a **structured history** that other nations, leaders, and systems actively reference when making decisions about you.

---

#### The Memory Record

Every significant action writes a `WorldMemory` entry:

```gdscript
class_name WorldMemory extends Resource
var event_type: String          # "betrayed_treaty", "aided_crisis", "annexed_nation",
                                #  "broke_ceasefire", "supported_rebellion", "used_nukes"
var actor_iso: String           # who did it
var target_iso: String          # who it was done to
var witnesses: Array[String]    # nations that observed (affects who remembers)
var date: Dictionary            # when it happened
var weight: float               # 0.0–10.0, severity
var decay_rate: float           # how fast it fades (per year). 0 = permanent
var current_strength: float     # weight * (1 - years_elapsed * decay_rate), floored at 0

# Permanent events (decay_rate = 0):
# - Used nuclear weapons
# - Committed genocide / mass civilian targeting  
# - Annexed a great power
# - Triggered nuclear war (game-ending)

# Long-lived (decay_rate = 0.05 → fades over ~20 years):
# - Betrayed a formal alliance during active war
# - Destroyed a functioning state
# - Broke a signed peace treaty within 2 years

# Medium (decay_rate = 0.15 → fades over ~7 years):
# - Sanctioned an ally
# - Broke a trade deal
# - Publicly denied a proven gray zone op

# Short-lived (decay_rate = 0.3 → fades over ~3 years):
# - Minor diplomatic insult
# - Refused a trade deal
# - Recalled an ambassador
```

---

#### Reputation Axes

Accumulated memories build a **reputation profile** — not a single number but a behavioral fingerprint that other nations read differently depending on who they are.

```gdscript
class_name Reputation extends Resource
# Each axis: -100 to +100
var treaty_reliability: float   # Do you keep your word?
var military_restraint: float   # Do you fight clean, or target civilians?
var generosity: float           # Do you help nations in crisis?
var aggression: float           # Do you start conflicts?
var consistency: float          # Do your actions match your stated values?
var nuclear_posture: float      # Have you used/threatened nukes?
```

Other nations weight these axes differently:
- **Small nations** care most about `aggression` and `treaty_reliability` — are you safe to be near?
- **Great powers** care most about `consistency` and `treaty_reliability` — can they predict you?
- **Neighbors of your victims** care most about `military_restraint` and `aggression`
- **Your allies** care most about `treaty_reliability` and `generosity`

---

#### Ripple Effects

Actions don't stay bilateral. They radiate outward.

**Betraying an ally:**
```
You betray Ally A during their war
        ↓
Ally A: grudge formed, relations crash, escalation possible
        ↓
Witnesses (all nations that had treaties with you):
    treaty_reliability drops -15 globally
        ↓
3 smaller nations quietly begin hedging — seek alternative alliances
        ↓
Your MoD reports: "Two allies have reduced joint exercise frequency."
        ↓
6 months later: alliance renewal requests decline
```

**Destroying a nation:**
```
You annex / fully destroy Country X
        ↓
Country X's population: refugee wave → destabilizes 2–3 neighbors
        ↓
Neighbors: stability -10, nationalist identity drift (fear response)
        ↓
Regional nations: aggression +20 against you in reputation
        ↓
Great powers: begin evaluating containment options
        ↓
If Country X had a diaspora in other nations:
    → Gray zone ops easier for enemies to recruit from
    → Resistance movements may appear in occupied territory for years
```

**Supporting a nation through crisis:**
```
You send aid during Country Y's famine / disaster
        ↓
Country Y: relations +30, generosity +10 to your reputation
        ↓
Country Y's neighbors notice: soft power gain in region
        ↓
Country Y's identity drifts toward yours over years
        ↓
10 years later: Country Y votes with you at international forums
        ↓
If Country Y later faces aggression:
    → They call on you first
    → Their population supports your intervention (legitimacy)
```

**Using nuclear weapons:**
```
You use a nuclear weapon (any yield)
        ↓
Immediate: global relations crash (-50 with every nation)
        ↓
nuclear_posture reputation: permanent mark, never decays
        ↓
Nuclear taboo broken globally:
    → All nations accelerate nuclear programs (research weight ×3)
    → Nations without nukes become desperate for them
        ↓
New gray zone ops appear: nuclear proliferation networks
        ↓
Your own population: stability -30 (unless narrative very high)
        ↓
Permanent: future leaders of every nation remember this
```

---

#### Generational Memory

When a **new leader** comes to power in any country:

```gdscript
func _on_leader_change(country: Country, new_leader: StaffCharacter):
    # New leader inherits world memory but with reduced weight
    for memory in WorldMemoryDB.get_memories_involving(country.iso):
        memory.current_strength *= 0.6    # 40% forgotten with new generation
        
        # Except permanent events — those stay at full weight
        if memory.decay_rate == 0:
            memory.current_strength = memory.weight
            
        # And events that happened to their own nation stay stronger
        if memory.target_iso == country.iso:
            memory.current_strength *= 1.4   # their own wounds stay fresher
```

A new leader is a **diplomatic reset opportunity** — but not a full wipe. The history is still there, just lighter. Nations that suffered deeply never fully forget.

---

#### The History Book (Player-Facing)

Players can open a **World History** panel showing:
- Timeline of major events involving their nation
- How other nations currently perceive them (reputation axes as readable text)
- "Why does X hate us?" — drill down to specific memories
- Long-term consequence warnings: *"Your annexation of Ukraine in 2027 continues to affect relations with all European nations. This memory will fade around 2043."*

Advisors also reference history in their dialogue:
> *"Prime Minister, our history of breaking the 2026 ceasefire still weighs on our global narrative. A new peace offer may be dismissed as insincere."*

> *"Chancellor Merz has not forgotten the sanctions we imposed during the 2028 crisis. Personal score remains very low despite 3 years of improved relations."*

---

#### Consequence Chains (No Action Is Isolated)

The five consequence chains that matter most:

| Starting Action | Chain |
|----------------|-------|
| **Betray treaty** | Treaty reliability drops → allies hedge → alliance renewals fail → isolated when threatened |
| **Support country in crisis** | Relations + reputation → identity drift → long-term ally → votes with you globally |
| **Destroy a nation** | Refugees destabilize neighbors → resistance forms → regional fear → containment coalition |
| **Gray zone exposed** | Narrative drops → escalation climbs → target retaliates → allies distance themselves |
| **Consistent generosity over decade** | Soft power web builds → nations defend you at global forums → your sanctions cost others less → your wars get legitimacy |

---

#### Tasks for Implementation
1. `WorldMemoryDB.gd` — autoload singleton, stores all memory records, handles decay on `tick_year`
2. `ReputationSystem.gd` — aggregates memories into reputation axes per country, recalculates on new memories
3. `RippleEffect.gd` — defines ripple rules per event type, applies secondary/tertiary effects with delay
4. `GenerationalMemory.gd` — hooks into leader change events, applies memory inheritance
5. History panel UI — timeline view, reputation breakdown, "why does X feel this way" drill-down
6. Advisor dialogue generation — references specific memories with dates and context
7. AI decision engine reads reputation axes when evaluating alliances, war declarations, deals

---

### System Interconnections

All 7 systems feed each other:

```
Gray Zone Op discovered
        ↓
Global Narrative drops
        ↓
Escalation climbs to Level 2
        ↓
Target nation's Identity drifts Nationalist
        ↓
Leader Relationship: grudge formed
        ↓
World Event: Sanctions Coalition fires
        ↓
Your economy weakens
        ↓
Black Swan risk: Military Mutiny probability × 3
```

No system is isolated. Everything causes everything.

---

## Phase 8: AI Behavior

**Goal:** Countries act autonomously. Each has a strategic personality.

### Tasks
1. `AIController.gd` — decision engine per country, runs every 30 in-game days:
   - **Personality types:** Expansionist, Trader, Isolationist, Diplomat, Opportunist
   - Evaluate threats (military), opportunities (weak neighbors, loan targets)
   - Decide action: build units / invest economy / offer loans / declare war / seek alliance
2. Great power rivalry system — S-tier nations compete for global influence, apply pressure on rising B/C tier nations
3. Proxy war system — great powers can fund weaker nations at war with rivals
4. Alliance blocs form organically based on relations and shared threats
5. Technology tree — 2026 baseline, unlock 2030s tech (hypersonics, AI warfare, quantum comms)

---

## Phase 9: Steam Integration & Polish

**Goal:** Ship-ready build with Steam features.

### Tasks
1. Install GodotSteam GDExtension 4.18+ (from Godot Asset Library asset #2445)
2. Initialize Steam in `Main.gd`:
   ```gdscript
   func _ready():
       var result = Steam.steamInitEx(YOUR_APP_ID, true)
       if result != Steam.STEAM_API_INIT_RESULT_OK:
           push_error("Steam init failed: " + str(result))
   ```
3. Implement Steam achievements framework
4. Save/load game state (JSON to user data dir)
5. Main menu, settings (resolution, audio, keybinds)
6. Performance pass: profile with Godot profiler, optimize heavy scenes

---

## Data Pipeline Tools (Phase 0 Tooling)

Run these once before Phase 1:

```bash
# 1. Download Natural Earth GeoJSON
curl -L https://github.com/nvkelso/natural-earth-vector/raw/master/geojson/ne_50m_admin_0_countries.geojson -o tools/countries.geojson

# 2. Fetch country data from REST Countries API
curl "https://restcountries.com/v3.1/all?fields=name,cca3,capital,region,population,borders,latlng,flags" -o tools/rest_countries.json

# 3. Run conversion script
python tools/geojson_to_godot.py
```

The Python tool outputs:
- `data/provinces.json` — polygons + centroids in Godot screen coords
- `data/countries.json` — merged country metadata
- `data/adjacencies.json` — border adjacency graph
- `assets/map/provinces.png` — 4096×2048 color bitmap for click detection

---

## MVP Definition

**Phase 1–5 = Playable combat sandbox**
- Real world map, 195 countries
- Real-time clock with pause/speed
- Units: Infantry, Armor, Fighter Jet
- Click to select, right-click to move
- Basic combat and conquest

**Phase 1–7 = Full early access release**
- All of above + economy, soft power, diplomacy
- Country info dashboard
- Sphere of influence map layer
- Multiple viable paths to dominance (military / economic / diplomatic)
- Country power tiers, dynamic difficulty

**Phase 8–9 = 1.0 release**
- AI with personalities
- Steam integration, achievements, save/load

---

## Map System — Layers & Modes

### Two Base Map Modes

Players toggle between two fundamental map views at any time (keyboard shortcut or UI button):

---

#### Mode 1: Political Map (Default / "Basic")
Clean, readable. Countries shown as solid colors. No terrain detail. Optimized for gameplay decisions.
- Country colors (by owner)
- Borders clearly visible
- Unit icons on top
- Clean UI, no visual noise

#### Mode 2: Immersive Map ("Terrain Mode")
The real world rendered as it looks. Mountains, deserts, forests, rivers, coastlines visible. Still fully playable — just visually rich.
- Real terrain texture (from Natural Earth raster or blended terrain bitmap)
- Country borders as overlaid lines, not fills
- Terrain types visible (mountain ranges, Sahara, Amazon, Siberian tundra)
- Rivers and lakes rendered
- Resources shown as icons on terrain (toggle separately)

---

### Map Layer Overlays (togglable on top of either base mode)

Each layer is a separate toggle. Multiple can be active simultaneously. Inspired by HoI4's map mode strip.

| Layer | What it shows | Visual Style |
|-------|--------------|-------------|
| **Political** | Country ownership, borders | Solid color fill |
| **Terrain** | Mountain/plains/desert/forest/jungle/tundra | Texture blend |
| **Resources** | Oil, gas, minerals, farmland icons | Point icons |
| **Economy** | GDP per country | Heat map (green = rich, red = poor) |
| **Sphere of Influence** | Who has leverage over whom | Colored radial gradient per major power |
| **Military** | Unit positions, front lines, war zones | Unit icons + front line markers |
| **Stability** | Civil unrest level | Heat map (blue = stable, red = unstable) |
| **Debt** | Debt-to-GDP ratio | Heat map |
| **Population** | Population density | Dot density or heat map |
| **Infrastructure** | Road/rail/port levels | Line network overlay |
| **Research** | Technology level by country | Color gradient |
| **Elections** | Upcoming elections, recent results | Flag icons + color tint |
| **Climate/Terrain** | Terrain type for combat planning | Terrain color code |

**Shortcut strip** at bottom of screen — one click to switch, hotkeys 1–9 for fast access.

---

### Terrain Types (Gameplay Effects)

Derived from SRTM elevation + ESA CCI land cover, merged into a single terrain bitmap.

| Terrain | Color Code | Army Move | Defense Bonus | Build Restriction | Resource |
|---------|-----------|-----------|--------------|-------------------|---------|
| **Plains** | Light green | 100% | None | None | Farmland |
| **Forest** | Dark green | 60% | +15% defender | No airports | Timber |
| **Desert** | Tan/yellow | 70% | None | No farms | Oil/Gas (Middle East) |
| **Mountain** | Grey/brown | 30% | +40% defender | Limited | Minerals, Uranium |
| **Jungle** | Deep green | 40% | +20% defender | Very limited | Rare Earths |
| **Tundra** | Blue-grey | 50% | None | Limited | Oil (Arctic) |
| **Urban** | Dark grey | 80% | +30% defender | Dense building | Economic hub |
| **Wetlands** | Blue-green | 20% | +10% defender | Very limited | None |
| **Coastline** | Teal edge | — | Naval range | Ports/bases | Fishing |
| **Arctic** | White | 10% | None | None | Oil (future tech) |

---

### Resources System

Resources are **point locations** derived from real-world data (USGS MRDS, EIA, FAO GAEZ). Each resource deposit sits on a territory and generates income/production when:
1. You control the territory
2. You've built the required extraction building

#### Resource Types

| Resource | Source Data | Building Required | Effect |
|----------|------------|------------------|--------|
| **Oil** | USGS/EIA fields | Oil Rig / Refinery | +GDP, fuel for mechanized/air units |
| **Natural Gas** | USGS/EIA | Gas Platform | +GDP, energy independence |
| **Coal** | USGS MRDS | Mine | +industrial output, +power |
| **Iron Ore** | USGS MRDS | Mine | +armor/artillery production |
| **Copper** | USGS MRDS | Mine | +electronics, +cyber research |
| **Uranium** | USGS MRDS | Enrichment Facility | +nuclear program, +energy |
| **Rare Earths** | USGS Critical Minerals | Processing Plant | +aerospace/cyber/electronics research |
| **Gold** | USGS MRDS | Mine | +credit rating, +loan capacity |
| **Lithium** | USGS Critical Minerals | Processing Plant | +drone/EV production |
| **Arable Land** | FAO GAEZ | Farm | +food security, +population growth, -import dependency |
| **Freshwater** | Natural Earth | Water Treatment | +stability, +population growth |
| **Timber** | Land cover | Logging | +construction speed |
| **Fishing** | Coastal zones | Fishing Port | +food security |

#### Resource Strategic Mechanics
- **Control ≠ Extraction** — you must build the right facility and fund it
- **Resource Dependency** — if you run mechanized units without controlling oil, you pay import prices (higher upkeep)
- **Resource Leverage** — controlling a rare resource others need = diplomatic/economic power
- **Depletion** — large fields deplete slowly over decades (very long game only)
- **Sanctions** — cutting off a nation's resource imports is a viable soft-power weapon

---

### Data Pipeline (Updated)

```
tools/
├── geojson_to_godot.py        # country polygons → provinces.json
├── terrain_pipeline.py        # SRTM + ESA CCI → terrain.png (4096×2048)
├── resources_pipeline.py      # USGS MRDS + EIA → resources.json (point list)
└── merge_map_data.py          # combines all into final game data package
```

#### Data Sources (All Free/Open)

| Layer | Source | Format | URL |
|-------|--------|--------|-----|
| Country polygons | Natural Earth 1:50m | GeoJSON | github.com/nvkelso/natural-earth-vector |
| Terrain texture | Natural Earth Raster II | GeoTIFF | naturalearthdata.com/downloads/10m-raster-data |
| Elevation (mountains) | NASA SRTM 90m | GeoTIFF | portal.opentopography.org |
| Land cover classes | ESA CCI-LC | NetCDF→GeoTIFF | esa-landcover-cci.org |
| Oil & gas fields | USGS World Oil/Gas | Shapefile | usgs.gov/tools/world-oil-and-gas |
| Mineral deposits | USGS MRDS | Shapefile | mrdata.usgs.gov/mrds |
| Critical minerals | USGS Critical Minerals | Shapefile | usgs.gov/tools/critical-minerals-atlas |
| Arable land | FAO GAEZ v5 | GeoTIFF | gaez.fao.org |
| Rivers & lakes | Natural Earth Physical | Shapefile | naturalearthdata.com |

#### GDAL Conversion Commands
```bash
# Resample any raster to 4096x2048
gdalwarp -ts 4096 2048 -r bilinear input.tif terrain_base.tif

# ESA CCI NetCDF → GeoTIFF
gdal_translate -of GeoTIFF NETCDF:"input.nc":lccs_class landcover.tif

# Normalize to 8-bit PNG for Godot
gdal_translate -ot Byte -scale landcover.tif -of PNG landcover.png

# Shapefile → GeoJSON (minerals, oil)
ogr2ogr -f "GeoJSON" oil_fields.json usgs_oil.shp
```

---

### Rendering Architecture

```
MapRenderer.gd
├── _base_layer: TextureRect          # terrain.png (immersive) OR flat color (political)
├── _political_overlay: Node2D        # Polygon2D per country, color fill
├── _border_layer: Line2D[]           # country borders
├── _resource_layer: Node2D           # resource icons (Sprite2D per deposit)
├── _unit_layer: Node2D               # unit sprites
└── _overlay_layers: Dictionary       # named toggleable overlays (heat maps etc.)

func set_base_mode(mode: String):     # "political" or "terrain"
func toggle_layer(layer: String):     # toggle any named overlay on/off
```

Heat map overlays are generated dynamically as a canvas layer drawn over the base map — each country's polygon filled with a color derived from its current data value (GDP, stability, etc.).

---

Estimated Godot scenes: ~25  
Estimated GDScript files: ~35  
Map data pipeline: 1 Python script (~300 lines)
