## CountryCard.gd
extends PanelContainer

signal country_confirmed(iso: String)

@onready var _flag_label:    Label       = $VBox/Header/Flag
@onready var _name_label:    Label       = $VBox/Header/Name
@onready var _tier_label:    Label       = $VBox/Header/Tier
@onready var _stats:         VBoxContainer = $VBox/Stats
@onready var _gdp_value:     Label       = $VBox/Stats/GDPRow/GDPValue
@onready var _pop_value:     Label       = $VBox/Stats/PopRow/PopValue
@onready var _troops_value:  Label       = $VBox/Stats/TroopsRow/TroopsValue
@onready var _stab_value:    Label       = $VBox/Stats/StabRow/StabValue
@onready var _gov_value:     Label       = $VBox/Stats/GovRow/GovValue
@onready var _sep2:          HSeparator  = $VBox/Sep2
@onready var _bars:          VBoxContainer = $VBox/Bars
@onready var _econ_bar:      ProgressBar = $VBox/Bars/EconBar
@onready var _stability_bar: ProgressBar = $VBox/Bars/StabilityBar
@onready var _military_bar:  ProgressBar = $VBox/Bars/MilitaryBar
@onready var _war_btn:       Button      = $VBox/WarButton
@onready var _peace_btn:     Button      = $VBox/PeaceButton
@onready var _confirm_btn:   Button      = $VBox/ConfirmButton

const TIER_LABELS: Dictionary = {
	"S": "Superpower", "A": "Great Power",
	"B": "Regional Power", "C": "Minor Nation", "D": "Weak State",
}

var _picking_mode: bool = false


func _ready() -> void:
	GameState.country_selected.connect(_on_selected)
	GameState.country_deselected.connect(_on_deselected)
	GameState.country_data_changed.connect(_on_data_changed)
	UIManager.panel_unlocked.connect(_on_panel_unlocked)
	_stats.visible       = false
	_sep2.visible        = false
	_bars.visible        = false
	_war_btn.visible     = false
	_peace_btn.visible   = false
	_confirm_btn.visible = false
	_war_btn.pressed.connect(_on_declare_war)
	_peace_btn.pressed.connect(_on_sue_for_peace)
	_confirm_btn.pressed.connect(_on_confirm)
	visible = false


func set_picking_mode(enabled: bool) -> void:
	_picking_mode = enabled


func _on_selected(iso: String) -> void:
	var data: Dictionary = GameState.get_country(iso)
	if data.is_empty():
		return
	visible = true
	_refresh(iso, data)


func _on_deselected() -> void:
	visible = false


func _on_data_changed(iso: String) -> void:
	if iso == GameState.selected_iso and visible:
		_refresh(iso, GameState.get_country(iso))


func _on_panel_unlocked(panel_name: String, _state: UIManager.PanelState) -> void:
	if panel_name == "economy" and not GameState.selected_iso.is_empty():
		_sep2.visible = true
		_bars.visible = true
		_refresh_bars(GameState.get_country(GameState.selected_iso))


func _refresh(iso: String, data: Dictionary) -> void:
	var flag: String = data.get("flag_emoji", "")
	if flag.is_empty():
		var iso2: String = data.get("iso2", "")
		if iso2.length() == 2:
			flag = String.chr(0x1F1E6 + iso2.unicode_at(0) - 65) + String.chr(0x1F1E6 + iso2.unicode_at(1) - 65)
	_flag_label.text = flag
	_name_label.text = data.get("name", iso)

	var tier: String = data.get("power_tier", "C")
	_tier_label.text = TIER_LABELS.get(tier, tier)
	_tier_label.add_theme_color_override("font_color", _tier_color(tier))

	# Stats rows — always visible once card is shown
	_stats.visible = true

	_gdp_value.text    = _fmt_gdp(float(data.get("gdp_raw_billions", 0.0)))
	_pop_value.text    = _fmt_pop(int(data.get("population", 0)))
	_troops_value.text = _fmt_military(int(data.get("military_normalized", 0)), tier)

	var stab: float = float(data.get("stability", 50.0))
	_stab_value.text = "%.0f / 100" % stab
	_stab_value.add_theme_color_override("font_color", _stab_color(stab))

	_gov_value.text = data.get("government_type", "Unknown")

	if _picking_mode:
		_confirm_btn.text    = "Play as %s" % data.get("name", iso)
		_confirm_btn.visible = true
		_war_btn.visible     = false
		_peace_btn.visible   = false
	elif not GameState.player_iso.is_empty() and iso != GameState.player_iso:
		var ter_owner: String = GameState.get_country_owner(iso)
		if ter_owner == GameState.player_iso:
			# We own this country's territory — no diplomatic buttons
			_war_btn.visible     = false
			_peace_btn.visible   = false
		else:
			var at_war: bool = GameState.is_at_war(GameState.player_iso, iso)
			_war_btn.visible   = not at_war
			_peace_btn.visible = at_war
		_confirm_btn.visible = false
	else:
		_war_btn.visible     = false
		_peace_btn.visible   = false
		_confirm_btn.visible = false

	if UIManager.get_panel_state("economy") >= UIManager.PanelState.MINIMAL:
		_sep2.visible = true
		_bars.visible = true
		_refresh_bars(data)


