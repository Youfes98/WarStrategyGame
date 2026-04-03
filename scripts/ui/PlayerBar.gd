## PlayerBar.gd
## Bottom HUD strip — shows the player's live country stats.
## All children created programmatically so no child nodes are needed in Main.tscn.
extends PanelContainer

var _flag_lbl:  Label = null
var _name_lbl:  Label = null
var _tier_lbl:  Label = null
var _gdp_lbl:   Label = null
var _tax_lbl:   Label = null
var _stab_lbl:  Label = null
var _debt_lbl:  Label = null

var _prev_gdp: float = 0.0


func _ready() -> void:
	var hbox := HBoxContainer.new()
	hbox.anchors_preset = Control.PRESET_FULL_RECT
	add_child(hbox)

	_flag_lbl = _make_label("🏳", 32)
	hbox.add_child(_flag_lbl)

	_name_lbl = _make_label("—", 140)
	_name_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(_name_lbl)

	_tier_lbl = _make_label("", 100)
	_tier_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	hbox.add_child(_tier_lbl)

	hbox.add_child(VSeparator.new())

	_gdp_lbl = _make_label("GDP  —", 180)
	_gdp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_gdp_lbl)

	hbox.add_child(VSeparator.new())

	_tax_lbl = _make_label("Tax  —", 80)
	hbox.add_child(_tax_lbl)

	hbox.add_child(VSeparator.new())

	_stab_lbl = _make_label("Stability  —", 130)
	_stab_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_stab_lbl)

	hbox.add_child(VSeparator.new())

	_debt_lbl = _make_label("Debt / GDP  —", 140)
	_debt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_debt_lbl)

	GameState.player_country_set.connect(_on_player_set)
	GameState.country_data_changed.connect(_on_data_changed)


func _make_label(default_text: String, min_width: int) -> Label:
	var lbl := Label.new()
	lbl.text = default_text
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(min_width, 0)
	return lbl


func _on_player_set(iso: String) -> void:
	visible = true
	var data: Dictionary = GameState.get_country(iso)
	_prev_gdp = float(data.get("gdp_raw_billions", 0.0))
	_refresh(iso)


func _on_data_changed(iso: String) -> void:
	if iso == GameState.player_iso:
		_refresh(iso)


func _refresh(iso: String) -> void:
	var data: Dictionary = GameState.get_country(iso)
	if data.is_empty():
		return

	_flag_lbl.text = data.get("flag_emoji", "")
	_name_lbl.text = data.get("name", iso)

	const TIER_NAMES: Dictionary = {
		"S": "Superpower", "A": "Great Power",
		"B": "Regional Power", "C": "Minor Nation", "D": "Weak State"
	}
	var tier: String = data.get("power_tier", "C")
	_tier_lbl.text = TIER_NAMES.get(tier, tier)

	var gdp: float       = float(data.get("gdp_raw_billions", 0.0))
	var delta_pct: float = (gdp - _prev_gdp) / maxf(_prev_gdp, 0.001) * 100.0
	_prev_gdp            = gdp
	var change: String   = ""
	if absf(delta_pct) > 0.001:
		change = "  ▲ +%.2f%%" % delta_pct if delta_pct > 0 else "  ▼ %.2f%%" % delta_pct
	_gdp_lbl.text = "GDP  %s%s" % [_fmt_gdp(gdp), change]

	var tax: float = float(data.get("tax_rate", 0.25)) * 100.0
	_tax_lbl.text = "Tax  %.0f%%" % tax

	var stab: float = float(data.get("stability", 50.0))
	_stab_lbl.text = "Stability  %.0f / 100" % stab

	var debt: float = float(data.get("debt_to_gdp", 0.0))
	_debt_lbl.text = "Debt / GDP  %.0f%%" % debt


func _fmt_gdp(b: float) -> String:
	if b >= 1000.0: return "$%.2fT" % (b / 1000.0)
	if b >= 1.0:    return "$%.1fB" % b
	return "$%.0fM" % (b * 1000.0)
