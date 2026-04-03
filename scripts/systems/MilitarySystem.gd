## MilitarySystem.gd
## Autoload — manages units, movement, combat, and army operations.
## Features: BFS pathfinding, movement queues, army splitting, province recruitment,
## multi-army selection (box select + shift-click), multi-army move orders.
extends Node

signal units_changed()
signal territory_selected(iso: String)
signal selection_changed()
signal battle_resolved(territory_iso: String, attacker_iso: String, defender_iso: String, attacker_won: bool)

## domain: "land" = moves on land provinces, "sea" = moves on ocean, "air" = range-based
const UNIT_TYPES: Dictionary = {
	# ── LAND (brigade-level, 2026 costs in $B) ──
	"infantry":  {"label": "Infantry",    "domain": "land", "travel_days": 3, "cost": 0.5,  "upkeep": 0.02, "power": 10, "sprite": "infantry"},
	"armor":     {"label": "Armor",       "domain": "land", "travel_days": 2, "cost": 3.0,  "upkeep": 0.08, "power": 25, "sprite": "armor"},
	"artillery": {"label": "Artillery",   "domain": "land", "travel_days": 4, "cost": 1.2,  "upkeep": 0.04, "power": 18, "sprite": "artillery"},
	# ── NAVAL (ship-level) ──
	"destroyer": {"label": "Destroyer",   "domain": "sea",  "travel_days": 1, "cost": 1.8,  "upkeep": 0.06, "power": 20, "sprite": "destroyer"},
	"submarine": {"label": "Submarine",   "domain": "sea",  "travel_days": 2, "cost": 3.5,  "upkeep": 0.10, "power": 22, "sprite": "submarine"},
	"carrier":   {"label": "Carrier",     "domain": "sea",  "travel_days": 1, "cost": 13.0, "upkeep": 0.35, "power": 30, "sprite": "carrier"},
	"transport": {"label": "Transport",   "domain": "sea",  "travel_days": 2, "cost": 0.8,  "upkeep": 0.03, "power": 2,  "sprite": "transport", "capacity": 5},
	# ── AIR (squadron-level) ──
	"fighter":   {"label": "Fighter Jet", "domain": "air",  "travel_days": 0, "cost": 2.5,  "upkeep": 0.08, "power": 15, "sprite": "fighter",  "range": 8},
	"bomber":    {"label": "Bomber",      "domain": "air",  "travel_days": 0, "cost": 5.0,  "upkeep": 0.15, "power": 30, "sprite": "bomber",   "range": 6},
	"drone":     {"label": "Drone",       "domain": "air",  "travel_days": 0, "cost": 0.3,  "upkeep": 0.01, "power": 8,  "sprite": "drone",    "range": 10},
}

const STARTING_UNITS: Dictionary = {
	"S": [["infantry", 5], ["armor", 3], ["artillery", 2], ["destroyer", 2], ["fighter", 2]],
	"A": [["infantry", 4], ["armor", 2], ["artillery", 1], ["destroyer", 1], ["fighter", 1]],
	"B": [["infantry", 3], ["armor", 1]],
	"C": [["infantry", 2]],
	"D": [["infantry", 1]],
}

## Terrain movement cost multipliers (Dijkstra weights)
const TERRAIN_MOVE_COST: Dictionary = {
	"plains": 1.0, "forest": 1.3, "desert": 1.5,
	"mountain": 2.0, "jungle": 1.8, "tundra": 1.5,
}

## Terrain defense multipliers (applied to defender power)
const TERRAIN_DEFENSE: Dictionary = {
	"plains": 1.0, "forest": 1.2, "desert": 0.9,
	"mountain": 1.5, "jungle": 1.3, "tundra": 1.1,
}

## Supply distance thresholds
const SUPPLY_FULL:     int = 3   # provinces from owned territory — no penalty
const SUPPLY_LOW:      int = 6   # reduced supply
const SUPPLY_CRITICAL: int = 9   # critical
# Beyond SUPPLY_CRITICAL = starvation

var units:             Dictionary    = {}
var selected_iso:      String        = ""
var selected_army_ids: Array[String] = []
var recruit_iso:       String        = ""
var _next_id:          int           = 1
var _next_army_id:     int           = 1

var selected_army_id: String:
	get:
		if selected_army_ids.is_empty():
			return ""
		return selected_army_ids[0]


