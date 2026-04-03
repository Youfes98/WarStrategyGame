# War Strategy Game — Claude Context

## What This Is
A real-time grand strategy game built in **Godot 4.6 (GDScript)**, targeting **Steam**.
Setting: modern **2026**, real world map, current geopolitics.
Inspired by: Hearts of Iron 4, Victoria 3, Call of War, Age of History 3.

---

## Engine & Architecture
- **Godot 4.6**, GDScript for everything now, GDExtension/C++ boundary left open for heavy systems later
- Heavy systems (pathfinding, combat, AI, map renderer) sit behind clean callable interfaces — pure functions, no internal state — so they can be swapped to C++ without touching callers
- **Multi-rate tick system** via `GameClock` autoload: hour/day/week/month/year signals. Systems subscribe to what they need. Never use `Engine.time_scale` — use `GameClock.speed_multiplier` instead
- **8 autoloads**: `GameClock`, `GameState`, `UIManager`, `WorldMemoryDB`, `ProvinceDB`, `MilitarySystem`, `AISystem`, `SaveSystem`

## Map
- Real world map, **8192×4096px** (doubled resolution)
- **4584 sub-national provinces** from Natural Earth admin-1 data
- Province click detection via **pixel-color bitmap** (`provinces.png`) — O(1) lookup
- **GPU shader rendering**: single `map.gdshader` handles terrain + country overlay + elevation shading + coast glow + noise + borders. 3 Sprite2D tiles for seamless horizontal wrapping (endless map)
- **Layered rendering**: terrain base (Natural Earth raster) → country colour overlay (LUT) → elevation shading (heightmap) → coast glow → noise → province/country borders
- Labels: zoom-responsive, overlap-rejected, priority-sorted by country size
- **Toggleable overlay layers**: Economy, Military, Sphere of Influence, Stability, Debt, Resources, etc.
- Terrain types affect gameplay: mountains = +40% defense, jungle = 40% movement, etc.
- Real resource data (oil, minerals, rare earths, farmland) from USGS/FAO seeded at real coordinates

## Data Pipeline (tools/)
- `fetch_country_data.py` → downloads 195 countries from REST Countries API, normalises values
- `geojson_to_godot.py` → downloads Natural Earth GeoJSON, builds `provinces.png` + polygon data
- Output: `data/countries.json`, `data/adjacencies.json`, `assets/map/provinces.png`
- **Normalisation**: real GDP ($0.05B–$28T) log-compressed to 1–1000 scale. Players see labels not raw numbers.

---

## Core Design Pillars

### Freedom of Play — War Is Optional
Five equal paths to dominance:
1. **Military** — conquest, occupation, nuclear deterrence
2. **Economic** — loans, debt traps, own foreign infrastructure
3. **Soft Power** — cultural influence, media, foreign aid
4. **Diplomatic** — alliances, puppets, UN voting blocs
5. **Development** — grow GDP, industrialise, become a regional hub

### Country Power Tiers (S/A/B/C/D)
Seeded from real 2026 data. USA = S tier (easy). Somalia = D tier (hard mode). Dynamic: if a weak nation grows powerful, great powers start applying pressure (sanctions, proxy wars).

### No Forced Victory Condition
Players set their own goals.

---

## Systems (all planned, building progressively)

### Economy
- Real GDP/debt/infrastructure per country, log-normalised
- Monthly tick: GDP growth, tax revenue, stability, inflation
- Player actions: build infrastructure, fund education, industrialise, take/give loans
- Debt system: high debt-to-GDP → credit downgrade → default → stability crash

### Soft Power & Diplomacy
- Loans, infrastructure investment, trade deals, cultural influence
- **Leverage**: own their ports / hold their debt = coerce without war
- Diplomatic actions: offer loan, invest, sanction, embargo coalition, support opposition

### Technology — Organic R&D (NOT a tech tree)
- Build universities, labs, institutes → generate **research points** in domains
- Points accumulate → **breakthrough fires** → game draws RANDOMLY from domain's possibility pool
- You never pick what you get. More investment = better odds at rarer techs. Never guaranteed.
- **Secret programs** (Black Sites) = only way to target a specific tech deliberately. Hidden from other nations.
- Serendipity: cross-domain discoveries possible (energy research accidentally unlocks aerospace)
- Brain drain: instability/low wages → scientists emigrate. Poach via Talent Visa Program.
- Tech diffusion: nothing stays exclusive forever. Export controls slow spread.

