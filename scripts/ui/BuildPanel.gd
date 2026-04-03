## BuildPanel.gd
## Modern building construction panel. Press V to toggle.
## Three views: Queue + Categories → Province Selection → Confirmation.
extends PanelContainer

var _main_vbox: VBoxContainer = null
var _selected_type: String = ""

const BG:          Color = Color(0.06, 0.06, 0.08, 0.94)
const HEADER:      Color = Color(0.85, 0.75, 0.45)
const TEXT:        Color = Color(0.85, 0.86, 0.90)
const DIM:         Color = Color(0.48, 0.50, 0.54)
const ACCENT:      Color = Color(0.35, 0.75, 1.0)
const GREEN:       Color = Color(0.35, 0.80, 0.40)
const RED:         Color = Color(0.85, 0.35, 0.30)
const BAR_BG:      Color = Color(0.15, 0.15, 0.18, 0.80)
const BAR_FILL:    Color = Color(0.30, 0.70, 0.35, 0.90)
const CAT_COLORS: Dictionary = {
	"military": Color(0.85, 0.40, 0.35),
	"economic": Color(0.40, 0.80, 0.45),
	"social":   Color(0.45, 0.70, 1.0),
	"research": Color(0.85, 0.70, 0.30),
	"special":  Color(0.70, 0.50, 0.85),
}


func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	_main_vbox = VBoxContainer.new()
	_main_vbox.add_theme_constant_override("separation", 6)
	add_child(_main_vbox)

	call_deferred("_connect_signals")


func _connect_signals() -> void:
	var bs: Node = get_node_or_null("/root/BuildingSystem")
	if bs != null:
		bs.building_completed.connect(func(_p: String, _t: String) -> void: _refresh())
		bs.construction_started.connect(func(_p: String, _t: String) -> void: _refresh())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_V and GameState.player_iso != "":
			visible = not visible
			if visible:
				_show_main()
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _selected_type.is_empty():
		_show_main()
	else:
		_show_provinces(_selected_type)


func _clear() -> void:
	for child: Node in _main_vbox.get_children():
		child.queue_free()


func _bs() -> Node:
	return get_node_or_null("/root/BuildingSystem")


# ── MAIN VIEW: Queue + Building Categories ────────────────────────────────────

func _show_main() -> void:
	_clear()
	_selected_type = ""

	# Title bar
	var title_row := HBoxContainer.new()
	_main_vbox.add_child(title_row)
	var title := Label.new()
	title.text = "CONSTRUCTION"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(func() -> void: visible = false)
	title_row.add_child(close_btn)

	# ── Construction Queue ──
	var bs: Node = _bs()
	var queue: Array = bs.get_queue(GameState.player_iso) if bs != null else []
	var max_q: int = bs._get_max_queue(GameState.player_iso) if bs != null else 2

	var q_header := Label.new()
	q_header.text = "QUEUE  %d / %d" % [queue.size(), max_q]
	q_header.add_theme_font_size_override("font_size", 10)
	q_header.add_theme_color_override("font_color", ACCENT)
	_main_vbox.add_child(q_header)

	if queue.is_empty():
		var empty := Label.new()
		empty.text = "No active construction"
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", DIM)
		_main_vbox.add_child(empty)
	else:
		for i: int in queue.size():
			_add_queue_item(queue[i], i)

	_main_vbox.add_child(HSeparator.new())

	# ── Building Categories ──
	var avail_header := Label.new()
	avail_header.text = "BUILD NEW"
	avail_header.add_theme_font_size_override("font_size", 10)
	avail_header.add_theme_color_override("font_color", HEADER)
	_main_vbox.add_child(avail_header)

	# Scroll for building list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)

	if bs == null:
		return

	var last_cat: String = ""
	for btype: String in bs.BUILDING_TYPES:
		var bdef: Dictionary = bs.BUILDING_TYPES[btype]
		var cat: String = bdef.get("category", "")

		if cat != last_cat:
			last_cat = cat
			var sep := HSeparator.new()
			list.add_child(sep)
			var cat_lbl := Label.new()
			cat_lbl.text = "  %s" % cat.to_upper()
			cat_lbl.add_theme_font_size_override("font_size", 9)
			cat_lbl.add_theme_color_override("font_color", CAT_COLORS.get(cat, DIM))
			list.add_child(cat_lbl)

		# Building row: icon-style button
		var row := _make_building_row(btype, bdef)
		list.add_child(row)


func _add_queue_item(item: Dictionary, index: int) -> void:
	var bs: Node = _bs()
	var bdef: Dictionary = bs.BUILDING_TYPES.get(item.get("type", ""), {}) if bs != null else {}
	var pname: String = ProvinceDB.province_data.get(item.get("province", ""), {}).get("name", "?")
	var progress: float = clampf(float(item.get("progress", 0.0)), 0.0, 1.0)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	_main_vbox.add_child(container)

	# Top row: name + cancel
	var top := HBoxContainer.new()
	container.add_child(top)

	var name_lbl := Label.new()
	name_lbl.text = "%s — %s" % [bdef.get("label", "?"), pname]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_lbl)

	var pct_lbl := Label.new()
	pct_lbl.text = "%.0f%%" % (progress * 100.0)
	pct_lbl.add_theme_font_size_override("font_size", 10)
	pct_lbl.add_theme_color_override("font_color", GREEN)
	pct_lbl.custom_minimum_size = Vector2(36, 0)
	pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(pct_lbl)

	var cancel_btn := Button.new()
	cancel_btn.text = "X"
	cancel_btn.custom_minimum_size = Vector2(20, 20)
	cancel_btn.add_theme_font_size_override("font_size", 9)
	cancel_btn.tooltip_text = "Cancel (50% refund)"
	var idx: int = index
	cancel_btn.pressed.connect(func() -> void:
		var b: Node = _bs()
		if b != null:
			b.cancel_build(GameState.player_iso, idx)
			_show_main())
	top.add_child(cancel_btn)

	# Progress bar
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(0, 6)
	bar_bg.color = BAR_BG
	container.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.custom_minimum_size = Vector2(progress * 300.0, 6)
	bar_fill.color = BAR_FILL
	bar_fill.position = Vector2.ZERO
	bar_bg.add_child(bar_fill)