func _ready() -> void:
	GameState.player_country_set.connect(_on_player_set)
	GameClock.tick_day.connect(_on_day)


func _on_player_set(iso: String) -> void:
	var tier: String = GameState.get_country(iso).get("power_tier", "C")
	var army_id: String = _new_army_id()
	var spawn_loc: String = _find_home_province(iso)
	for entry: Array in STARTING_UNITS.get(tier, [["infantry", 1]]):
		for _i: int in entry[1]:
			spawn_unit(entry[0], iso, spawn_loc, army_id)
	_spawn_ai_armies()
	units_changed.emit()


func _spawn_ai_armies() -> void:
	for ciso: String in GameState.countries:
		if ciso == GameState.player_iso:
			continue
		var tier: String = GameState.get_country(ciso).get("power_tier", "D")
		var army_id: String = _new_army_id()
		var spawn_loc: String = _find_home_province(ciso)
		for entry: Array in STARTING_UNITS.get(tier, [["infantry", 1]]):
			for _i: int in entry[1]:
				spawn_unit(entry[0], ciso, spawn_loc, army_id)


func spawn_unit(type: String, unit_owner: String, location: String, army_id: String = "") -> String:
	if army_id.is_empty():
		army_id = _new_army_id()
	var id: String = "u%04d" % _next_id
	_next_id += 1
	units[id] = {
		"id": id, "type": type, "owner": unit_owner,
		"location": location, "path": [],
		"days_remaining": 0, "strength": 100, "morale": 80,
		"army_id": army_id,
	}
	return id


func _find_home_province(country_iso: String) -> String:
	var provinces: Array = ProvinceDB.get_country_province_ids(country_iso)
	if provinces.is_empty():
		return country_iso
	var country_centroid: Vector2 = ProvinceDB.get_centroid(country_iso)
	if country_centroid == Vector2.ZERO:
		return provinces[0]
	var best_pid: String = provinces[0]
	var best_dist: float = INF
	for pid: String in provinces:
		var pc: Vector2 = ProvinceDB.get_centroid(pid)
		if pc == Vector2.ZERO:
			continue
		var d: float = pc.distance_squared_to(country_centroid)
		if d < best_dist:
			best_dist = d
			best_pid = pid
	return best_pid


func _new_army_id() -> String:
	var id: String = "a%04d" % _next_army_id
	_next_army_id += 1
	return id


func _get_army_location(army_id: String) -> String:
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id and (u.path as Array).is_empty():
			return u.location
	for id: String in units:
		if (units[id] as Dictionary).get("army_id", "") == army_id:
			return (units[id] as Dictionary).get("location", "")
	return ""


func _get_army_ids_at(iso: String, unit_owner: String) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	var parent: String = ProvinceDB.get_parent_iso(iso)
	for id: String in units:
		var u: Dictionary = units[id]
		if u.owner != unit_owner:
			continue
		if u.location == iso or u.location == parent:
			var aid: String = u.get("army_id", "")
			if not aid.is_empty() and not seen.has(aid):
				seen[aid] = true
				result.append(aid)
	return result


func _find_stationary_army(unit_owner: String, location: String) -> String:
	for id: String in units:
		var u: Dictionary = units[id]
		if u.owner == unit_owner and u.location == location and (u.path as Array).is_empty():
			return u.get("army_id", "")
	return ""


func _get_army_unit_ids(army_id: String) -> Array:
	var result: Array = []
	for id: String in units:
		if (units[id] as Dictionary).get("army_id", "") == army_id:
			result.append(id)
	return result


func _get_army_travel_days(army_id: String) -> int:
	var slowest: int = 1
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id:
			var td: int = UNIT_TYPES.get(u.type, {}).get("travel_days", 3)
			if td > slowest:
				slowest = td
	return slowest


func get_army_path(army_id: String) -> Array:
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id:
			return u.get("path", [])
	return []


func is_army_moving(army_id: String) -> bool:
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id and not (u.path as Array).is_empty():
			return true
	return false


func is_army_selected(army_id: String) -> bool:
	return army_id in selected_army_ids


