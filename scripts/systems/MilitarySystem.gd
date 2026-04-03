## MilitarySystem.gd
## Autoload — manages units, movement, and combat.
## Units are grouped into armies (army_id). Each army is independently selectable.
## Movement into neutral territory is blocked.
extends Node

signal units_changed()
signal territory_selected(iso: String)
signal battle_resolved(territory_iso: String, attacker_iso: String, defender_iso: String, attacker_won: bool)

const UNIT_TYPES: Dictionary = {
	"infantry":  {"label": "Infantry",  "travel_days": 3, "cost": 5.0,  "upkeep": 0.10, "icon": "I", "power": 10},
	"armor":     {"label": "Armor",     "travel_days": 2, "cost": 15.0, "upkeep": 0.30, "icon": "A", "power": 25},
	"artillery": {"label": "Artillery", "travel_days": 4, "cost": 10.0, "upkeep": 0.20, "icon": "R", "power": 18},
}

const STARTING_UNITS: Dictionary = {
	"S": [["infantry", 5], ["armor", 3], ["artillery", 2]],
	"A": [["infantry", 4], ["armor", 2], ["artillery", 1]],
	"B": [["infantry", 3], ["armor", 1]],
	"C": [["infantry", 2]],
	"D": [["infantry", 1]],
}

var units:            Dictionary = {}   # id → unit dict
var selected_iso:     String     = ""   # territory iso of selected army
var selected_army_id: String     = ""   # which army is currently selected
var _next_id:         int        = 1
var _next_army_id:    int        = 1


func _ready() -> void:
	GameState.player_country_set.connect(_on_player_set)
	GameClock.tick_day.connect(_on_day)


func _on_player_set(iso: String) -> void:
	var tier: String = GameState.get_country(iso).get("power_tier", "C")
	var spawn_loc: String = _find_home_province(iso)
	var army_id: String = _new_army_id()
	for entry: Array in STARTING_UNITS.get(tier, [["infantry", 1]]):
		for _i: int in entry[1]:
			spawn_unit(entry[0], iso, spawn_loc, army_id)
	units_changed.emit()


## Find the province closest to the country centroid (capital region).
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


func spawn_unit(type: String, unit_owner: String, location: String, army_id: String = "") -> String:
	if army_id.is_empty():
		army_id = _new_army_id()
	var id: String = "u%04d" % _next_id
	_next_id += 1
	units[id] = {
		"id": id, "type": type, "owner": unit_owner,
		"location": location, "destination": "",
		"days_remaining": 0, "strength": 100, "morale": 80,
		"army_id": army_id,
	}
	return id


# ── Army helpers ──────────────────────────────────────────────────────────────

func _new_army_id() -> String:
	var id: String = "a%04d" % _next_army_id
	_next_army_id += 1
	return id


func _get_army_location(army_id: String) -> String:
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
		# Match exact location OR parent country fallback
		if u.location == iso or u.location == parent:
			var aid: String = u.get("army_id", "")
			if not aid.is_empty() and not seen.has(aid):
				seen[aid] = true
				result.append(aid)
	return result


func _find_stationary_army(unit_owner: String, location: String) -> String:
	for id: String in units:
		var u: Dictionary = units[id]
		if u.owner == unit_owner and u.location == location and u.destination.is_empty():
			return u.get("army_id", "")
	return ""


## Returns true if the player can legally move into a territory.
## Works with both province_ids and country ISOs.
func _can_enter(player: String, territory_id: String) -> bool:
	var parent: String = ProvinceDB.get_parent_iso(territory_id)
	var unit_owner: String  = GameState.territory_owner.get(territory_id, parent)
	return unit_owner == player or GameState.is_at_war(player, unit_owner)


# ── Movement ──────────────────────────────────────────────────────────────────

func handle_territory_click(iso: String) -> bool:
	var player: String = GameState.player_iso
	if player.is_empty():
		return false

	if selected_army_id != "":
		var army_loc: String = _get_army_location(selected_army_id)

		# Clicking the same territory — cycle to next army or deselect
		if iso == army_loc:
			var armies_here: Array = _get_army_ids_at(iso, player)
			var idx: int = armies_here.find(selected_army_id)
			if idx >= 0 and idx < armies_here.size() - 1:
				# Select next army at this location
				selected_army_id = armies_here[idx + 1]
				territory_selected.emit(iso)
				units_changed.emit()
			else:
				deselect()
			return true

		# Adjacent valid destination — move
		if iso in ProvinceDB.get_neighbors(army_loc):
			if _can_enter(player, iso):
				_move_army(selected_army_id, iso)
				return true
			# Neutral territory: don't move, allow country card to open
			return false

		# Different territory with player armies — switch selection
		var other_armies: Array = _get_army_ids_at(iso, player)
		if other_armies.size() > 0:
			selected_army_id = other_armies[0]
			selected_iso     = iso
			territory_selected.emit(iso)
			units_changed.emit()
			return true

		deselect()
		return false

	# Nothing selected yet — try to select an army at iso
	var player_armies: Array = _get_army_ids_at(iso, player)
	if player_armies.size() > 0:
		selected_army_id = player_armies[0]
		selected_iso     = iso
		territory_selected.emit(iso)
		units_changed.emit()
		return true

	return false


func deselect() -> void:
	selected_iso     = ""
	selected_army_id = ""
	territory_selected.emit("")
	units_changed.emit()


