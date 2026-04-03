## BuildingSystem.gd
## Autoload — manages province-level buildings, construction queues, and effects.
## Victoria 3-style: click building type → see ranked provinces → place it.
extends Node

signal building_completed(province_id: String, building_type: String)
signal construction_started(province_id: String, building_type: String)
signal construction_cancelled(province_id: String, building_type: String)

# ── Building Type Definitions ─────────────────────────────────────────────────
# category: "military", "economic", "infrastructure", "research", "special"
# requires_coastal: must be on a coastal province
# requires_capital: must be on capital province
# unlocks_recruit: unit types this building enables for recruitment

const BUILDING_TYPES: Dictionary = {
	"barracks": {
		"label": "Barracks", "category": "military",
		"cost": 0.3, "build_months": 2,
		"description": "Enables infantry recruitment at this province.",
		"unlocks_recruit": ["infantry"],
	},
	"factory": {
		"label": "Military Factory", "category": "military",
		"cost": 1.5, "build_months": 4,
		"description": "Enables armor and artillery production.",
		"unlocks_recruit": ["armor", "artillery"],
	},
	"naval_yard": {
		"label": "Naval Yard", "category": "military",
		"cost": 2.0, "build_months": 4, "requires_coastal": true,
		"description": "Enables naval unit construction. Must be coastal.",
		"unlocks_recruit": ["destroyer", "submarine", "carrier", "transport"],
	},
	"airfield": {
		"label": "Airfield", "category": "military",
		"cost": 1.8, "build_months": 3,
		"description": "Enables fighter, bomber, and drone deployment.",
		"unlocks_recruit": ["fighter", "bomber", "drone"],
	},
	"bunker": {
		"label": "Bunker", "category": "military",
		"cost": 0.8, "build_months": 3,
		"description": "+30% defense bonus for this province.",
		"defense_bonus": 0.3,
	},
	"port": {
		"label": "Trade Port", "category": "economic",
		"cost": 1.0, "build_months": 3, "requires_coastal": true,
		"description": "Increases trade income. Enables sea supply lines.",
		"gdp_bonus": 0.0003,
	},
	"civilian_factory": {
		"label": "Civilian Factory", "category": "economic",
		"cost": 2.0, "build_months": 5,
		"description": "Boosts national GDP growth.",
		"gdp_bonus": 0.0005,
	},
	"power_plant": {
		"label": "Power Plant", "category": "economic",
		"cost": 3.0, "build_months": 6,
		"description": "Boosts all building output in this province.",
		"output_multiplier": 1.2,
	},
	"university": {
		"label": "University", "category": "research",
		"cost": 2.5, "build_months": 6,
		"description": "Generates research points each month.",
		"research_points": 1,
	},
	"hospital": {
		"label": "Hospital", "category": "infrastructure",
		"cost": 0.8, "build_months": 3,
		"description": "Improves population growth and stability.",
		"stability_bonus": 0.5, "pop_growth_bonus": 0.001,
	},
	"school": {
		"label": "School", "category": "infrastructure",
		"cost": 0.5, "build_months": 2,
		"description": "Increases literacy and stability.",
		"stability_bonus": 0.2, "literacy_bonus": 0.1,
	},
	"intelligence_hq": {
		"label": "Intelligence HQ", "category": "special",
		"cost": 4.0, "build_months": 6, "requires_capital": true,
		"description": "Enables espionage operations. Capital only.",
	},
}

# Max simultaneous constructions scales with GDP
const BASE_MAX_QUEUE: int = 2
const GDP_PER_EXTRA_SLOT: float = 5000.0  # +1 slot per $5T GDP

# Terrain build speed modifiers
const TERRAIN_BUILD_SPEED: Dictionary = {
	"plains": 1.0, "forest": 0.85, "desert": 0.8,
	"mountain": 0.6, "jungle": 0.7, "tundra": 0.75,
}

# Starting buildings by power tier
const STARTING_BUILDINGS: Dictionary = {
	"S": [
		["barracks", 3], ["factory", 2], ["naval_yard", 2],
		["airfield", 2], ["university", 1], ["hospital", 2],
		["civilian_factory", 2], ["port", 1],
	],
	"A": [
		["barracks", 2], ["factory", 1], ["naval_yard", 1],
		["airfield", 1], ["university", 1], ["hospital", 1],
	],
	"B": [["barracks", 1], ["factory", 1]],
	"C": [["barracks", 1]],
	"D": [],
}