## Dijkstra pathfinding weighted by terrain cost.
func find_path(from: String, to: String, mover_iso: String = "") -> Array:
	if from == to:
		return []
	# dist[node] = best cost so far, prev[node] = previous node
	var dist: Dictionary = {from: 0.0}
	var prev: Dictionary = {}
	# Priority queue: [[cost, node_id]]
	var pq: Array = [[0.0, from]]
	var visited: Dictionary = {}

	while not pq.is_empty():
		# Pop lowest cost (simple linear scan — fine for <1000 nodes explored)
		var best_idx: int = 0
		for i: int in range(1, pq.size()):
			if pq[i][0] < pq[best_idx][0]:
				best_idx = i
		var entry: Array = pq[best_idx]
		pq.remove_at(best_idx)
		var cost: float = entry[0]
		var current: String = entry[1]

		if visited.has(current):
			continue
		visited[current] = true

		if current == to:
			# Reconstruct path
			var path: Array = []
			var node: String = to
			while node != from:
				path.push_front(node)
				node = prev[node]
			return path

		for neighbor: String in ProvinceDB.get_neighbors(current):
			if visited.has(neighbor):
				continue
			if not mover_iso.is_empty() and not _can_enter(mover_iso, neighbor):
				if neighbor != to or not _can_attack(mover_iso, neighbor):
					continue
			var terrain: String = ProvinceDB.get_province_terrain(neighbor)
			var move_cost: float = TERRAIN_MOVE_COST.get(terrain, 1.0)
			var new_cost: float = cost + move_cost
			if not dist.has(neighbor) or new_cost < dist[neighbor]:
				dist[neighbor] = new_cost
				prev[neighbor] = current
				pq.append([new_cost, neighbor])

		if visited.size() > 800:
			break

	return []


## Check if mover_iso can enter a territory for passage (own land or military access).
func _can_enter(mover_iso: String, territory: String) -> bool:
	var parent: String = ProvinceDB.get_parent_iso(territory)
	var ter_owner: String = GameState.territory_owner.get(territory, parent)
	if ter_owner.is_empty() or ter_owner == mover_iso:
		return true
	if GameState.is_at_war(mover_iso, ter_owner):
		return true
	var rel: Dictionary = GameState.get_relation(mover_iso, ter_owner)
	if rel.get("military_access", false):
		return true
	return false


## Check if mover can attack into a territory (must be at war with the owner).
func _can_attack(mover_iso: String, territory: String) -> bool:
	var parent: String = ProvinceDB.get_parent_iso(territory)
	var ter_owner: String = GameState.territory_owner.get(territory, parent)
	if ter_owner.is_empty() or ter_owner == mover_iso:
		return true
	return GameState.is_at_war(mover_iso, ter_owner)


func handle_territory_click(iso: String, shift_held: bool = false) -> bool:
	var player: String = GameState.player_iso
	if player.is_empty():
		return false

	var parent: String = ProvinceDB.get_parent_iso(iso)
	var ter_owner: String = GameState.territory_owner.get(iso, parent)
	if ter_owner == player:
		recruit_iso = iso

	var armies_here: Array = _get_army_ids_at(iso, player)

	if armies_here.is_empty():
		if not shift_held:
			deselect()
		return false

	if shift_held:
		for aid: String in armies_here:
			if aid in selected_army_ids:
				selected_army_ids.erase(aid)
			else:
				selected_army_ids.append(aid)
		selected_iso = iso
		selection_changed.emit()
		units_changed.emit()
		return true

	if not selected_army_ids.is_empty():
		var current: String = selected_army_ids[0]
		if current in armies_here:
			var idx: int = armies_here.find(current)
			if idx < armies_here.size() - 1:
				selected_army_ids = [armies_here[idx + 1]]
			else:
				deselect()
			selection_changed.emit()
			units_changed.emit()
			return true

	selected_army_ids = [armies_here[0]]
	selected_iso = iso
	territory_selected.emit(iso)
	selection_changed.emit()
	units_changed.emit()
	return true


func box_select(rect: Rect2) -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	selected_army_ids.clear()
	var seen: Dictionary = {}
	for id: String in units:
		var u: Dictionary = units[id]
		if u.owner != player:
			continue
		var aid: String = u.get("army_id", "")
		if seen.has(aid):
			continue
		var centroid: Vector2 = ProvinceDB.get_centroid(u.location)
		if centroid != Vector2.ZERO and rect.has_point(centroid):
			seen[aid] = true
			selected_army_ids.append(aid)
	if not selected_army_ids.is_empty():
		selected_iso = _get_army_location(selected_army_ids[0])
	selection_changed.emit()
	units_changed.emit()