func _refresh_bars(data: Dictionary) -> void:
	_econ_bar.value      = data.get("gdp_normalized", 0)
	_stability_bar.value = data.get("stability", 50)
	_military_bar.value  = data.get("military_normalized", 0)


func _on_confirm() -> void:
	var iso: String = GameState.selected_iso
	if iso.is_empty():
		return
	emit_signal("country_confirmed", iso)


func _on_declare_war() -> void:
	var iso: String = GameState.selected_iso
	if iso.is_empty() or GameState.player_iso.is_empty():
		return
	GameState.set_war(GameState.player_iso, iso, true)
	var cname: String = GameState.get_country(iso).get("name", iso)
	UIManager.push_notification("War declared against %s." % cname, "warning")
	_refresh(iso, GameState.get_country(iso))


func _on_sue_for_peace() -> void:
	var iso: String = GameState.selected_iso
	if iso.is_empty() or GameState.player_iso.is_empty():
		return
	GameState.set_war(GameState.player_iso, iso, false)
	var cname: String = GameState.get_country(iso).get("name", iso)
	UIManager.push_notification("Peace with %s." % cname, "info")
	_refresh(iso, GameState.get_country(iso))


# ── Formatters ──────────────────────────────────────────────────────────────

func _fmt_gdp(b: float) -> String:
	if b >= 1000.0: return "$%.2fT" % (b / 1000.0)
	if b >= 1.0:    return "$%.1fB" % b
	return "$%.0fM" % (b * 1000.0)


func _fmt_pop(p: int) -> String:
	if p >= 1_000_000_000: return "%.2fB" % (p / 1_000_000_000.0)
	if p >= 1_000_000:     return "%.1fM" % (p / 1_000_000.0)
	if p >= 1_000:         return "%.0fK" % (p / 1_000.0)
	return str(p)


func _fmt_military(normalized: int, _tier: String) -> String:
	var player: String = GameState.player_iso
	if not player.is_empty():
		var iso: String = GameState.selected_iso
		var unit_count: int = 0
		if ProvinceDB.has_provinces():
			for pid: String in ProvinceDB.get_country_province_ids(iso):
				unit_count += MilitarySystem.get_units_at(pid).size()
		else:
			unit_count = MilitarySystem.get_units_at(iso).size()
		if unit_count > 0:
			return "%d units" % unit_count
	if normalized >= 800: return "Massive"
	if normalized >= 500: return "Large"
	if normalized >= 200: return "Moderate"
	if normalized >= 50:  return "Small"
	return "Minimal"


# ── Color helpers ────────────────────────────────────────────────────────────

func _tier_color(tier: String) -> Color:
	match tier:
		"S": return Color(1.0, 0.85, 0.2)
		"A": return Color(0.7, 0.85, 1.0)
		"B": return Color(0.55, 0.9, 0.55)
		"C": return Color(0.75, 0.75, 0.75)
		_:   return Color(0.6, 0.45, 0.45)


func _stab_color(stab: float) -> Color:
	if stab >= 70: return Color(0.4, 0.9, 0.4)
	if stab >= 40: return Color(0.9, 0.85, 0.3)
	return Color(0.95, 0.35, 0.3)
