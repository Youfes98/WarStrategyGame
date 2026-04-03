## CountryCard.gd
## Left-side country info card — clean grand strategy style.
## All children created programmatically for full visual control.
extends PanelContainer

signal country_confirmed(iso: String)

const COL_BG:      Color = Color(0.05, 0.07, 0.11, 0.95)
const COL_BORDER:  Color = Color(0.18, 0.25, 0.38, 0.80)
const COL_HEADER:  Color = Color(0.08, 0.10, 0.16, 1.0)
const COL_DIVIDER: Color = Color(0.20, 0.26, 0.38, 0.50)
const COL_TEXT:    Color = Color(0.90, 0.92, 0.96)
const COL_DIM:     Color = Color(0.55, 0.58, 0.65)
const COL_VALUE:   Color = Color(0.80, 0.85, 0.92)
const COL_BAR_BG:  Color = Color(0.12, 0.14, 0.20)
const COL_WAR:     Color = Color(0.85, 0.20, 0.20)
const COL_PEACE:   Color = Color(0.25, 0.75, 0.40)
const COL_CONFIRM: Color = Color(0.20, 0.55, 0.95)

const TIER_LABELS: Dictionary = {
	"S": "SUPERPOWER", "A": "GREAT POWER",
	"B": "REGIONAL", "C": "MINOR", "D": "WEAK",
}
const TIER_COLORS: Dictionary = {
	"S": Color(1.0, 0.85, 0.2),  "A": Color(0.6, 0.8, 1.0),
	"B": Color(0.5, 0.85, 0.5),  "C": Color(0.65, 0.65, 0.65),
	"D": Color(0.6, 0.42, 0.42),
}

var _picking_mode: bool = false

var _vbox:        VBoxContainer = null
var _detail_lbl:  Label = null  # Extra info shown only in picking mode
var _flag_lbl:    Label = null
var _flag_tex:    TextureRect = null
var _name_lbl:    Label = null
var _tier_lbl:    Label = null
var _gov_lbl:     Label = null
var _gdp_lbl:     Label = null
var _pop_lbl:     Label = null
var _mil_lbl:     Label = null
var _stab_bar:    ProgressBar = null
var _stab_val:    Label = null
var _econ_bar:    ProgressBar = null
var _econ_val:    Label = null
var _mil_bar:     ProgressBar = null
var _mil_val:     Label = null
var _war_btn:     Button = null
var _peace_btn:   Button = null
var _confirm_btn: Button = null


func _ready() -> void:
	custom_minimum_size = Vector2(260, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	# Remove any scene-defined children (allows clean .tscn)
	for child in get_children():
		child.queue_free()

	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 0)
	add_child(_vbox)

	_build_header()
	_build_stats()
	_build_bars()
	_build_actions()

	GameState.country_selected.connect(_on_selected)
	GameState.country_deselected.connect(_on_deselected)
	GameState.country_data_changed.connect(_on_data_changed)
	UIManager.panel_unlocked.connect(_on_panel_unlocked)


func _build_header() -> void:
	var header_panel := PanelContainer.new()
	var h_style := StyleBoxFlat.new()
	h_style.bg_color = COL_HEADER
	h_style.content_margin_left = 12
	h_style.content_margin_right = 12
	h_style.content_margin_top = 10
	h_style.content_margin_bottom = 8
	header_panel.add_theme_stylebox_override("panel", h_style)
	_vbox.add_child(header_panel)

	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header_panel.add_child(header_vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	header_vbox.add_child(name_row)

	# Flag image (circular PNG)
	_flag_tex = TextureRect.new()
	_flag_tex.custom_minimum_size = Vector2(42, 42)
	_flag_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	name_row.add_child(_flag_tex)

	# Fallback emoji label (hidden when flag image loads)
	_flag_lbl = Label.new()
	_flag_lbl.add_theme_font_size_override("font_size", 28)
	_flag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flag_lbl.visible = false
	name_row.add_child(_flag_lbl)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 0)
	name_row.add_child(name_col)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 15)
	_name_lbl.add_theme_color_override("font_color", COL_TEXT)
	name_col.add_child(_name_lbl)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	name_col.add_child(tag_row)

	_tier_lbl = Label.new()
	_tier_lbl.add_theme_font_size_override("font_size", 9)
	tag_row.add_child(_tier_lbl)

	_gov_lbl = Label.new()
	_gov_lbl.add_theme_font_size_override("font_size", 9)
	_gov_lbl.add_theme_color_override("font_color", COL_DIM)
	tag_row.add_child(_gov_lbl)