func handle_move_order(target_iso: String) -> bool:
	var player: String = GameState.player_iso
	if player.is_empty() or selected_army_ids.is_empty():
		return false
	if not _can_enter(player, target_iso) and not _can_attack(player, target_iso):
		UIManager.push_notification("Cannot enter neutral territory.", "warning")
		return false
	var any_moved: bool = false
	for aid: String in selected_army_ids:
		var army_loc: String = _get_army_location(aid)
		if army_loc.is_empty() or army_loc == target_iso:
			continue
		var path: Array = find_path(army_loc, target_iso, player)
		if path.is_empty():
			continue
		_order_army_move(aid, path)
		any_moved = true
	if not any_moved:
		UIManager.push_notification("No valid path for selected armies.", "warning")
		return false
	deselect()
	return true


func deselect() -> void:
	selected_iso = ""
	selected_army_ids.clear()
	territory_selected.emit("")
	selection_changed.emit()
	units_changed.emit()


func _order_army_move(army_id: String, path: Array) -> void:
	var travel_days: int = _get_army_travel_days(army_id)
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id:
			u.path = path.duplicate()
			u.days_remaining = travel_days
			u.travel_days_total = travel_days  # Store total for interpolation
	units_changed.emit()


func _on_day(_date: Dictionary) -> void:
	_tick_morale_and_supply()

	var army_progress: Dictionary = {}
	for id: String in units:
		var u: Dictionary = units[id]
		if (u.path as Array).is_empty():
			continue
		var aid: String = u.get("army_id", id)
		if not army_progress.has(aid):
			army_progress[aid] = {"days_remaining": u.days_remaining, "unit_ids": []}
		(army_progress[aid]["unit_ids"] as Array).append(id)
		army_progress[aid]["days_remaining"] = maxi(
			int(army_progress[aid]["days_remaining"]), int(u.days_remaining))

	if army_progress.is_empty():
		return

	var notifications: Array = []
	var changed: bool = false

	for aid: String in army_progress:
		var info: Dictionary = army_progress[aid]
		var uid_list: Array = info["unit_ids"]
		var days_left: int = int(info["days_remaining"]) - 1

		if days_left > 0:
			for uid: String in uid_list:
				units[uid]["days_remaining"] = days_left
			continue

		var first_u: Dictionary = units[uid_list[0]]
		var path: Array = first_u.path
		if path.is_empty():
			continue

		var next_prov: String = path[0]
		var attacker: String = first_u.owner
		var defender: String = GameState.get_territory_owner(next_prov)

		# Reroute if we can no longer enter the next province (e.g., war ended mid-path)
		if not _can_enter(attacker, next_prov) and not _can_attack(attacker, next_prov):
			var current_loc: String = first_u.location
			var final_dest: String = path[path.size() - 1]
			var new_path: Array = find_path(current_loc, final_dest, attacker)
			if new_path.is_empty():
				# No alternative route — halt
				for uid: String in uid_list:
					if units.has(uid):
						units[uid]["path"] = []
						units[uid]["days_remaining"] = 0
				if attacker == GameState.player_iso:
					notifications.append(["Army halted — no route to %s." % _get_territory_name(final_dest), "warning"])
			else:
				# Reroute around blocked territory
				var travel_days: int = _get_army_travel_days(aid)
				for uid: String in uid_list:
					if units.has(uid):
						units[uid]["path"] = new_path.duplicate()
						units[uid]["days_remaining"] = travel_days
				if attacker == GameState.player_iso:
					notifications.append(["Army rerouting to %s." % _get_territory_name(final_dest), "info"])
			changed = true
			continue

		var is_hostile: bool = (not defender.is_empty()
			and defender != attacker
			and GameState.is_at_war(attacker, defender))

		if is_hostile:
			var won: bool = _resolve_battle(uid_list, next_prov, attacker, defender)
			changed = true
			if attacker == GameState.player_iso:
				var tname: String = _get_territory_name(next_prov)
				if won:
					notifications.append(["Victory in %s! Territory captured." % tname, "info"])
				else:
					notifications.append(["Defeated in %s. Units retreated." % tname, "warning"])
			if not won:
				for uid: String in uid_list:
					if units.has(uid):
						units[uid]["path"] = []
						units[uid]["days_remaining"] = 0
		else:
			var remaining_path: Array = path.slice(1)
			var travel_days: int = _get_army_travel_days(aid)
			for uid: String in uid_list:
				units[uid]["location"] = next_prov
				units[uid]["path"] = remaining_path.duplicate()
				units[uid]["days_remaining"] = travel_days if not remaining_path.is_empty() else 0
			if remaining_path.is_empty() and attacker == GameState.player_iso:
				notifications.append(["Army arrived in %s." % _get_territory_name(next_prov), "info"])
			changed = true

	for n: Array in notifications:
		UIManager.push_notification(n[0], n[1])
	if changed:
		units_changed.emit()