func _ready() -> void:
	GameClock.tick_month.connect(_on_month)
	GameState.player_country_set.connect(_on_player_set)


func _on_player_set(_iso: String) -> void:
	# Seed buildings for all countries on first game start
	if GameState.province_buildings.is_empty():
		_seed_starting_buildings()


func _on_month(_date: Dictionary) -> void:
	_advance_construction()
	# Building effects are applied by EconomySystem (it calls get_building_effects)


# ── Public API ────────────────────────────────────────────────────────────────

## Get all buildings at a province.
func get_buildings_at(province_id: String) -> Array:
	return GameState.province_buildings.get(province_id, [])


## Check if a province has a specific building type.
func has_building(province_id: String, building_type: String) -> bool:
	for b: Dictionary in get_buildings_at(province_id):
		if b.get("type", "") == building_type:
			return true
	return false


## Check if any province owned by country has a specific building.
func country_has_building(country_iso: String, building_type: String) -> bool:
	for pid: String in ProvinceDB.get_country_province_ids(country_iso):
		if GameState.territory_owner.get(pid, ProvinceDB.get_parent_iso(pid)) == country_iso:
			if has_building(pid, building_type):
				return true
	return false


## Find provinces with a specific building owned by a country.
func get_provinces_with_building(country_iso: String, building_type: String) -> Array:
	var result: Array = []
	for pid: String in ProvinceDB.get_country_province_ids(country_iso):
		if GameState.territory_owner.get(pid, ProvinceDB.get_parent_iso(pid)) == country_iso:
			if has_building(pid, building_type):
				result.append(pid)
	return result


## Can this building type be built at this province?
func can_build(building_type: String, province_id: String, country_iso: String) -> bool:
	var bdef: Dictionary = BUILDING_TYPES.get(building_type, {})
	if bdef.is_empty():
		return false
	# Ownership check
	var ter_owner: String = GameState.territory_owner.get(province_id, ProvinceDB.get_parent_iso(province_id))
	if ter_owner != country_iso:
		return false
	# Coastal requirement
	if bdef.get("requires_coastal", false) and not ProvinceDB.is_coastal(province_id):
		return false
	# Capital requirement
	if bdef.get("requires_capital", false):
		if province_id != ProvinceDB.get_capital_province(country_iso):
			return false
	# Already has this building?
	if has_building(province_id, building_type):
		return false
	# Already in construction queue?
	for item: Dictionary in GameState.construction_queue.get(country_iso, []):
		if item.get("province", "") == province_id and item.get("type", "") == building_type:
			return false
	# Treasury check
	var treasury: float = float(GameState.get_country(country_iso).get("treasury", 0.0))
	if treasury < bdef.get("cost", 999.0):
		return false
	# Queue capacity
	var queue: Array = GameState.construction_queue.get(country_iso, [])
	var max_queue: int = _get_max_queue(country_iso)
	if queue.size() >= max_queue:
		return false
	return true


## Start building construction.
func start_build(building_type: String, province_id: String, country_iso: String) -> bool:
	if not can_build(building_type, province_id, country_iso):
		return false
	var bdef: Dictionary = BUILDING_TYPES[building_type]
	var cost: float = bdef.get("cost", 1.0)

	# Deduct cost from treasury
	var data: Dictionary = GameState.get_country(country_iso)
	data["treasury"] = float(data.get("treasury", 0.0)) - cost

	# Add to construction queue
	if not GameState.construction_queue.has(country_iso):
		GameState.construction_queue[country_iso] = []
	(GameState.construction_queue[country_iso] as Array).append({
		"province": province_id,
		"type": building_type,
		"progress": 0.0,
		"cost": cost,
	})

	construction_started.emit(province_id, building_type)
	var pname: String = ProvinceDB.province_data.get(province_id, {}).get("name", province_id)
	if country_iso == GameState.player_iso:
		UIManager.push_notification(
			"Construction started: %s in %s" % [bdef["label"], pname], "info")
	return true


