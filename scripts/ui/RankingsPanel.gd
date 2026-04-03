## RankingsPanel.gd
## Country rankings with tabs: Power (default), GDP, Military.
## Power = composite score of GDP + Military + Stability + Population.
extends PanelContainer

var _list_container: VBoxContainer = null
var _tab_btns: Dictionary = {}
var _current_tab: String = "power"
var _title_lbl: Label = null

const BG_COLOR:     Color = Color(0.06, 0.06, 0.08, 0.94)
const HEADER_COLOR: Color = Color(0.85, 0.75, 0.45)
const PLAYER_COLOR: Color = Color(0.3, 0.7, 1.0)
const TEXT_COLOR:   Color = Color(0.82, 0.83, 0.86)
const DIM_COLOR:    Color = Color(0.50, 0.52, 0.55)
const TAB_ACTIVE:   Color = Color(0.85, 0.75, 0.45)
const TAB_INACTIVE: Color = Color(0.45, 0.45, 0.48)
const MAX_ROWS:     int   = 30

const TABS: Array = ["power", "gdp", "military"]
const TAB_LABELS: Dictionary = {
	"power": "POWER", "gdp": "GDP", "military": "MILITARY",
}
const TAB_TITLES: Dictionary = {
	"power": "WORLD POWER RANKINGS",
	"gdp": "GDP RANKINGS",
	"military": "MILITARY RANKINGS",
}


func _ready() -> void:
	custom_minimum_size = Vector2(340, 0)
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

	# Title
	_title_lbl = Label.new()
	_title_lbl.text = TAB_TITLES["power"]
	_title_lbl.add_theme_font_size_override("font_size", 12)
	_title_lbl.add_theme_color_override("font_color", HEADER_COLOR)
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_lbl)

	# Tab buttons
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(tab_row)

	for tab_id: String in TABS:
		var btn := Button.new()
		btn.text = TAB_LABELS[tab_id]
		btn.add_theme_font_size_override("font_size", 10)
		btn.custom_minimum_size = Vector2(70, 22)
		var tid: String = tab_id
		btn.pressed.connect(func() -> void: _switch_tab(tid))
		tab_row.add_child(btn)
		_tab_btns[tab_id] = btn

	vbox.add_child(HSeparator.new())

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 1)
	scroll.add_child(_list_container)

	# Close
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


func _switch_tab(tab_id: String) -> void:
	_current_tab = tab_id
	_title_lbl.text = TAB_TITLES.get(tab_id, "RANKINGS")
	_update_tab_styles()
	_rebuild()


func _update_tab_styles() -> void:
	for tid: String in _tab_btns:
		var btn: Button = _tab_btns[tid]
		if tid == _current_tab:
			btn.add_theme_color_override("font_color", TAB_ACTIVE)
		else:
			btn.add_theme_color_override("font_color", TAB_INACTIVE)