func _get_territory_name(tid: String) -> String:
	var pdata: Dictionary = ProvinceDB.province_data.get(tid, {})
	if not pdata.is_empty():
		return pdata.get("name", tid)
	return GameState.get_country(tid).get("name", tid)


## Total monthly upkeep for all units owned by a country ($B/month).
func get_total_upkeep(iso: String) -> float:
	var total: float = 0.0
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("owner", "") == iso:
			total += float(UNIT_TYPES.get(u.get("type", ""), {}).get("upkeep", 0.0))
	return total


func get_garrison_power(territory_id: String) -> float:
	var parent: String = ProvinceDB.get_parent_iso(territory_id)
	var ter_owner: String = GameState.territory_owner.get(territory_id, parent)
	if ter_owner.is_empty():
		return 20.0
	var mil: float = float(GameState.get_country(ter_owner).get("military_normalized", 100))
	return maxf(30.0, mil * 0.3)


func _resolve_battle(attacker_ids: Array, territory_iso: String,
		attacker_iso: String, defender_iso: String) -> bool:
	var terrain: String = ProvinceDB.get_province_terrain(territory_iso)
	var terrain_def: float = TERRAIN_DEFENSE.get(terrain, 1.0)

	# ── Phase 1: Calculate attacker power ──
	var atk_power: float = 0.0
	var atk_supply: float = _get_supply_modifier(territory_iso, attacker_iso)
	for id: String in attacker_ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		var base: float = float(UNIT_TYPES.get(u.type, {}).get("power", 10))
		var str_mod: float = float(u.strength) / 100.0
		var mor_mod: float = float(u.get("morale", 100)) / 100.0
		var type_bonus: float = _get_type_terrain_bonus(u.type, terrain, true)
		atk_power += base * str_mod * mor_mod * type_bonus

	# Artillery bombardment phase: artillery gets +30% as pre-battle fire
	for id: String in attacker_ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		if u.type == "artillery":
			atk_power += float(UNIT_TYPES["artillery"]["power"]) * 0.3 * float(u.strength) / 100.0

	atk_power *= atk_supply

	# ── Phase 2: Calculate defender power ──
	var defender_ids: Array = []
	var def_power: float = 0.0
	var def_supply: float = _get_supply_modifier(territory_iso, defender_iso)
	for id: String in units:
		var u: Dictionary = units[id]
		if u.owner == defender_iso and u.location == territory_iso:
			defender_ids.append(id)
			var base: float = float(UNIT_TYPES.get(u.type, {}).get("power", 10))
			var str_mod: float = float(u.strength) / 100.0
			var mor_mod: float = float(u.get("morale", 100)) / 100.0
			var type_bonus: float = _get_type_terrain_bonus(u.type, terrain, false)
			def_power += base * str_mod * mor_mod * type_bonus

	var has_real_defenders: bool = not defender_ids.is_empty()
	if not has_real_defenders:
		def_power = get_garrison_power(territory_iso) * 0.3

	# Apply terrain defense bonus and supply
	def_power *= terrain_def * def_supply

	# ── Phase 3: Roll with narrower randomness ──
	var atk_roll: float = atk_power * randf_range(0.85, 1.15)
	var def_roll: float = def_power * randf_range(0.90, 1.10)
	var attacker_won: bool = atk_roll > def_roll
	var power_ratio: float = maxf(atk_roll, 0.1) / maxf(def_roll, 0.1)

	# ── Phase 4: Apply casualties based on power ratio ──
	if attacker_won:
		GameState.territory_owner[territory_iso] = attacker_iso
		# Winner takes lighter casualties when decisive
		var atk_cas: float = clampf(0.25 / power_ratio, 0.03, 0.35)
		for id: String in attacker_ids:
			if not units.has(id):
				continue
			var u: Dictionary = units[id]
			u.strength = clampi(int(float(u.strength) * (1.0 - atk_cas)), 10, 100)
			u.morale = clampf(float(u.get("morale", 100)) + 10.0, 0.0, 100.0)  # Victory morale boost
			var remaining: Array = (u.path as Array).slice(1) if (u.path as Array).size() > 0 else []
			u.location = territory_iso
			u.path = remaining
			u.days_remaining = _get_army_travel_days(u.get("army_id", "")) if not remaining.is_empty() else 0

		if has_real_defenders:
			var def_cas: float = clampf(0.35 * power_ratio, 0.15, 0.80)
			var dead: Array = []
			var retreat_to: String = _find_retreat_province(territory_iso, defender_iso)
			for id: String in defender_ids:
				if not units.has(id):
					continue
				var u: Dictionary = units[id]
				u.strength = clampi(int(float(u.strength) * (1.0 - def_cas)), 0, 100)
				u.morale = clampf(float(u.get("morale", 100)) - 20.0, 0.0, 100.0)
				if u.strength <= 0:
					dead.append(id)
				elif retreat_to.is_empty():
					dead.append(id)  # Encircled — no friendly province to retreat to → destroyed
				else:
					# ALL surviving defenders retreat — territory is lost
					u.location = retreat_to
					u.path = []
					u.days_remaining = 0
			for id: String in dead:
				units.erase(id)
	else:
		# Attacker lost
		var atk_cas: float = clampf(0.35 * (1.0 / power_ratio), 0.15, 0.75)
		var dead: Array = []
		for id: String in attacker_ids:
			if not units.has(id):
				continue
			var u: Dictionary = units[id]
			u.strength = clampi(int(float(u.strength) * (1.0 - atk_cas)), 0, 100)
			u.morale = clampf(float(u.get("morale", 100)) - 20.0, 0.0, 100.0)
			u.path = []
			u.days_remaining = 0
			if u.strength <= 0 or u.morale < 10.0:
				dead.append(id)
		for id: String in dead:
			units.erase(id)

		if has_real_defenders:
			var def_cas: float = clampf(0.15 / (1.0 / power_ratio), 0.03, 0.30)
			var def_dead: Array = []
			for id: String in defender_ids:
				if not units.has(id):
					continue
				var u: Dictionary = units[id]
				u.strength = clampi(int(float(u.strength) * (1.0 - def_cas)), 0, 100)
				u.morale = clampf(float(u.get("morale", 100)) + 5.0, 0.0, 100.0)  # Successful defense morale
				if u.strength <= 0:
					def_dead.append(id)
			for id: String in def_dead:
				units.erase(id)

	battle_resolved.emit(territory_iso, attacker_iso, defender_iso, attacker_won)
	return attacker_won