func _build_stats() -> void:
	var stats_margin := MarginContainer.new()
	stats_margin.add_theme_constant_override("margin_left", 12)
	stats_margin.add_theme_constant_override("margin_right", 12)
	stats_margin.add_theme_constant_override("margin_top", 8)
	stats_margin.add_theme_constant_override("margin_bottom", 4)
	_vbox.add_child(stats_margin)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 4)
	stats_margin.add_child(stats_grid)

	_gdp_lbl = _add_stat_row(stats_grid, "GDP")
	_pop_lbl = _add_stat_row(stats_grid, "Population")
	_mil_lbl = _add_stat_row(stats_grid, "Military")


func _add_stat_row(parent: Node, label_text: String) -> Label:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COL_DIM)
	lbl.custom_minimum_size = Vector2(70, 0)
	parent.add_child(lbl)

	var val := Label.new()
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color", COL_VALUE)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(val)
	return val


func _build_bars() -> void:
	var div := ColorRect.new()
	div.color = COL_DIVIDER
	div.custom_minimum_size = Vector2(0, 1)
	_vbox.add_child(div)

	var bars_margin := MarginContainer.new()
	bars_margin.add_theme_constant_override("margin_left", 12)
	bars_margin.add_theme_constant_override("margin_right", 12)
	bars_margin.add_theme_constant_override("margin_top", 6)
	bars_margin.add_theme_constant_override("margin_bottom", 4)
	_vbox.add_child(bars_margin)

	var bars_vbox := VBoxContainer.new()
	bars_vbox.add_theme_constant_override("separation", 6)
	bars_margin.add_child(bars_vbox)

	var stab_pair := _make_bar_row(bars_vbox, "Stability", 100)
	_stab_bar = stab_pair[0]
	_stab_val = stab_pair[1]

	var econ_pair := _make_bar_row(bars_vbox, "Economy", 1000)
	_econ_bar = econ_pair[0]
	_econ_val = econ_pair[1]

	var mil_pair := _make_bar_row(bars_vbox, "Military", 1000)
	_mil_bar = mil_pair[0]
	_mil_val = mil_pair[1]


func _make_bar_row(parent: Node, label_text: String, max_val: int) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", COL_DIM)
	lbl.custom_minimum_size = Vector2(56, 0)
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.max_value = max_val
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = COL_BAR_BG
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = COL_CONFIRM
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	row.add_child(bar)

	var val := Label.new()
	val.add_theme_font_size_override("font_size", 9)
	val.add_theme_color_override("font_color", COL_VALUE)
	val.custom_minimum_size = Vector2(32, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)

	return [bar, val]