### Military Command
- Full command hierarchy: Head of State → Minister of Defense → Theater Commanders → Army Commanders
- **Commanders are named characters with traits** (Aggressive, Cautious, Opportunist, Defensive Specialist, etc.)
- MoD issues strategic directives, player approves/modifies/rejects
- AI executes autonomously — player can override any order at any time or go full manual
- Traits earned from battles, training (Military Academy building), mentorship
- Low commander loyalty → resignation, defection, or coup

### Units (2026 Modern)
Infantry, Armor, Artillery, Fighter Jets, Stealth Bombers, Drones, Destroyers, Submarines, Carriers, ICBMs

### Internal Governance
- **Government types**: Presidential Democracy, Parliamentary, Constitutional Monarchy, Absolute Monarchy, Authoritarian, One-Party, Military Junta, Theocracy — seeded from real 2026 data
- **Cabinet**: named characters you appoint from a visible candidate pool. Traits: Competent, Corrupt, Loyal, Charismatic, Reformist, Old Guard, etc.
- **Elections**: approval rating affects result. Player can campaign, make promises, rig (authoritarian only)
- **Taxes**: 3 levels — Auto (one-click), Sliders (3 rates), Sector breakdown
- **Buildings**: Economic, Infrastructure, Social, Military, Research — construction queue with Auto-Build option
- **Political Capital**: resource from approval + stability, spent on major decisions

### Advanced Systems
- **Gray Zone Conflict**: fund militias, trigger unrest, sabotage, election interference — all deniable. Opponent can expose (huge diplomatic hit), counter-fund, or ignore.
- **National Identity Drift**: 5 axes (Globalist↔Nationalist, Democratic↔Authoritarian, Secular↔Religious, Open↔Protectionist, Progressive↔Conservative). Shifts slowly from policies, foreign influence, crises.
- **Leader Relationships**: personal grudges, betrayal memory, crisis bonds — separate from country-to-country relations. Persist until leader leaves power.
- **Narrative Warfare**: domestic and global narrative scores. Control perception = control outcomes. Lose a war but run good media → population still supports you.
- **Escalation Ladder**: 0 (Peace) → 1 (Tensions) → 2 (Proxy) → 3 (Limited Strikes) → 4 (Full War) → 5 (Total War) → 6 (Nuclear Threshold). Both sides play chicken. Backing down costs prestige.
- **World Events**: semi-random but logically triggered. Global recession, pandemic, oil shock, breakaway regions. The world hits back.
- **Black Swan Events**: rare but probability-weighted by conditions. Mutiny = 1% base × 5 if morale low × 6 if losing war. Never purely random. Player gets meaningful choices.
- **Advisors Who Disagree**: ministers run real game models to assess decisions. Finance minister warns war will bankrupt you in 18 months — with actual numbers. Fire too many advisors → sycophant cabinet → nobody warns you → Black Swan risk climbs.
- **Long-Term Consequences & World Memory**: every significant action writes a memory record with weight + decay rate. Betrayal = remembered years. Using nukes = permanent. New leader inherits 60% of memories. Ripple effects are automatic (betray ally → all allies start hedging).

---

## UI/UX — Progressive Disclosure
**Never show a system before the player has a reason to care about it.**
- Game starts with almost nothing: map, country card, pause/speed controls
- Systems unlock when triggered: first month → economy bar. First foreign click → diplomacy. Build university → research panel. War declared → military command.
- `UIManager` singleton manages panel states: HIDDEN → MINIMAL → FULL
- Notification feed (right side) is the primary teacher — surfaces problems with [View] buttons that open panels for the first time

---

## Current Build Status
- Phase 1–3 complete: map rendering, province click detection, country card, game clock, speed controls, notification feed, all autoloads
- **CountryPicker** (game start screen): searchable list, tier/stats preview, sets player_iso, releases clock
- **EconomySystem**: monthly GDP growth, stability drift, debt interest, instability auto-pause events
- **Main.gd**: clock stays paused until player confirms country
- Data pipeline working (countries.json + provinces.png generated)
- Next: Phase 4 — military units, adjacency graph, movement orders + Phase 5 combat