## Unit type vs terrain bonuses (attacker/defender)
func _get_type_terrain_bonus(unit_type: String, terrain: String, is_attacker: bool) -> float:
	match unit_type:
		"armor":
			# Armor dominates in open terrain, suffers in mountains/jungle
			if terrain == "plains" or terrain == "desert":
				return 1.3 if is_attacker else 1.0
			if terrain == "mountain" or terrain == "jungle":
				return 0.7 if is_attacker else 0.8
		"infantry":
			# Infantry excels in defensive terrain
			if terrain == "mountain" or terrain == "jungle" or terrain == "forest":
				return 1.0 if is_attacker else 1.2
		"artillery":
			# Artillery less effective in forests/jungles (obstructed fire)
			if terrain == "forest" or terrain == "jungle":
				return 0.8
	return 1.0


## Find a friendly province to retreat to
func _find_retreat_province(from: String, unit_owner: String) -> String:
	for nb: String in ProvinceDB.get_neighbors(from):
		var nb_owner: String = GameState.territory_owner.get(nb, ProvinceDB.get_parent_iso(nb))
		if nb_owner == unit_owner:
			return nb
	return ""  # Encircled — no retreat possible


## ── Morale & Supply System ────────────────────────────────────────────────────

func _tick_morale_and_supply() -> void:
	var dead_units: Array = []
	for uid: String in units:
		var u: Dictionary = units[uid]
		var loc: String = u.location
		var unit_owner: String = u.owner
		var morale: float = float(u.get("morale", 100))
		var strength: float = float(u.get("strength", 100))

		# Supply distance: BFS from unit to nearest owned territory
		var supply_dist: int = _get_supply_distance(loc, unit_owner)
		u["supply_distance"] = supply_dist

		# Territory status
		var ter_owner: String = GameState.territory_owner.get(loc, ProvinceDB.get_parent_iso(loc))
		var in_friendly: bool = ter_owner == unit_owner
		var in_enemy: bool = not in_friendly and not ter_owner.is_empty()

		# ── Morale changes ──
		if in_friendly:
			morale += 2.0  # Recovery in friendly territory
			var capital: String = ProvinceDB.get_capital_province(unit_owner)
			if loc == capital:
				morale += 3.0  # Extra recovery at capital
		elif in_enemy:
			morale -= 0.5  # Slow drain in enemy territory

		# Supply-based morale drain
		if supply_dist > SUPPLY_FULL and supply_dist <= SUPPLY_LOW:
			morale -= 1.0
		elif supply_dist > SUPPLY_LOW and supply_dist <= SUPPLY_CRITICAL:
			morale -= 3.0
		elif supply_dist > SUPPLY_CRITICAL:
			morale -= 6.0  # Starvation morale collapse

		# ── Supply-based strength attrition ──
		if supply_dist > SUPPLY_LOW and supply_dist <= SUPPLY_CRITICAL:
			strength -= 1.0  # Light attrition
		elif supply_dist > SUPPLY_CRITICAL:
			strength -= 3.0  # Heavy attrition (starvation)

		# Clamp values
		u["morale"] = clampf(morale, 0.0, 100.0)
		u["strength"] = clampi(int(strength), 0, 100)

		if u["strength"] <= 0:
			dead_units.append(uid)

	# Remove dead units
	for uid: String in dead_units:
		units.erase(uid)
	if not dead_units.is_empty():
		units_changed.emit()