func _build_actions() -> void:
	# Detailed info (only visible in picking mode)
	_detail_lbl = Label.new()
	_detail_lbl.add_theme_font_size_override("font_size", 11)
	_detail_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lbl.visible = false
	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 12)
	detail_margin.add_theme_constant_override("margin_right", 12)
	detail_margin.add_child(_detail_lbl)
	_vbox.add_child(detail_margin)

	var div := ColorRect.new()
	div.color = COL_DIVIDER
	div.custom_minimum_size = Vector2(0, 1)
	_vbox.add_child(div)

	var action_margin := MarginContainer.new()
	action_margin.add_theme_constant_override("margin_left", 12)
	action_margin.add_theme_constant_override("margin_right", 12)
	action_margin.add_theme_constant_override("margin_top", 6)
	action_margin.add_theme_constant_override("margin_bottom", 2)
	_vbox.add_child(action_margin)

	var action_vbox := VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 4)
	action_margin.add_child(action_vbox)

	_war_btn = _make_action_btn("Declare War", COL_WAR)
	_war_btn.pressed.connect(_on_declare_war)
	_war_btn.visible = false
	action_vbox.add_child(_war_btn)

	_peace_btn = _make_action_btn("Sue for Peace", COL_PEACE)
	_peace_btn.pressed.connect(_on_sue_for_peace)
	_peace_btn.visible = false
	action_vbox.add_child(_peace_btn)

	_confirm_btn = _make_action_btn("Play as ...", COL_CONFIRM)
	_confirm_btn.pressed.connect(_on_confirm)
	_confirm_btn.visible = false
	action_vbox.add_child(_confirm_btn)


func _make_action_btn(btn_text: String, col: Color) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 12)
	var style := StyleBoxFlat.new()
	style.bg_color = col.darkened(0.5)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = col.darkened(0.3)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = col.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", col.lightened(0.4))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	return btn


func set_picking_mode(enabled: bool) -> void:
	_picking_mode = enabled
	custom_minimum_size.x = 320 if enabled else 260


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


func _on_panel_unlocked(_panel_name: String, _state: UIManager.PanelState) -> void:
	if not GameState.selected_iso.is_empty():
		_refresh(GameState.selected_iso, GameState.get_country(GameState.selected_iso))


func _refresh(iso: String, data: Dictionary) -> void:
	# Load flag image
	var iso2: String = data.get("iso2", "")
	var flag_path: String = "res://assets/flags/%s.png" % iso2
	if not iso2.is_empty() and ResourceLoader.exists(flag_path):
		_flag_tex.texture = load(flag_path)
		_flag_tex.visible = true
		_flag_lbl.visible = false
	else:
		_flag_tex.visible = false
		_flag_lbl.visible = true
		var flag: String = data.get("flag_emoji", "")
		if flag.is_empty() and iso2.length() == 2:
			flag = String.chr(0x1F1E6 + iso2.unicode_at(0) - 65) + String.chr(0x1F1E6 + iso2.unicode_at(1) - 65)
		_flag_lbl.text = flag
	_name_lbl.text = data.get("name", iso)

	var tier: String = data.get("power_tier", "C")
	_tier_lbl.text = TIER_LABELS.get(tier, tier)
	_tier_lbl.add_theme_color_override("font_color", TIER_COLORS.get(tier, COL_DIM))

	_gov_lbl.text = data.get("government_type", "Unknown").capitalize()

	_gdp_lbl.text = _fmt_gdp(float(data.get("gdp_raw_billions", 0.0)))
	_pop_lbl.text = _fmt_pop(int(data.get("population", 0)))
	_mil_lbl.text = _fmt_military(iso, data)

	var stab: float = float(data.get("stability", 50.0))
	_stab_bar.value = stab
	_stab_val.text = "%d" % int(stab)
	_color_bar(_stab_bar, stab, 100.0)

	_econ_bar.value = data.get("gdp_normalized", 0)
	_econ_val.text = "%d" % int(data.get("gdp_normalized", 0))

	_mil_bar.value = data.get("military_normalized", 0)
	_mil_val.text = "%d" % int(data.get("military_normalized", 0))

	if _picking_mode:
		_confirm_btn.text = "Play as %s" % data.get("name", iso)
		_confirm_btn.visible = true
		_war_btn.visible = false
		_peace_btn.visible = false
		# Show detailed info
		if _detail_lbl:
			_detail_lbl.visible = true
			var capital: String = data.get("capital", "Unknown")
			var debt: float = data.get("debt_to_gdp", 0.0)
			var infra: int = int(data.get("infrastructure", 0))
			var literacy: int = int(data.get("literacy_rate", 0))
			var area: float = data.get("area_km2", 0.0)
			var landlocked: bool = data.get("landlocked", false)
			var n_provs: int = ProvinceDB.get_country_province_ids(iso).size()
			var neighbors: Array = data.get("borders", [])
			var area_str: String = "%dK km²" % int(area / 1000) if area >= 1000 else "%d km²" % int(area)
			_detail_lbl.text = (
				"Capital: %s\n" % capital +
				"Area: %s  |  Provinces: %d\n" % [area_str, n_provs] +
				"Debt/GDP: %.0f%%  |  Infrastructure: %d%%\n" % [debt, infra] +
				"Literacy: %d%%  |  %s\n" % [literacy, "Landlocked" if landlocked else "Sea access"] +
				"Neighbors: %d countries" % neighbors.size()
			)
	elif not GameState.player_iso.is_empty() and iso != GameState.player_iso:
		if _detail_lbl:
			_detail_lbl.visible = false
		var ter_owner: String = GameState.get_country_owner(iso)
		if ter_owner == GameState.player_iso:
			_war_btn.visible = false
			_peace_btn.visible = false
		else:
			var at_war: bool = GameState.is_at_war(GameState.player_iso, iso)
			_war_btn.visible = not at_war
			_peace_btn.visible = at_war
		_confirm_btn.visible = false
	else:
		_war_btn.visible = false
		_peace_btn.visible = false
		_confirm_btn.visible = false


