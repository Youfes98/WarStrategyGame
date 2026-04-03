## MilitarySystem.gd
## Autoload — manages units, movement, combat, and army operations.
## Features: BFS pathfinding, movement queues, army splitting, province recruitment,
## multi-army selection (box select + shift-click), multi-army move orders.
extends Node

signal units_changed()
signal territory_selected(iso: String)
signal selection_changed()
signal battle_resolved(territory_iso: String, attacker_iso: String, defender_iso: String, attacker_won: bool)

const UNIT_TYPES: Dictionary = {
	"infantry":  {"label": "Infantry",  "travel_days": 3, "cost": 5.0,  "upkeep": 0.10, "icon": "INF", "power": 10},
	"armor":     {"label": "Armor",     "travel_days": 2, "cost": 15.0, "upkeep": 0.30, "icon": "ARM", "power": 25},
	"artillery": {"label": "Artillery", "travel_days": 4, "cost": 10.0, "upkeep": 0.20, "icon": "ART", "power": 18},
}

const STARTING_UNITS: Dictionary = {
	"S": [["infantry", 5], ["armor", 3], ["artillery", 2]],
	"A": [["infantry", 4], ["armor", 2], ["artillery", 1]],
	"B": [["infantry", 3], ["armor", 1]],
	"C": [["infantry", 2]],
	"D": [["infantry", 1]],
}

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


func _can_enter(player: String, territory_id: String) -> bool:
	var parent: String = ProvinceDB.get_parent_iso(territory_id)
	var ter_owner: String = GameState.territory_owner.get(territory_id, parent)
	return ter_owner == player or GameState.is_at_war(player, ter_owner)


func is_army_moving(army_id: String) -> bool:
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id and not (u.path as Array).is_empty():
			return true
	return false


func is_army_selected(army_id: String) -> bool:
	return army_id in selected_army_ids


func find_path(from: String, to: String) -> Array:
	if from == to:
		return []
	var queue: Array = [[from]]
	var visited: Dictionary = {from: true}
	while not queue.is_empty():
		var current_path: Array = queue.pop_front()
		var current: String = current_path[current_path.size() - 1]
		for neighbor: String in ProvinceDB.get_neighbors(current):
			if visited.has(neighbor):
				continue
			var new_path: Array = current_path.duplicate()
			new_path.append(neighbor)
			if neighbor == to:
				return new_path.slice(1)
			visited[neighbor] = true
			queue.append(new_path)
			if visited.size() > 500:
				return []
	return []


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
	if not _can_enter(player, target_iso):
		UIManager.push_notification("Cannot enter neutral territory.", "warning")
		return false
	var any_moved: bool = false
	for aid: String in selected_army_ids:
		var army_loc: String = _get_army_location(aid)
		if army_loc.is_empty() or army_loc == target_iso:
			continue
		var path: Array = find_path(army_loc, target_iso)
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
	units_changed.emit()


func _on_day(_date: Dictionary) -> void:
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


func get_garrison_power(territory_id: String) -> float:
	var parent: String = ProvinceDB.get_parent_iso(territory_id)
	var ter_owner: String = GameState.territory_owner.get(territory_id, parent)
	if ter_owner.is_empty():
		return 20.0
	var mil: float = float(GameState.get_country(ter_owner).get("military_normalized", 100))
	return maxf(30.0, mil * 0.3)


func _resolve_battle(attacker_ids: Array, territory_iso: String,
		attacker_iso: String, defender_iso: String) -> bool:
	var atk_power: float = 0.0
	for id: String in attacker_ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		atk_power += float(UNIT_TYPES.get(u.type, {}).get("power", 10)) \
					 * (float(u.strength) / 100.0)
	var def_power: float = get_garrison_power(territory_iso)
	var atk_roll: float = atk_power * randf_range(0.75, 1.25)
	var def_roll: float = def_power * randf_range(0.85, 1.20)
	var attacker_won: bool = atk_roll > def_roll

	if attacker_won:
		GameState.territory_owner[territory_iso] = attacker_iso
		var casualty: float = clampf(def_roll / atk_roll * 0.35, 0.05, 0.45)
		for id: String in attacker_ids:
			if not units.has(id):
				continue
			var u: Dictionary = units[id]
			u.strength = clampi(int(float(u.strength) * (1.0 - casualty)), 10, 100)
			var remaining: Array = (u.path as Array).slice(1) if (u.path as Array).size() > 0 else []
			u.location = territory_iso
			u.path = remaining
			u.days_remaining = _get_army_travel_days(u.get("army_id", "")) if not remaining.is_empty() else 0
	else:
		var casualty: float = clampf(def_roll / atk_roll * 0.55, 0.15, 0.80)
		var dead: Array = []
		for id: String in attacker_ids:
			if not units.has(id):
				continue
			var u: Dictionary = units[id]
			u.strength = clampi(int(float(u.strength) * (1.0 - casualty)), 0, 100)
			u.path = []
			u.days_remaining = 0
			if u.strength <= 0:
				dead.append(id)
		for id: String in dead:
			units.erase(id)
	battle_resolved.emit(territory_iso, attacker_iso, defender_iso, attacker_won)
	return attacker_won


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


func can_recruit(type: String) -> bool:
	if GameState.player_iso.is_empty():
		return false
	var cost: float = UNIT_TYPES.get(type, {}).get("cost", 9999.0)
	return float(GameState.get_country(GameState.player_iso).get("gdp_raw_billions", 0.0)) >= cost


func recruit_unit(type: String, at_province: String = "") -> bool:
	if not can_recruit(type):
		return false
	var player: String = GameState.player_iso
	var data: Dictionary = GameState.get_country(player)
	data["gdp_raw_billions"] = float(data.get("gdp_raw_billions", 0.0)) \
							   - float(UNIT_TYPES[type].get("cost", 0.0))
	var location: String = at_province
	if location.is_empty():
		location = _find_home_province(player)
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
