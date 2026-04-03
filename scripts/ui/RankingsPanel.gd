## RankingsPanel.gd
## GDP leaderboard — shows all countries ranked by GDP.
## Opened by clicking the flag/name area in ResourceBar.
extends PanelContainer

var _list_container: VBoxContainer = null
var _rows: Array = []

const BG_COLOR:     Color = Color(0.06, 0.06, 0.08, 0.94)
const HEADER_COLOR: Color = Color(0.85, 0.75, 0.45)
const PLAYER_COLOR: Color = Color(0.3, 0.7, 1.0)
const TEXT_COLOR:   Color = Color(0.82, 0.83, 0.86)
const DIM_COLOR:    Color = Color(0.50, 0.52, 0.55)
const MAX_ROWS:     int   = 20


func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = "WORLD RANKINGS — GDP"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Header row
	var hdr_row := HBoxContainer.new()
	vbox.add_child(hdr_row)
	_add_label(hdr_row, "#", 24, 9, DIM_COLOR)
	_add_label(hdr_row, "Country", 150, 9, DIM_COLOR, true)
	_add_label(hdr_row, "GDP", 70, 9, DIM_COLOR)
	_add_label(hdr_row, "Tier", 50, 9, DIM_COLOR)

	vbox.add_child(HSeparator.new())

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 2)
	scroll.add_child(_list_container)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func() -> void: visible = false)
	vbox.add_child(close_btn)

	GameState.player_country_set.connect(func(_iso: String) -> void: _rebuild())
	GameClock.tick_month.connect(func(_d: Dictionary) -> void:
		if visible:
			_rebuild())


func show_rankings() -> void:
	visible = not visible
	if visible:
		_rebuild()


func _rebuild() -> void:
	# Clear old rows
	for child: Node in _list_container.get_children():
		child.queue_free()

	# Sort countries by GDP descending
	var sorted: Array = []
	for iso: String in GameState.countries:
		var data: Dictionary = GameState.countries[iso]
		sorted.append({
			"iso": iso,
			"name": data.get("name", iso),
			"gdp": float(data.get("gdp_raw_billions", 0.0)),
			"tier": data.get("power_tier", "D"),
			"iso2": data.get("iso2", ""),
		})
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["gdp"] > b["gdp"])

	var player: String = GameState.player_iso

	for i: int in mini(sorted.size(), MAX_ROWS):
		var entry: Dictionary = sorted[i]
		var is_player: bool = entry["iso"] == player
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_list_container.add_child(row)

		# Highlight player row
		if is_player:
			var bg := ColorRect.new()
			bg.color = Color(0.15, 0.30, 0.50, 0.30)
			bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(bg)

		# Rank
		var rank_col: Color = PLAYER_COLOR if is_player else DIM_COLOR
		_add_label(row, "%d." % (i + 1), 24, 11, rank_col)

		# Flag + Name
		var name_hbox := HBoxContainer.new()
		name_hbox.add_theme_constant_override("separation", 4)
		name_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_hbox.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_hbox)

		var flag_path: String = "res://assets/flags/%s.png" % entry["iso2"]
		if not entry["iso2"].is_empty() and ResourceLoader.exists(flag_path):
			var flag := TextureRect.new()
			flag.texture = load(flag_path)
			flag.custom_minimum_size = Vector2(16, 16)
			flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			flag.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			name_hbox.add_child(flag)

		var name_col: Color = PLAYER_COLOR if is_player else TEXT_COLOR
		_add_label(name_hbox, entry["name"], 0, 11, name_col, true)

		# GDP
		_add_label(row, _fmt_gdp(entry["gdp"]), 70, 11, TEXT_COLOR)

		# Tier
		var tier_colors: Dictionary = {
			"S": Color(0.95, 0.80, 0.25), "A": Color(0.55, 0.75, 1.0),
			"B": Color(0.45, 0.80, 0.45), "C": Color(0.65, 0.65, 0.65),
			"D": Color(0.75, 0.35, 0.30),
		}
		_add_label(row, entry["tier"], 50, 11, tier_colors.get(entry["tier"], DIM_COLOR))


func _add_label(parent: Node, text: String, min_w: int, font_size: int,
		col: Color, expand: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	if min_w > 0:
		lbl.custom_minimum_size = Vector2(min_w, 0)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(lbl)
	return lbl


func _fmt_gdp(b: float) -> String:
	if b >= 1000.0: return "$%.1fT" % (b / 1000.0)
	if b >= 1.0:    return "$%.1fB" % b
	return "$%.0fM" % (b * 1000.0)
