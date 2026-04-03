## ResourceBar.gd
## Top-left HUD strip — shows the player's spendable resources at a glance.
## Appears after the player confirms their country.
extends PanelContainer

var _treasury_lbl: Label = null
var _income_lbl:   Label = null
var _stab_lbl:     Label = null

var _prev_gdp:    float = 0.0
var _gdp_month_start: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 36)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)

	# Treasury
	var t_col := VBoxContainer.new()
	hbox.add_child(t_col)

	var t_hdr := Label.new()
	t_hdr.text = "TREASURY"
	t_hdr.add_theme_font_size_override("font_size", 9)
	t_hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	t_col.add_child(t_hdr)

	_treasury_lbl = Label.new()
	_treasury_lbl.add_theme_font_size_override("font_size", 13)
	_treasury_lbl.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	t_col.add_child(_treasury_lbl)

	hbox.add_child(VSeparator.new())

	# Monthly income / change
	var i_col := VBoxContainer.new()
	hbox.add_child(i_col)

	var i_hdr := Label.new()
	i_hdr.text = "MONTHLY"
	i_hdr.add_theme_font_size_override("font_size", 9)
	i_hdr.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	i_col.add_child(i_hdr)

	_income_lbl = Label.new()
	_income_lbl.add_theme_font_size_override("font_size", 13)
	i_col.add_child(_income_lbl)

	hbox.add_child(VSeparator.new())

	# Stability
	var s_col := VBoxContainer.new()
	hbox.add_child(s_col)

	var s_hdr := Label.new()
	s_hdr.text = "STABILITY"
	s_hdr.add_theme_font_size_override("font_size", 9)
	s_hdr.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	s_col.add_child(s_hdr)

	_stab_lbl = Label.new()
	_stab_lbl.add_theme_font_size_override("font_size", 13)
	s_col.add_child(_stab_lbl)

	GameState.player_country_set.connect(_on_player_set)
	GameState.country_data_changed.connect(_on_data_changed)
	GameClock.tick_month.connect(_on_month)
	visible = false


func _on_player_set(iso: String) -> void:
	visible = true
	var data: Dictionary = GameState.get_country(iso)
	_prev_gdp = float(data.get("gdp_raw_billions", 0.0))
	_gdp_month_start = _prev_gdp
	_refresh(iso)


func _on_data_changed(iso: String) -> void:
	if iso == GameState.player_iso:
		_refresh(iso)


func _on_month(_date: Dictionary) -> void:
	var iso: String = GameState.player_iso
	if iso.is_empty():
		return
	var gdp: float = float(GameState.get_country(iso).get("gdp_raw_billions", 0.0))
	_gdp_month_start = gdp   # reset baseline for next month's delta


func _refresh(iso: String) -> void:
	var data: Dictionary = GameState.get_country(iso)
	var gdp:  float      = float(data.get("gdp_raw_billions", 0.0))
	var stab: float      = float(data.get("stability", 50.0))

	_treasury_lbl.text = _fmt(gdp)

	var delta: float = gdp - _gdp_month_start
	if absf(delta) < 0.001:
		_income_lbl.text = "—"
		_income_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	elif delta >= 0:
		_income_lbl.text = "+%s" % _fmt(delta)
		_income_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	else:
		_income_lbl.text = "-%s" % _fmt(absf(delta))
		_income_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))

	_stab_lbl.text = "%.0f / 100" % stab
	var stab_col: Color
	if stab >= 70:
		stab_col = Color(0.4, 0.9, 0.5)
	elif stab >= 40:
		stab_col = Color(0.9, 0.85, 0.3)
	else:
		stab_col = Color(0.95, 0.35, 0.25)
	_stab_lbl.add_theme_color_override("font_color", stab_col)


func _fmt(b: float) -> String:
	if b >= 1000.0: return "$%.2fT" % (b / 1000.0)
	if b >= 1.0:    return "$%.1fB" % b
	return "$%.0fM" % (b * 1000.0)
