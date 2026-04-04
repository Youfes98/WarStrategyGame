## AISystem.gd
## Autoload — AI decision loop for all non-player countries.
## AI actively fights wars: moves armies toward enemies, attacks, builds military.
extends Node

const PEACE_WEIGHTS: Dictionary = {
	"idle":              30,
	"build_military":    10,
	"build_buildings":   15,
	"invest_infra":      15,
	"diplomatic_drift":  10,
	"stability_focus":   10,
	"aggressive_posture": 5,
	"trade_outreach":     5,
}

const WAR_WEIGHTS: Dictionary = {
	"war_operations":    50,
	"build_military":    25,
	"build_buildings":    5,
	"stability_focus":   10,
	"idle":               5,
	"invest_infra":       5,
}


func _ready() -> void:
	GameClock.tick_month.connect(_on_month)


func _on_month(_date: Dictionary) -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	for iso: String in GameState.countries:
		if iso == player:
			continue
		_ai_turn(iso)


func _ai_turn(iso: String) -> void:
	var data: Dictionary = GameState.countries[iso]
	var at_war: bool = _is_at_war(iso)

	# Pick weights based on war state
	var weights: Dictionary = WAR_WEIGHTS.duplicate() if at_war else PEACE_WEIGHTS.duplicate()

	# Situational adjustments
	var stability: float = float(data.get("stability", 50))
	var treasury: float = float(data.get("treasury", 0))

	if stability < 30:
		weights["stability_focus"] = weights.get("stability_focus", 10) + 30
		weights["aggressive_posture"] = 0
	if treasury < 1.0:
		weights["build_military"] = maxi(0, weights.get("build_military", 0) - 10)
		weights["build_buildings"] = maxi(0, weights.get("build_buildings", 0) - 10)

	var action: String = _weighted_pick(weights)

	match action:
		"war_operations":
			_do_war_operations(iso, data)
		"build_military":
			_do_build_military(iso, data)
		"build_buildings":
			_do_build_buildings(iso, data)
		"invest_infra":
			_do_invest_infra(iso, data)
		"stability_focus":
			_do_stability_focus(iso, data)
		"diplomatic_drift":
			_do_diplomatic_drift(iso)
		"aggressive_posture":
			_do_aggressive_posture(iso, data)
		"trade_outreach":
			_do_trade_outreach(iso)

	# During war: always try to move idle armies (on top of chosen action)
	if at_war:
		_do_war_operations(iso, data)


# ── War Operations ───────────────────────────────────────────────────────────

func _do_war_operations(iso: String, _data: Dictionary) -> void:
	var enemies: Array = _get_enemies(iso)
	if enemies.is_empty():
		return

	# Find all idle armies (units not currently moving)
	var idle_armies: Dictionary = {}  # army_id → location
	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.owner != iso:
			continue
		if not (u.get("path", []) as Array).is_empty():
			continue  # Already moving
		var aid: String = u.get("army_id", "")
		if not idle_armies.has(aid):
			idle_armies[aid] = u.location

	# Move each idle army toward nearest enemy territory
	for aid: String in idle_armies:
		var loc: String = idle_armies[aid]
		var target: String = _find_nearest_enemy_province(loc, enemies, iso)
		if target.is_empty():
			continue
		var domain: String = MilitarySystem._get_army_domain(aid)
		var path: Array = MilitarySystem.find_path(loc, target, iso, domain)
		if not path.is_empty():
			MilitarySystem._order_army_move(aid, path)


func _find_nearest_enemy_province(from: String, enemies: Array, mover_iso: String) -> String:
	# BFS from current location to find nearest province owned by an enemy
	var visited: Dictionary = {from: true}
	var frontier: Array = [from]
	for _dist: int in range(20):  # Max search depth
		var next_frontier: Array = []
		for pid: String in frontier:
			for nb: String in ProvinceDB.get_neighbors(pid):
				if visited.has(nb):
					continue
				visited[nb] = true
				var ter_owner: String = GameState.territory_owner.get(nb, ProvinceDB.get_parent_iso(nb))
				if ter_owner in enemies:
					return nb
				next_frontier.append(nb)
		frontier = next_frontier
	return ""  # No reachable enemy


# ── Military Building ────────────────────────────────────────────────────────

func _do_build_military(iso: String, data: Dictionary) -> void:
	var treasury: float = float(data.get("treasury", 0.0))
	var tier: String = data.get("power_tier", "D")

	# Pick unit type based on tier, buildings, and what's available
	var bs: Node = get_node_or_null("/root/BuildingSystem")
	var types_to_try: Array = ["infantry"]

	# Check what buildings exist
	if bs != null:
		if bs.country_has_building(iso, "factory"):
			if tier in ["S", "A"] and randf() < 0.3:
				types_to_try = ["armor"]
			elif randf() < 0.2:
				types_to_try = ["artillery"]
		if bs.country_has_building(iso, "airfield") and randf() < 0.15:
			types_to_try = ["fighter"]
		if bs.country_has_building(iso, "naval_yard") and randf() < 0.15:
			types_to_try = ["destroyer"]

	for type_key: String in types_to_try:
		var cost: float = float(MilitarySystem.UNIT_TYPES[type_key].get("cost", 0.5))
		if treasury >= cost:
			data["treasury"] = treasury - cost
			# Find appropriate spawn location
			var loc: String = _find_recruit_location(iso, type_key, bs)
			if not loc.is_empty():
				MilitarySystem.spawn_unit(type_key, iso, loc)
			break


