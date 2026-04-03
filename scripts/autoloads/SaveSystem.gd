## SaveSystem.gd
## Autoload — F5 quicksave, F9 quickload.
## Serialises GameState + MilitarySystem to JSON for fast playtesting iteration.
extends Node

const SAVE_DIR:  String = "user://saves/"
const QUICK_SAVE: String = "user://saves/quicksave.json"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_F5:
			quicksave()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_F9:
			quickload()
			get_viewport().set_input_as_handled()


func quicksave() -> void:
	var data: Dictionary = _serialize()
	var file: FileAccess = FileAccess.open(QUICK_SAVE, FileAccess.WRITE)
	if file == null:
		UIManager.push_notification("Save failed: cannot write file", "warning")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	UIManager.push_notification("Game saved.", "info")


func quickload() -> void:
	if not FileAccess.file_exists(QUICK_SAVE):
		UIManager.push_notification("No save file found.", "warning")
		return
	var file: FileAccess = FileAccess.open(QUICK_SAVE, FileAccess.READ)
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		UIManager.push_notification("Save file corrupt.", "warning")
		file.close()
		return
	file.close()
	_deserialize(json.get_data())
	UIManager.push_notification("Game loaded.", "info")


func _serialize() -> Dictionary:
	return {
		"version": 2,
		"player_iso": GameState.player_iso,
		"selected_iso": GameState.selected_iso,
		"territory_owner": GameState.territory_owner.duplicate(),
		"relations": GameState.relations.duplicate(true),
		"countries": _serialize_countries(),
		"military": _serialize_military(),
		"clock": _serialize_clock(),
		"buildings": GameState.province_buildings.duplicate(true),
		"construction": GameState.construction_queue.duplicate(true),
	}


func _serialize_countries() -> Dictionary:
	var out: Dictionary = {}
	for iso: String in GameState.countries:
		var c: Dictionary = GameState.countries[iso]
		out[iso] = {
			"gdp_raw_billions": c.get("gdp_raw_billions", 0.0),
			"stability": c.get("stability", 50),
			"debt_to_gdp": c.get("debt_to_gdp", 0.0),
			"credit_rating": c.get("credit_rating", 50),
			"infrastructure": c.get("infrastructure", 30),
			"treasury": c.get("treasury", 0.0),
			"tax_rate": c.get("tax_rate", 0.25),
			"tax_min": c.get("tax_min", 0.10),
			"tax_max": c.get("tax_max", 0.45),
			"budget_military": c.get("budget_military", 25.0),
			"budget_infrastructure": c.get("budget_infrastructure", 45.0),
			"budget_research": c.get("budget_research", 30.0),
		}
	return out


func _serialize_military() -> Dictionary:
	return {
		"units": MilitarySystem.units.duplicate(true),
		"next_id": MilitarySystem._next_id,
		"next_army_id": MilitarySystem._next_army_id,
	}


func _serialize_clock() -> Dictionary:
	return {
		"year":  GameClock.date.year,
		"month": GameClock.date.month,
		"day":   GameClock.date.day,
		"hour":  GameClock.date.hour,
		"paused": GameClock.paused,
		"speed": GameClock.speed,
	}


func _deserialize(data: Dictionary) -> void:
	# Pause during load to prevent ticks while restoring state
	var was_paused: bool = GameClock.paused
	GameClock.paused = true

	# Clock
	var clk: Dictionary = data.get("clock", {})
	if clk.has("year"):
		GameClock.date.year  = int(clk.year)
		GameClock.date.month = int(clk.month)
		GameClock.date.day   = int(clk.day)
		GameClock.date.hour  = int(clk.get("hour", 0))
	if clk.has("speed"):
		GameClock.speed = int(clk.speed)

	# Territory ownership
	var owners: Dictionary = data.get("territory_owner", {})
	for key: String in owners:
		GameState.territory_owner[key] = owners[key]

	# Relations
	var rels: Dictionary = data.get("relations", {})
	GameState.relations = rels

	# Country mutable data
	var countries: Dictionary = data.get("countries", {})
	for iso: String in countries:
		if GameState.countries.has(iso):
			var saved: Dictionary = countries[iso]
			var live: Dictionary  = GameState.countries[iso]
			for k: String in saved:
				live[k] = saved[k]

	# Player
	var piso: String = data.get("player_iso", "")
	if not piso.is_empty():
		GameState.player_iso = piso

	# Military
	var mil: Dictionary = data.get("military", {})
	if mil.has("units"):
		MilitarySystem.units = mil.units
	if mil.has("next_id"):
		MilitarySystem._next_id = int(mil.next_id)
	if mil.has("next_army_id"):
		MilitarySystem._next_army_id = int(mil.next_army_id)

	# Buildings
	var buildings: Dictionary = data.get("buildings", {})
	if not buildings.is_empty():
		GameState.province_buildings = buildings
	var construction: Dictionary = data.get("construction", {})
	if not construction.is_empty():
		GameState.construction_queue = construction

	# Restore pause state
	GameClock.paused = bool(clk.get("paused", was_paused))

	# Refresh all visuals
	GameState.country_data_changed.emit(piso)
	MilitarySystem.units_changed.emit()
	MilitarySystem.selection_changed.emit()

	# Refresh map colors for territory ownership changes
	var map: Node = get_tree().get_first_node_in_group("map_renderer")
	if map != null and map.has_method("_refresh_all_colors"):
		map._refresh_all_colors()


## ── Named saves ──────────────────────────────────────────────────────────────

func save_game(slot_name: String) -> bool:
	var path: String = SAVE_DIR + slot_name + ".json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_serialize(), "\t"))
	file.close()
	return true


func load_game(slot_name: String) -> bool:
	var path: String = SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return false
	file.close()
	_deserialize(json.get_data())
	return true


func list_saves() -> Array[String]:
	var saves: Array[String] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			saves.append(fname.get_basename())
		fname = dir.get_next()
	saves.sort()
	return saves


func delete_save(slot_name: String) -> void:
	var path: String = SAVE_DIR + slot_name + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