## BFS supply distance: shortest path from location to any owned province.
func _get_supply_distance(from_loc: String, unit_owner: String) -> int:
	# If already in owned territory, distance = 0
	var from_owner: String = GameState.territory_owner.get(from_loc, ProvinceDB.get_parent_iso(from_loc))
	if from_owner == unit_owner:
		return 0

	var visited: Dictionary = {from_loc: true}
	var frontier: Array = [from_loc]
	var distance: int = 0

	while not frontier.is_empty() and distance < 15:
		distance += 1
		var next_frontier: Array = []
		for pid: String in frontier:
			for nb: String in ProvinceDB.get_neighbors(pid):
				if visited.has(nb):
					continue
				visited[nb] = true
				var nb_owner: String = GameState.territory_owner.get(nb, ProvinceDB.get_parent_iso(nb))
				if nb_owner == unit_owner:
					return distance
				next_frontier.append(nb)
		frontier = next_frontier

	return 15  # Max distance = encircled / no supply


## Get supply modifier for combat (1.0 = full, <1.0 = penalized)
func _get_supply_modifier(loc: String, unit_owner: String) -> float:
	var dist: int = _get_supply_distance(loc, unit_owner)
	if dist <= SUPPLY_FULL:
		return 1.0
	elif dist <= SUPPLY_LOW:
		return 0.85
	elif dist <= SUPPLY_CRITICAL:
		return 0.6
	return 0.35  # Starving army


func split_army(army_id: String) -> String:
	var unit_ids: Array = _get_army_unit_ids(army_id)
	if unit_ids.size() < 2:
		return ""
	for uid: String in unit_ids:
		if not (units[uid]["path"] as Array).is_empty():
			UIManager.push_notification("Cannot split army while moving.", "warning")
			return ""
	var new_aid: String = _new_army_id()
	for i: int in range(unit_ids.size()):
		if i % 2 == 1:
			units[unit_ids[i]]["army_id"] = new_aid
	units_changed.emit()
	UIManager.push_notification("Army split into two groups.", "info")
	return new_aid


func merge_armies(army_a: String, army_b: String) -> void:
	var loc_a: String = _get_army_location(army_a)
	var loc_b: String = _get_army_location(army_b)
	if loc_a != loc_b:
		UIManager.push_notification("Armies must be in the same territory to merge.", "warning")
		return
	for id: String in units:
		if (units[id] as Dictionary).get("army_id", "") == army_b:
			units[id]["army_id"] = army_a
	units_changed.emit()
	UIManager.push_notification("Armies merged.", "info")


