## GameState.gd
## Autoload singleton — single source of truth for all game data.
## No system owns data. They read/write here.
extends Node

signal country_selected(iso: String)
signal country_deselected()
signal country_data_changed(iso: String)
signal player_country_set(iso: String)
signal war_state_changed(iso_a: String, iso_b: String, at_war: bool)

# All countries keyed by ISO-A3 code
var countries: Dictionary = {}          # iso → CountryData dict
var player_iso: String = ""             # which country the player controls
var selected_iso: String = ""           # currently selected country ISO

# Ownership: territory_id → owner_iso
# territory_id is a province_id when provinces are loaded, or country_iso otherwise
var territory_owner: Dictionary = {}

# Relations matrix: "ISO_A:ISO_B" → RelationData dict
var relations: Dictionary = {}


func _ready() -> void:
	pass


## Called by ProvinceDB after loading countries.json.
func init_countries(data: Array) -> void:
	for entry in data:
		var iso: String = entry.get("iso", "")
		if iso.is_empty():
			continue
		countries[iso] = entry
		territory_owner[iso] = iso   # country-level fallback; overridden by init_provinces


## Called by ProvinceDB after loading provinces.json.
func init_provinces(data: Array) -> void:
	for entry in data:
		var pid: String    = entry.get("id", "")
		var parent: String = entry.get("parent_iso", pid)
		if pid.is_empty():
			continue
		territory_owner[pid] = parent   # province owned by its country at start


func select_country(iso: String) -> void:
	if iso == selected_iso:
		return
	selected_iso = iso
	if iso.is_empty():
		emit_signal("country_deselected")
	else:
		emit_signal("country_selected", iso)


func deselect() -> void:
	select_country("")


func get_country(iso: String) -> Dictionary:
	return countries.get(iso, {})


func get_territory_owner(territory_iso: String) -> String:
	return territory_owner.get(territory_iso, "")


func is_player_country(iso: String) -> bool:
	return iso == player_iso


func set_player_country(iso: String) -> void:
	player_iso = iso
	emit_signal("player_country_set", iso)


## Returns the dominant owner of a country (who owns the most of its provinces).
## Falls back to territory_owner[country_iso] if no provinces are loaded.
func get_country_owner(country_iso: String) -> String:
	var provinces: Array = ProvinceDB.get_country_province_ids(country_iso)
	if provinces.is_empty():
		return territory_owner.get(country_iso, country_iso)
	var counts: Dictionary = {}
	for pid: String in provinces:
		var ter_owner: String = territory_owner.get(pid, country_iso)
		counts[ter_owner] = counts.get(ter_owner, 0) + 1
	var best: String = country_iso
	var best_n: int  = 0
	for ter_owner: String in counts:
		if counts[ter_owner] > best_n:
			best_n = counts[ter_owner]
			best   = ter_owner
	return best


## Relation helpers
func get_relation(iso_a: String, iso_b: String) -> Dictionary:
	var key: String = _relation_key(iso_a, iso_b)
	if not relations.has(key):
		relations[key] = _default_relation(iso_a, iso_b)
	return relations[key]


func _relation_key(a: String, b: String) -> String:
	if a < b:
		return "%s:%s" % [a, b]
	return "%s:%s" % [b, a]


func is_at_war(iso_a: String, iso_b: String) -> bool:
	return get_relation(iso_a, iso_b).get("at_war", false)


func set_war(iso_a: String, iso_b: String, at_war: bool) -> void:
	get_relation(iso_a, iso_b)["at_war"] = at_war
	war_state_changed.emit(iso_a, iso_b, at_war)


func _default_relation(iso_a: String, iso_b: String) -> Dictionary:
	return {
		"iso_a": iso_a,
		"iso_b": iso_b,
		"diplomatic_score": 0,
		"escalation_level": 0,
		"trade_volume": 0.0,
		"loans_owed": 0.0,
		"at_war": false,
		"alliance": false,
	}