func _move_army(army_id: String, to_iso: String) -> void:
	var moved: bool = false
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("army_id", "") == army_id and u.destination.is_empty():
			u.destination    = to_iso
			u.days_remaining = UNIT_TYPES.get(u.type, {}).get("travel_days", 3)
			moved = true
	if moved:
		units_changed.emit()
		deselect()


func _on_day(_date: Dictionary) -> void:
	# Decrement travel timers
	for id: String in units:
		var u: Dictionary = units[id]
		if not u.destination.is_empty():
			u.days_remaining -= 1

	# Group units that have just arrived: key = "owner:destination"
	var arrivals: Dictionary = {}
	for id: String in units:
		var u: Dictionary = units[id]
		if u.destination.is_empty() or u.days_remaining > 0:
			continue
		var key: String = "%s:%s" % [u.owner, u.destination]
		if not arrivals.has(key):
			arrivals[key] = []
		(arrivals[key] as Array).append(id)

	if arrivals.is_empty():
		return

	var notifications: Array = []
	var changed: bool = false

	for key: String in arrivals:
		var ids: Array = arrivals[key]
		var first: Dictionary = units[ids[0]]
		var dest: String       = first.destination
		var attacker: String   = first.owner
		var defender: String   = GameState.get_territory_owner(dest)

		var is_hostile: bool = (not defender.is_empty()
			and defender != attacker
			and GameState.is_at_war(attacker, defender))

		if is_hostile:
			var won: bool = _resolve_battle(ids, dest, attacker, defender)
			changed = true
			if attacker == GameState.player_iso:
				var tname: String = GameState.get_country(dest).get("name", dest)
				if won:
					notifications.append(["Victory in %s! Territory captured." % tname, "info"])
				else:
					notifications.append(["Defeated in %s. Units retreated." % tname, "warning"])
		else:
			# Peaceful arrival
			for id: String in ids:
				var u: Dictionary = units[id]
				u.location    = u.destination
				u.destination = ""
			if attacker == GameState.player_iso:
				var tname: String = GameState.get_country(dest).get("name", dest)
				notifications.append(["Units arrived in %s." % tname, "info"])
			changed = true

	for n: Array in notifications:
		UIManager.push_notification(n[0], n[1])

	if changed:
		units_changed.emit()


# ── Combat ────────────────────────────────────────────────────────────────────

func get_garrison_power(territory_id: String) -> float:
	var parent: String = ProvinceDB.get_parent_iso(territory_id)
	var unit_owner: String  = GameState.territory_owner.get(territory_id, parent)
	if unit_owner.is_empty():
		return 20.0
	var mil: float = float(GameState.get_country(unit_owner).get("military_normalized", 100))
	# Scale: weak country ~30, average ~90, superpower ~270
	return maxf(30.0, mil * 0.3)


func _resolve_battle(attacker_ids: Array, territory_iso: String,
		attacker_iso: String, defender_iso: String) -> bool:
	# Attacker power = sum of unit combat power × condition
	var atk_power: float = 0.0
	for id: String in attacker_ids:
		if not units.has(id):
			continue
		var u: Dictionary = units[id]
		atk_power += float(UNIT_TYPES.get(u.type, {}).get("power", 10)) \
					 * (float(u.strength) / 100.0)

	var def_power: float = get_garrison_power(territory_iso)

	# Dice roll — defenders have slight home advantage
	var atk_roll: float = atk_power  * randf_range(0.75, 1.25)
	var def_roll: float = def_power  * randf_range(0.85, 1.20)

	var attacker_won: bool = atk_roll > def_roll

	if attacker_won:
		# Transfer ownership
		GameState.territory_owner[territory_iso] = attacker_iso
		# Move units in, apply light casualties
		var casualty: float = clampf(def_roll / atk_roll * 0.35, 0.05, 0.45)
		for id: String in attacker_ids:
			if not units.has(id):
				continue
			var u: Dictionary = units[id]
			u.strength    = clampi(int(float(u.strength) * (1.0 - casualty)), 10, 100)
			u.location    = territory_iso
			u.destination = ""
	else:
		# Retreat to origin (location was not updated yet) — heavy casualties
		var casualty: float = clampf(def_roll / atk_roll * 0.55, 0.15, 0.80)
		var dead: Array = []
		for id: String in attacker_ids:
			if not units.has(id):
				continue
			var u: Dictionary = units[id]
			u.strength    = clampi(int(float(u.strength) * (1.0 - casualty)), 0, 100)
			u.destination = ""
			# u.location stays as origin — unit retreats there automatically
			if u.strength <= 0:
				dead.append(id)
		for id: String in dead:
			units.erase(id)

	battle_resolved.emit(territory_iso, attacker_iso, defender_iso, attacker_won)
	return attacker_won


# ── Queries ───────────────────────────────────────────────────────────────────

func can_recruit(type: String) -> bool:
	if GameState.player_iso.is_empty():
		return false
	var cost: float = UNIT_TYPES.get(type, {}).get("cost", 9999.0)
	return float(GameState.get_country(GameState.player_iso).get("gdp_raw_billions", 0.0)) >= cost


func recruit_unit(type: String) -> bool:
	if not can_recruit(type):
		return false
	var player: String = GameState.player_iso
	var data: Dictionary = GameState.get_country(player)
	data["gdp_raw_billions"] = float(data.get("gdp_raw_billions", 0.0)) \
							   - float(UNIT_TYPES[type].get("cost", 0.0))
	# Join existing stationary army at home province, or create a new one
	var home: String = _find_home_province(player)
	var army_id: String = _find_stationary_army(player, home)
	if army_id.is_empty():
		army_id = _new_army_id()
	spawn_unit(type, player, home, army_id)
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