func _find_recruit_location(iso: String, unit_type: String, bs: Node) -> String:
	if bs == null:
		return ProvinceDB.get_main_province(iso)
	# Find a province with the right building
	for btype: String in bs.BUILDING_TYPES:
		var bdef: Dictionary = bs.BUILDING_TYPES[btype]
		if unit_type in bdef.get("unlocks_recruit", []):
			var provs: Array = bs.get_provinces_with_building(iso, btype)
			if not provs.is_empty():
				return provs[randi() % provs.size()]
	return ProvinceDB.get_main_province(iso)


# ── Building Construction ────────────────────────────────────────────────────

func _do_build_buildings(iso: String, data: Dictionary) -> void:
	var bs: Node = get_node_or_null("/root/BuildingSystem")
	if bs == null:
		return
	var treasury: float = float(data.get("treasury", 0.0))
	if treasury < 0.5:
		return

	# Priority: barracks > factory > airfield > naval yard (if coastal)
	var needs: Array = []
	if not bs.country_has_building(iso, "barracks"):
		needs.append("barracks")
	if not bs.country_has_building(iso, "factory"):
		needs.append("factory")
	if not bs.country_has_building(iso, "airfield"):
		needs.append("airfield")
	var coast: String = ProvinceDB.get_nearest_coast(iso)
	if not coast.is_empty() and not bs.country_has_building(iso, "naval_yard"):
		needs.append("naval_yard")
	# Economic buildings
	if randf() < 0.3:
		needs.append("civilian_factory")
	if randf() < 0.2:
		needs.append("hospital")

	for btype: String in needs:
		var bdef: Dictionary = bs.BUILDING_TYPES.get(btype, {})
		var cost: float = bdef.get("cost", 999.0)
		if treasury < cost:
			continue
		var ranked: Array = bs.get_ranked_provinces(btype, iso)
		if ranked.is_empty():
			continue
		var target_pid: String = ranked[0]["pid"]
		if bs.start_build(btype, target_pid, iso):
			break  # One build per turn


# ── Other Actions (mostly unchanged) ─────────────────────────────────────────

func _do_invest_infra(_iso: String, data: Dictionary) -> void:
	var infra: int = int(data.get("infrastructure", 30))
	var treasury: float = float(data.get("treasury", 0.0))
	var invest_cost: float = 0.5
	if treasury >= invest_cost and infra < 95:
		data["infrastructure"] = mini(95, infra + randi_range(1, 3))
		data["treasury"] = treasury - invest_cost


func _do_stability_focus(_iso: String, data: Dictionary) -> void:
	var stab: float = float(data.get("stability", 50))
	data["stability"] = minf(95.0, stab + randf_range(1.0, 4.0))


func _do_diplomatic_drift(iso: String) -> void:
	var neighbors: Array = ProvinceDB.adjacencies.get(iso, [])
	if neighbors.is_empty():
		return
	var target: String = neighbors[randi() % neighbors.size()]
	var rel: Dictionary = GameState.get_relation(iso, target)
	rel["diplomatic_score"] = int(rel.get("diplomatic_score", 0)) + randi_range(1, 5)


func _do_aggressive_posture(iso: String, data: Dictionary) -> void:
	var tier: String = data.get("power_tier", "D")
	if tier in ["D", "C"]:
		return
	var neighbors: Array = ProvinceDB.adjacencies.get(iso, [])
	for nb: String in neighbors:
		if nb == GameState.player_iso:
			continue
		if GameState.is_at_war(iso, nb):
			continue
		var nb_data: Dictionary = GameState.get_country(nb)
		var nb_tier: String = nb_data.get("power_tier", "C")
		if _tier_rank(tier) >= _tier_rank(nb_tier) + 2:
			if randf() < 0.15:
				GameState.set_war(iso, nb, true)
				return


func _do_trade_outreach(iso: String) -> void:
	var neighbors: Array = ProvinceDB.adjacencies.get(iso, [])
	if neighbors.is_empty():
		return
	var target: String = neighbors[randi() % neighbors.size()]
	var rel: Dictionary = GameState.get_relation(iso, target)
	rel["trade_volume"] = float(rel.get("trade_volume", 0.0)) + randf_range(0.5, 3.0)
	rel["diplomatic_score"] = int(rel.get("diplomatic_score", 0)) + 1


# ── Helpers ──────────────────────────────────────────────────────────────────

func _is_at_war(iso: String) -> bool:
	for other: String in GameState.countries:
		if GameState.is_at_war(iso, other):
			return true
	return false


func _get_enemies(iso: String) -> Array:
	var enemies: Array = []
	for other: String in GameState.countries:
		if GameState.is_at_war(iso, other):
			enemies.append(other)
	return enemies


func _tier_rank(tier: String) -> int:
	match tier:
		"S": return 5
		"A": return 4
		"B": return 3
		"C": return 2
		_:   return 1


func _weighted_pick(weights: Dictionary) -> String:
	var total: int = 0
	for w: int in weights.values():
		total += maxi(0, w)
	if total <= 0:
		return "idle"
	var roll: int = randi() % total
	var cumulative: int = 0
	for act: String in weights:
		cumulative += maxi(0, weights[act])
		if roll < cumulative:
			return act
	return "idle"