## Cancel a construction in progress. Refunds 50%.
func cancel_build(country_iso: String, queue_index: int) -> void:
	var queue: Array = GameState.construction_queue.get(country_iso, [])
	if queue_index < 0 or queue_index >= queue.size():
		return
	var item: Dictionary = queue[queue_index]
	var refund: float = item.get("cost", 0.0) * 0.5
	GameState.get_country(country_iso)["treasury"] = \
		float(GameState.get_country(country_iso).get("treasury", 0.0)) + refund
	var pid: String = item.get("province", "")
	var btype: String = item.get("type", "")
	queue.remove_at(queue_index)
	construction_cancelled.emit(pid, btype)
	if country_iso == GameState.player_iso:
		UIManager.push_notification("Construction cancelled. 50%% refunded.", "info")


## Get construction queue for a country.
func get_queue(country_iso: String) -> Array:
	return GameState.construction_queue.get(country_iso, [])


## Province suitability score for a building type (Victoria 3 style ranking).
func get_province_score(building_type: String, province_id: String, country_iso: String) -> float:
	var bdef: Dictionary = BUILDING_TYPES.get(building_type, {})
	if bdef.is_empty():
		return 0.0
	var cdata: Dictionary = GameState.get_country(country_iso)
	var infra: float = float(cdata.get("infrastructure", 50)) / 100.0
	var stab: float = float(cdata.get("stability", 50)) / 100.0

	# Terrain factor
	var terrain: String = ProvinceDB.get_province_terrain(province_id)
	var terrain_score: float = TERRAIN_BUILD_SPEED.get(terrain, 0.8)

	# Coastal bonus (only matters for coastal buildings)
	var coastal_score: float = 0.0
	if bdef.get("requires_coastal", false) and ProvinceDB.is_coastal(province_id):
		coastal_score = 1.0
	elif not bdef.get("requires_coastal", false):
		coastal_score = 0.5  # neutral

	# Population weight (approximate: distribute country pop evenly across provinces)
	var prov_count: int = maxi(ProvinceDB.get_country_province_ids(country_iso).size(), 1)
	var pop: float = float(cdata.get("population", 100000)) / float(prov_count)
	var pop_score: float = clampf(pop / 5_000_000.0, 0.0, 1.0)

	# Already has many buildings? Lower priority (spread them out)
	var existing: int = get_buildings_at(province_id).size()
	var spread_penalty: float = maxf(0.0, 1.0 - existing * 0.15)

	return (pop_score * 0.25 + infra * 0.25 + stab * 0.2
			+ terrain_score * 0.15 + coastal_score * 0.1) * spread_penalty


