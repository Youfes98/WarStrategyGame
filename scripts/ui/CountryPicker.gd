## CountryPicker.gd
## Full-screen overlay shown at game start.
## Player picks their country, then the game begins.
extends Control

signal country_confirmed(iso: String)

@onready var _search_box:    LineEdit      = $Panel/VBox/SearchRow/SearchBox
@onready var _list:          VBoxContainer = $Panel/VBox/Columns/Scroll/List
@onready var _flag_label:    Label         = $Panel/VBox/Columns/Preview/Header/Flag
@onready var _name_label:    Label         = $Panel/VBox/Columns/Preview/Header/NameTier/Name
@onready var _tier_label:    Label         = $Panel/VBox/Columns/Preview/Header/NameTier/Tier
@onready var _region_label:  Label         = $Panel/VBox/Columns/Preview/Stats/Region
@onready var _gdp_bar:       ProgressBar   = $Panel/VBox/Columns/Preview/Stats/GdpBar
@onready var _mil_bar:       ProgressBar   = $Panel/VBox/Columns/Preview/Stats/MilBar
@onready var _stab_bar:      ProgressBar   = $Panel/VBox/Columns/Preview/Stats/StabBar
@onready var _confirm_btn:   Button        = $Panel/VBox/Columns/Preview/ConfirmButton
@onready var _tip_label:     Label         = $Panel/VBox/Columns/Preview/TipLabel

const TIER_LABELS: Dictionary = {
	"S": "Superpower",
	"A": "Great Power",
	"B": "Regional Power",
	"C": "Minor Nation",
	"D": "Weak State",
}

const TIER_TIPS: Dictionary = {
	"S": "Global reach, massive economy. Everyone watches your every move.",
	"A": "Strong regional influence and a large economy. A serious player.",
	"B": "Dominant in your region. Limited but growing global reach.",
	"C": "Functional state with limited influence. Room to grow.",
	"D": "Hard mode. Instability, poverty, and civil war risk from day one.",
}

var _selected_iso: String = ""
var _all_entries: Array = []
var _row_buttons: Dictionary = {}


func _ready() -> void:
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm)
	_search_box.text_changed.connect(_on_search)
	ProvinceDB.data_loaded.connect(_populate)
	if not ProvinceDB.country_map_data.is_empty():
		_populate()


func _populate() -> void:
	_all_entries = []
	for iso: String in GameState.countries:
		_all_entries.append(GameState.countries[iso])
	# Sort: tier S→D, then alphabetically
	const TIER_ORDER: Dictionary = { "S": 0, "A": 1, "B": 2, "C": 3, "D": 4 }
	_all_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = TIER_ORDER.get(a.get("power_tier", "D"), 4)
		var tb: int = TIER_ORDER.get(b.get("power_tier", "D"), 4)
		if ta != tb:
			return ta < tb
		return a.get("name", "") < b.get("name", "")  # "name" here is a dict key string, not a variable
	)
	_rebuild_list(_all_entries)


func _rebuild_list(entries: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_row_buttons.clear()

	for entry: Dictionary in entries:
		var iso: String = entry.get("iso", "")
		var btn: Button = Button.new()
		btn.text = "%s  %s  [%s]" % [
			entry.get("flag_emoji", ""),
			entry.get("name", iso),
			entry.get("power_tier", "C"),
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.flat = true
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(_on_row_selected.bind(iso))
		_list.add_child(btn)
		_row_buttons[iso] = btn


func _on_search(text: String) -> void:
	var q: String = text.strip_edges().to_lower()
	if q.is_empty():
		_rebuild_list(_all_entries)
		return
	var filtered: Array = _all_entries.filter(func(e: Dictionary) -> bool:
		return e.get("name", "").to_lower().contains(q) \
			or e.get("region", "").to_lower().contains(q) \
			or e.get("iso", "").to_lower().contains(q)
	)
	_rebuild_list(filtered)


func _on_row_selected(iso: String) -> void:
	_selected_iso = iso
	var data: Dictionary = GameState.get_country(iso)
	_flag_label.text  = data.get("flag_emoji", "")
	_name_label.text  = data.get("name", iso)
	var tier: String  = data.get("power_tier", "C")
	_tier_label.text  = TIER_LABELS.get(tier, "")
	_region_label.text = data.get("region", "") + " · " + data.get("subregion", "")
	_gdp_bar.value    = data.get("gdp_normalized", 0)
	_mil_bar.value    = data.get("military_normalized", 0)
	_stab_bar.value   = data.get("stability", 50)
	_tip_label.text   = TIER_TIPS.get(tier, "")
	_confirm_btn.disabled = false
	_confirm_btn.text = "Play as %s" % data.get("name", iso)

	# Highlight on map
	GameState.select_country(iso)


func _on_confirm() -> void:
	if _selected_iso.is_empty():
		return
	GameState.set_player_country(_selected_iso)
	GameState.deselect()
	emit_signal("country_confirmed", _selected_iso)
	queue_free()