func _make_building_row(btype: String, bdef: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 32)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var cost: float = bdef.get("cost", 1.0)
	var cost_str: String = "$%.1fB" % cost if cost >= 1.0 else "$%.0fM" % (cost * 1000)
	var months: int = bdef.get("build_months", 3)
	var cat_col: Color = CAT_COLORS.get(bdef.get("category", ""), DIM)

	btn.text = "  %s    %s    %d months" % [bdef.get("label", btype), cost_str, months]
	btn.add_theme_font_size_override("font_size", 10)

	# Check if player can afford
	var treasury: float = float(GameState.get_country(GameState.player_iso).get("treasury", 0.0))
	if treasury < cost:
		btn.disabled = true
		btn.tooltip_text = "Insufficient treasury (%s needed)" % cost_str

	# Check coastal requirement
	if bdef.get("requires_coastal", false):
		btn.text += "  [coastal]"
	if bdef.get("requires_capital", false):
		btn.text += "  [capital]"

	var bt: String = btype
	btn.pressed.connect(func() -> void: _show_provinces(bt))
	return btn


# ── PROVINCE SELECTION VIEW ───────────────────────────────────────────────────

func _show_provinces(building_type: String) -> void:
	_clear()
	_selected_type = building_type
	var bs: Node = _bs()
	if bs == null:
		return
	var bdef: Dictionary = bs.BUILDING_TYPES.get(building_type, {})
	var player: String = GameState.player_iso

	# Header
	var title_row := HBoxContainer.new()
	_main_vbox.add_child(title_row)

	var back_btn := Button.new()
	back_btn.text = "<"
	back_btn.custom_minimum_size = Vector2(28, 28)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.pressed.connect(func() -> void: _show_main())
	title_row.add_child(back_btn)

	var title := Label.new()
	title.text = "  %s" % bdef.get("label", building_type).to_upper()
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", HEADER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	# Description
	var desc := Label.new()
	desc.text = bdef.get("description", "")
	desc.add_theme_font_size_override("font_size", 9)
	desc.add_theme_color_override("font_color", DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_vbox.add_child(desc)

	# Cost + time info
	var cost: float = bdef.get("cost", 1.0)
	var cost_str: String = "$%.1fB" % cost if cost >= 1.0 else "$%.0fM" % (cost * 1000)
	var info := Label.new()
	info.text = "Cost: %s  |  Build time: %d months" % [cost_str, bdef.get("build_months", 3)]
	info.add_theme_font_size_override("font_size", 10)
	info.add_theme_color_override("font_color", TEXT)
	_main_vbox.add_child(info)

	_main_vbox.add_child(HSeparator.new())

	# Column headers
	var hdr := HBoxContainer.new()
	_main_vbox.add_child(hdr)
	_lbl(hdr, "#", 20, 9, DIM)
	_lbl(hdr, "Province", 0, 9, DIM, true)
	_lbl(hdr, "Terrain", 55, 9, DIM)
	_lbl(hdr, "Score", 40, 9, DIM)

	# Ranked list
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	var ranked: Array = bs.get_ranked_provinces(building_type, player)

	if ranked.is_empty():
		var none := Label.new()
		none.text = "No suitable provinces found."
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", RED)
		list.add_child(none)
		return

	for i: int in mini(ranked.size(), 30):
		var entry: Dictionary = ranked[i]
		var pid: String = entry["pid"]
		var score: float = entry["score"]
		var pdata: Dictionary = ProvinceDB.province_data.get(pid, {})
		var pname: String = pdata.get("name", pid)
		var terrain: String = pdata.get("terrain", "plains")
		var is_coastal: bool = pdata.get("coastal", false)

		var row := Button.new()
		row.custom_minimum_size = Vector2(0, 24)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 10)

		var score_pct: int = int(score * 100)
		var extra: String = " *" if is_coastal else ""
		row.text = "  %d.  %s  [%s]%s  —  %d%%" % [i + 1, pname, terrain, extra, score_pct]

		var p: String = pid
		var bt: String = building_type
		row.pressed.connect(func() -> void: _on_build(bt, p))
		list.add_child(row)


func _on_build(building_type: String, province_id: String) -> void:
	var bs: Node = _bs()
	if bs != null and bs.start_build(building_type, province_id, GameState.player_iso):
		GameState.country_data_changed.emit(GameState.player_iso)
		_show_main()


func _lbl(parent: Node, text: String, min_w: int, fs: int, col: Color, expand: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if min_w > 0:
		l.custom_minimum_size = Vector2(min_w, 0)
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