## Get ranked provinces for a building type (best first).
func get_ranked_provinces(building_type: String, country_iso: String) -> Array:
	var ranked: Array = []
	for pid: String in ProvinceDB.get_country_province_ids(country_iso):
		if GameState.territory_owner.get(pid, ProvinceDB.get_parent_iso(pid)) != country_iso:
			continue
		if not can_build(building_type, pid, country_iso):
			continue
		var score: float = get_province_score(building_type, pid, country_iso)
		ranked.append({"pid": pid, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"])
	return ranked


## Get aggregated building effects for a country (called by EconomySystem).
func get_building_effects(country_iso: String) -> Dictionary:
	var effects: Dictionary = {
		"gdp_bonus": 0.0,
		"stability_bonus": 0.0,
		"pop_growth_bonus": 0.0,
		"literacy_bonus": 0.0,
		"research_points": 0,
		"defense_provinces": {},  # pid → bonus multiplier
	}
	for pid: String in ProvinceDB.get_country_province_ids(country_iso):
		if GameState.territory_owner.get(pid, ProvinceDB.get_parent_iso(pid)) != country_iso:
			continue
		var buildings: Array = get_buildings_at(pid)
		var has_power: bool = false
		for b: Dictionary in buildings:
			if b.get("type", "") == "power_plant":
				has_power = true
				break
		var output_mult: float = 1.2 if has_power else 1.0

		for b: Dictionary in buildings:
			var btype: String = b.get("type", "")
			var bdef: Dictionary = BUILDING_TYPES.get(btype, {})
			effects["gdp_bonus"] += bdef.get("gdp_bonus", 0.0) * output_mult
			effects["stability_bonus"] += bdef.get("stability_bonus", 0.0) * output_mult
			effects["pop_growth_bonus"] += bdef.get("pop_growth_bonus", 0.0) * output_mult
			effects["literacy_bonus"] += bdef.get("literacy_bonus", 0.0) * output_mult
			effects["research_points"] += int(bdef.get("research_points", 0))
			if bdef.has("defense_bonus"):
				effects["defense_provinces"][pid] = 1.0 + bdef.get("defense_bonus", 0.0)
	return effects


# ── Private ───────────────────────────────────────────────────────────────────

func _get_max_queue(country_iso: String) -> int:
	var gdp: float = float(GameState.get_country(country_iso).get("gdp_raw_billions", 1.0))
	return BASE_MAX_QUEUE + int(gdp / GDP_PER_EXTRA_SLOT)


func _advance_construction() -> void:
	for iso: String in GameState.construction_queue:
		var queue: Array = GameState.construction_queue[iso]
		var cdata: Dictionary = GameState.get_country(iso)
		var infra: float = float(cdata.get("infrastructure", 50)) / 100.0
		var stab: float = float(cdata.get("stability", 50)) / 100.0
		var speed_mod: float = (0.5 + infra * 0.5) * (0.7 + stab * 0.3)

		var completed: Array = []
		for i: int in queue.size():
			var item: Dictionary = queue[i]
			var btype: String = item.get("type", "")
			var bdef: Dictionary = BUILDING_TYPES.get(btype, {})
			var build_months: float = float(bdef.get("build_months", 3))
			var pid: String = item.get("province", "")
			var terrain: String = ProvinceDB.get_province_terrain(pid)
			var terrain_speed: float = TERRAIN_BUILD_SPEED.get(terrain, 0.8)

			item["progress"] = float(item.get("progress", 0.0)) + \
				(1.0 / build_months) * speed_mod * terrain_speed

			if float(item["progress"]) >= 1.0:
				completed.append(i)
				_complete_building(pid, btype, iso)

		# Remove completed items (reverse order to preserve indices)
		for i: int in range(completed.size() - 1, -1, -1):
			queue.remove_at(completed[i])


func _complete_building(province_id: String, building_type: String, country_iso: String) -> void:
	if not GameState.province_buildings.has(province_id):
		GameState.province_buildings[province_id] = []
	(GameState.province_buildings[province_id] as Array).append({
		"type": building_type,
		"level": 1,
	})
	building_completed.emit(province_id, building_type)
	var bdef: Dictionary = BUILDING_TYPES.get(building_type, {})
	var pname: String = ProvinceDB.province_data.get(province_id, {}).get("name", province_id)
	if country_iso == GameState.player_iso:
		UIManager.push_notification(
			"%s completed in %s!" % [bdef.get("label", building_type), pname], "info")


func _seed_starting_buildings() -> void:
	for iso: String in GameState.countries:
		var tier: String = GameState.get_country(iso).get("power_tier", "D")
		var specs: Array = STARTING_BUILDINGS.get(tier, [])
		if specs.is_empty():
			continue

		var provinces: Array = ProvinceDB.get_country_province_ids(iso)
		if provinces.is_empty():
			continue
		var capital: String = ProvinceDB.get_capital_province(iso)

		# Find coastal provinces for naval buildings
		var coastal: Array = []
		for pid: String in provinces:
			if ProvinceDB.is_coastal(pid):
				coastal.append(pid)

		var prov_idx: int = 0
		for spec: Array in specs:
			var btype: String = spec[0]
			var count: int = spec[1]
			var bdef: Dictionary = BUILDING_TYPES.get(btype, {})
			var needs_coast: bool = bdef.get("requires_coastal", false)
			var needs_capital: bool = bdef.get("requires_capital", false)

			for _i: int in count:
				var target: String = ""
				if needs_capital:
					target = capital
				elif needs_coast and not coastal.is_empty():
					target = coastal[prov_idx % coastal.size()]
				else:
					# Spread across provinces starting from capital
					if prov_idx == 0:
						target = capital
					else:
						target = provinces[prov_idx % provinces.size()]
				prov_idx += 1

				if target.is_empty():
					continue
				# Place building directly (no construction time for starting buildings)
				if not GameState.province_buildings.has(target):
					GameState.province_buildings[target] = []
				if not has_building(target, btype):
					(GameState.province_buildings[target] as Array).append({
						"type": btype, "level": 1,
					})

	print("BuildingSystem: Seeded starting buildings for %d countries" % GameState.countries.size())