func _rebuild() -> void:
	_update_tab_styles()
	for child: Node in _list_container.get_children():
		child.queue_free()

	# Build sorted list
	var sorted: Array = []
	for iso: String in GameState.countries:
		var d: Dictionary = GameState.countries[iso]
		var gdp: float = float(d.get("gdp_raw_billions", 0.0))
		var mil: float = float(d.get("military_normalized", 0))
		var stab: float = float(d.get("stability", 50))
		var pop: float = float(d.get("population_normalized", 0))

		# Power score: weighted composite
		var power: float = gdp * 0.35 + mil * 0.30 + pop * 0.20 + stab * 0.15

		sorted.append({
			"iso": iso,
			"name": d.get("name", iso),
			"gdp": gdp,
			"mil": mil,
			"stab": stab,
			"pop": pop,
			"power": power,
			"tier": d.get("power_tier", "D"),
			"iso2": d.get("iso2", ""),
		})

	match _current_tab:
		"power":
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a["power"] > b["power"])
		"gdp":
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a["gdp"] > b["gdp"])
		"military":
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a["mil"] > b["mil"])

	var player: String = GameState.player_iso
	var player_rank: int = -1
	var player_in_top: bool = false

	# Find player rank
	for i: int in sorted.size():
		if sorted[i]["iso"] == player:
			player_rank = i
			player_in_top = i < MAX_ROWS
			break

	for i: int in mini(sorted.size(), MAX_ROWS):
		var entry: Dictionary = sorted[i]
		var is_player: bool = entry["iso"] == player
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.custom_minimum_size = Vector2(0, 20)
		_list_container.add_child(row)

		# Rank number
		var rank_col: Color = PLAYER_COLOR if is_player else DIM_COLOR
		var rank_lbl := Label.new()
		rank_lbl.text = "%d." % (i + 1)
		rank_lbl.custom_minimum_size = Vector2(24, 0)
		rank_lbl.add_theme_font_size_override("font_size", 10)
		rank_lbl.add_theme_color_override("font_color", rank_col)
		row.add_child(rank_lbl)

		# Flag
		var flag_path: String = "res://assets/flags/%s.png" % entry["iso2"]
		if not entry["iso2"].is_empty() and ResourceLoader.exists(flag_path):
			var flag := TextureRect.new()
			flag.texture = load(flag_path)
			flag.custom_minimum_size = Vector2(16, 16)
			flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			flag.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			row.add_child(flag)

		# Name
		var name_lbl := Label.new()
		name_lbl.text = entry["name"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", PLAYER_COLOR if is_player else TEXT_COLOR)
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_lbl)

		# Value column (depends on tab)
		var val_text: String
		match _current_tab:
			"power":
				val_text = "%.0f" % entry["power"]
			"gdp":
				val_text = _fmt_gdp(entry["gdp"])
			"military":
				val_text = "%.0f" % entry["mil"]
		var val_lbl := Label.new()
		val_lbl.text = val_text
		val_lbl.custom_minimum_size = Vector2(60, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 10)
		val_lbl.add_theme_color_override("font_color", TEXT_COLOR)
		row.add_child(val_lbl)

		# Tier badge
		var tier_colors: Dictionary = {
			"S": Color(0.95, 0.80, 0.25), "A": Color(0.55, 0.75, 1.0),
			"B": Color(0.45, 0.80, 0.45), "C": Color(0.65, 0.65, 0.65),
			"D": Color(0.75, 0.35, 0.30),
		}
		var tier_lbl := Label.new()
		tier_lbl.text = entry["tier"]
		tier_lbl.custom_minimum_size = Vector2(20, 0)
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_lbl.add_theme_font_size_override("font_size", 10)
		tier_lbl.add_theme_color_override("font_color", tier_colors.get(entry["tier"], DIM_COLOR))
		row.add_child(tier_lbl)

	# If player is not in the top N, add a separator + their row
	if not player_in_top and player_rank >= 0:
		var sep := HSeparator.new()
		_list_container.add_child(sep)

		var dots := Label.new()
		dots.text = "···"
		dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dots.add_theme_font_size_override("font_size", 10)
		dots.add_theme_color_override("font_color", DIM_COLOR)
		_list_container.add_child(dots)

		# Reuse the same row-building logic for player
		var pe: Dictionary = sorted[player_rank]
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 4)
		prow.custom_minimum_size = Vector2(0, 20)
		_list_container.add_child(prow)

		var pr_lbl := Label.new()
		pr_lbl.text = "%d." % (player_rank + 1)
		pr_lbl.custom_minimum_size = Vector2(24, 0)
		pr_lbl.add_theme_font_size_override("font_size", 10)
		pr_lbl.add_theme_color_override("font_color", PLAYER_COLOR)
		prow.add_child(pr_lbl)

		var pflag_path: String = "res://assets/flags/%s.png" % pe["iso2"]
		if not pe["iso2"].is_empty() and ResourceLoader.exists(pflag_path):
			var pflag := TextureRect.new()
			pflag.texture = load(pflag_path)
			pflag.custom_minimum_size = Vector2(16, 16)
			pflag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pflag.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			prow.add_child(pflag)

		var pname := Label.new()
		pname.text = pe["name"]
		pname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pname.add_theme_font_size_override("font_size", 10)
		pname.add_theme_color_override("font_color", PLAYER_COLOR)
		prow.add_child(pname)

		var pval_text: String
		match _current_tab:
			"power": pval_text = "%.0f" % pe["power"]
			"gdp":   pval_text = _fmt_gdp(pe["gdp"])
			_:       pval_text = "%.0f" % pe["mil"]
		var pval := Label.new()
		pval.text = pval_text
		pval.custom_minimum_size = Vector2(60, 0)
		pval.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pval.add_theme_font_size_override("font_size", 10)
		pval.add_theme_color_override("font_color", PLAYER_COLOR)
		prow.add_child(pval)

		var ptier := Label.new()
		ptier.text = pe["tier"]
		ptier.custom_minimum_size = Vector2(20, 0)
		ptier.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ptier.add_theme_font_size_override("font_size", 10)
		ptier.add_theme_color_override("font_color", Color(0.95, 0.80, 0.25))
		prow.add_child(ptier)


func _fmt_gdp(b: float) -> String:
	if b >= 1000.0: return "$%.1fT" % (b / 1000.0)
	if b >= 1.0:    return "$%.1fB" % b
	return "$%.0fM" % (b * 1000.0)
