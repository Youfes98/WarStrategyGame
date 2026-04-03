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
		"version": 1,
		"player_iso": GameState.player_iso,
		"selected_iso": GameState.selected_iso,
		"territory_owner": GameState.territory_owner.duplicate(),
		"relations": GameState.relations.duplicate(true),
		"countries": _serialize_countries(),
		"military": _serialize_military(),
		"clock": _serialize_clock(),
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
		"day": GameClock.day,
		"month": GameClock.month,
		"year": GameClock.year,
		"paused": GameClock.paused,
		"speed": GameClock.speed_index if "speed_index" in GameClock else 1,
	}


func _deserialize(data: Dictionary) -> void:
	# Clock
	var clk: Dictionary = data.get("clock", {})
	if clk.has("day"):
		GameClock.day   = int(clk.day)
		GameClock.month = int(clk.month)
		GameClock.year  = int(clk.year)
	if clk.has("paused"):
		GameClock.paused = bool(clk.paused)

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
	if not piso.is_empty() and piso != GameState.player_iso:
		GameState.set_player_country(piso)

	# Military
	var mil: Dictionary = data.get("military", {})
	if mil.has("units"):
		MilitarySystem.units = mil.units
	if mil.has("next_id"):
		MilitarySystem._next_id = int(mil.next_id)
	if mil.has("next_army_id"):
		MilitarySystem._next_army_id = int(mil.next_army_id)

	# Refresh visuals
	GameState.country_data_changed.emit(piso)