## Get the valid recruitment location for a unit type, or "" if can't recruit here.
func get_recruit_location(type: String, preferred: String = "") -> String:
	var player: String = GameState.player_iso
	if player.is_empty():
		return ""

	# Find which building types unlock this unit
	var required_buildings: Array = []
	for btype: String in BuildingSystem.BUILDING_TYPES:
		var bdef: Dictionary = BuildingSystem.BUILDING_TYPES[btype]
		var unlocks: Array = bdef.get("unlocks_recruit", [])
		if type in unlocks:
			required_buildings.append(btype)

	if required_buildings.is_empty():
		return ""  # No building can produce this unit

	# Check preferred location first
	if not preferred.is_empty():
		var ter_owner: String = GameState.territory_owner.get(preferred, "")
		if ter_owner == player:
			for btype: String in required_buildings:
				if BuildingSystem.has_building(preferred, btype):
					return preferred

	# Fallback: find any province with the required building
	for btype: String in required_buildings:
		var provinces: Array = BuildingSystem.get_provinces_with_building(player, btype)
		if not provinces.is_empty():
			return provinces[0]

	return ""  # No building available — can't recruit


func can_recruit(type: String) -> bool:
	if GameState.player_iso.is_empty():
		return false
	var cost: float = UNIT_TYPES.get(type, {}).get("cost", 9999.0)
	if float(GameState.get_country(GameState.player_iso).get("treasury", 0.0)) < cost:
		return false
	# Check location requirement
	return not get_recruit_location(type).is_empty()


## Check if a specific unit type can be recruited at a specific location.
func can_recruit_at(type: String, location: String) -> bool:
	if GameState.player_iso.is_empty() or location.is_empty():
		return false
	var cost: float = UNIT_TYPES.get(type, {}).get("cost", 9999.0)
	if float(GameState.get_country(GameState.player_iso).get("treasury", 0.0)) < cost:
		return false
	var player: String = GameState.player_iso
	if GameState.territory_owner.get(location, "") != player:
		return false
	# Check if this location has a building that unlocks this unit type
	for btype: String in BuildingSystem.BUILDING_TYPES:
		var bdef: Dictionary = BuildingSystem.BUILDING_TYPES[btype]
		if type in bdef.get("unlocks_recruit", []):
			if BuildingSystem.has_building(location, btype):
				return true
	return false


func recruit_unit(type: String, at_province: String = "") -> bool:
	if not can_recruit(type):
		return false
	var player: String = GameState.player_iso
	var data: Dictionary = GameState.get_country(player)
	var location: String = get_recruit_location(type, at_province)
	if location.is_empty():
		UIManager.push_notification("No valid location to recruit %s." % UNIT_TYPES[type]["label"], "warning")
		return false
	data["treasury"] = float(data.get("treasury", 0.0)) \
					   - float(UNIT_TYPES[type].get("cost", 0.0))
	var army_id: String = ""
	if not selected_army_ids.is_empty():
		var sel_loc: String = _get_army_location(selected_army_ids[0])
		if sel_loc == location:
			army_id = selected_army_ids[0]
	if army_id.is_empty():
		army_id = _find_stationary_army(player, location)
	if army_id.is_empty():
		army_id = _new_army_id()
	spawn_unit(type, player, location, army_id)
	units_changed.emit()
	var loc_name: String = ProvinceDB.province_data.get(location, {}).get("name", location)
	UIManager.push_notification("%s recruited at %s." % [UNIT_TYPES[type]["label"], loc_name], "info")
	return true


func get_units_at(iso: String) -> Array:
	return _get_units_at(iso, "")

func get_player_units_at(iso: String) -> Array:
	return _get_units_at(iso, GameState.player_iso)

func _get_units_at(iso: String, owner_filter: String) -> Array:
	var result: Array = []
	var parent: String = ProvinceDB.get_parent_iso(iso)
	for id: String in units:
		var u: Dictionary = units[id]
		if u.location != iso and u.location != parent:
			continue
		if owner_filter.is_empty() or u.owner == owner_filter:
			result.append(u)
	return result