func _color_bar(bar: ProgressBar, value: float, max_val: float) -> void:
	var ratio: float = value / maxf(max_val, 1.0)
	var col: Color
	if ratio > 0.7:
		col = Color(0.20, 0.70, 0.35)
	elif ratio > 0.4:
		col = Color(0.80, 0.70, 0.15)
	else:
		col = Color(0.80, 0.25, 0.20)
	var fill := bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	fill.bg_color = col
	bar.add_theme_stylebox_override("fill", fill)


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
	UIManager.push_notification("War declared against %s." % GameState.get_country(iso).get("name", iso), "warning")
	_refresh(iso, GameState.get_country(iso))


func _on_sue_for_peace() -> void:
	var iso: String = GameState.selected_iso
	if iso.is_empty() or GameState.player_iso.is_empty():
		return
	GameState.set_war(GameState.player_iso, iso, false)
	UIManager.push_notification("Peace with %s." % GameState.get_country(iso).get("name", iso), "info")
	_refresh(iso, GameState.get_country(iso))


func _fmt_gdp(b: float) -> String:
	if b >= 1000.0: return "$%.2fT" % (b / 1000.0)
	if b >= 1.0:    return "$%.1fB" % b
	return "$%.0fM" % (b * 1000.0)

func _fmt_pop(p: int) -> String:
	if p >= 1_000_000_000: return "%.2fB" % (p / 1_000_000_000.0)
	if p >= 1_000_000:     return "%.1fM" % (p / 1_000_000.0)
	if p >= 1_000:         return "%.0fK" % (p / 1_000.0)
	return str(p)

func _fmt_military(iso: String, _data: Dictionary) -> String:
	var player: String = GameState.player_iso
	if not player.is_empty():
		var unit_count: int = 0
		if ProvinceDB.has_provinces():
			for pid: String in ProvinceDB.get_country_province_ids(iso):
				unit_count += MilitarySystem.get_units_at(pid).size()
		else:
			unit_count = MilitarySystem.get_units_at(iso).size()
		if unit_count > 0:
			return "%d units" % unit_count
	var normalized: int = int(_data.get("military_normalized", 0))
	if normalized >= 800: return "Massive"
	if normalized >= 500: return "Large"
	if normalized >= 200: return "Moderate"
	if normalized >= 50:  return "Small"
	return "Minimal"
