## BuildPanel.gd
## Victoria 3-style building panel: pick type → see ranked provinces → build.
## Press V to toggle. Shows construction queue with progress.
extends PanelContainer

var _type_list: VBoxContainer = null
var _province_list: VBoxContainer = null
var _queue_list: VBoxContainer = null
var _detail_panel: VBoxContainer = null
var _selected_type: String = ""
var _back_btn: Button = null

const BG_COLOR:     Color = Color(0.06, 0.06, 0.08, 0.94)
const HEADER_COLOR: Color = Color(0.85, 0.75, 0.45)
const TEXT_COLOR:   Color = Color(0.82, 0.83, 0.86)
const DIM_COLOR:    Color = Color(0.50, 0.52, 0.55)
const CAT_COLORS: Dictionary = {
	"military": Color(0.85, 0.40, 0.35),
	"economic": Color(0.40, 0.80, 0.45),
	"social":   Color(0.45, 0.70, 1.0),
	"research": Color(0.85, 0.70, 0.30),
	"special":  Color(0.75, 0.55, 0.85),
}


func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	_detail_panel = VBoxContainer.new()
	_detail_panel.add_theme_constant_override("separation", 4)
	add_child(_detail_panel)

	_show_type_list()

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
				_show_type_list()
			get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _selected_type.is_empty():
		_show_type_list()
	else:
		_show_province_list(_selected_type)


func _clear() -> void:
	for child: Node in _detail_panel.get_children():
		child.queue_free()


func _show_type_list() -> void:
	_clear()
	_selected_type = ""

	var title := Label.new()
	title.text = "CONSTRUCTION"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_panel.add_child(title)

	# Show construction queue first
	var queue: Array = get_node("/root/BuildingSystem").get_queue(GameState.player_iso)
	if not queue.is_empty():
		var q_hdr := Label.new()
		q_hdr.text = "IN PROGRESS (%d)" % queue.size()
		q_hdr.add_theme_font_size_override("font_size", 9)
		q_hdr.add_theme_color_override("font_color", DIM_COLOR)
		_detail_panel.add_child(q_hdr)

		for i: int in queue.size():
			var item: Dictionary = queue[i]
			var bdef: Dictionary = get_node("/root/BuildingSystem").BUILDING_TYPES.get(item.get("type", ""), {})
			var pname: String = ProvinceDB.province_data.get(item.get("province", ""), {}).get("name", "?")
			var progress: float = float(item.get("progress", 0.0))

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			_detail_panel.add_child(row)

			var lbl := Label.new()
			lbl.text = "%s — %s" % [bdef.get("label", "?"), pname]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", TEXT_COLOR)
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(lbl)

			var pct := Label.new()
			pct.text = "%.0f%%" % (progress * 100.0)
			pct.add_theme_font_size_override("font_size", 10)
			pct.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
			row.add_child(pct)

		_detail_panel.add_child(HSeparator.new())

	# Building type buttons grouped by category
	var last_cat: String = ""
	for btype: String in get_node("/root/BuildingSystem").BUILDING_TYPES:
		var bdef: Dictionary = get_node("/root/BuildingSystem").BUILDING_TYPES[btype]
		var cat: String = bdef.get("category", "")

		if cat != last_cat:
			last_cat = cat
			var cat_lbl := Label.new()
			cat_lbl.text = cat.to_upper()
			cat_lbl.add_theme_font_size_override("font_size", 9)
			cat_lbl.add_theme_color_override("font_color", CAT_COLORS.get(cat, DIM_COLOR))
			_detail_panel.add_child(cat_lbl)

		var btn := Button.new()
		var cost_str: String = "$%.1fB" % bdef["cost"] if bdef["cost"] >= 1.0 else "$%.0fM" % (bdef["cost"] * 1000)
		btn.text = "%s  —  %s  (%d mo)" % [bdef["label"], cost_str, bdef["build_months"]]
		btn.add_theme_font_size_override("font_size", 10)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var bt: String = btype
		btn.pressed.connect(func() -> void: _show_province_list(bt))
		_detail_panel.add_child(btn)

	_detail_panel.add_child(HSeparator.new())
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func() -> void: visible = false)
	_detail_panel.add_child(close_btn)


func _show_province_list(building_type: String) -> void:
	_clear()
	_selected_type = building_type
	var bdef: Dictionary = get_node("/root/BuildingSystem").BUILDING_TYPES.get(building_type, {})
	var player: String = GameState.player_iso

	# Header
	var title := Label.new()
	title.text = "BUILD: %s" % bdef.get("label", building_type).to_upper()
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_panel.add_child(title)

	var desc := Label.new()
	desc.text = bdef.get("description", "")
	desc.add_theme_font_size_override("font_size", 9)
	desc.add_theme_color_override("font_color", DIM_COLOR)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_panel.add_child(desc)

	_detail_panel.add_child(HSeparator.new())

	# Back button
	_back_btn = Button.new()
	_back_btn.text = "< Back"
	_back_btn.add_theme_font_size_override("font_size", 10)
	_back_btn.pressed.connect(func() -> void: _show_type_list())
	_detail_panel.add_child(_back_btn)

	# Ranked province list
	var ranked: Array = get_node("/root/BuildingSystem").get_ranked_provinces(building_type, player)

	if ranked.is_empty():
		var none := Label.new()
		none.text = "No suitable provinces available."
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", Color(0.85, 0.40, 0.35))
		_detail_panel.add_child(none)
	else:
		var hdr_row := HBoxContainer.new()
		_detail_panel.add_child(hdr_row)
		_add_lbl(hdr_row, "Province", 140, 9, DIM_COLOR, true)
		_add_lbl(hdr_row, "Terrain", 60, 9, DIM_COLOR)
		_add_lbl(hdr_row, "Score", 40, 9, DIM_COLOR)

		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 320)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_detail_panel.add_child(scroll)

		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 1)
		scroll.add_child(list)

		for i: int in mini(ranked.size(), 25):
			var entry: Dictionary = ranked[i]
			var pid: String = entry["pid"]
			var score: float = entry["score"]
			var pdata: Dictionary = ProvinceDB.province_data.get(pid, {})
			var pname: String = pdata.get("name", pid)
			var terrain: String = pdata.get("terrain", "plains")

			var row := Button.new()
			row.text = "%d. %s  [%s]  %.0f%%" % [i + 1, pname, terrain, score * 100]
			row.add_theme_font_size_override("font_size", 10)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var p: String = pid
			var bt: String = building_type
			row.pressed.connect(func() -> void: _on_build(bt, p))
			list.add_child(row)


func _on_build(building_type: String, province_id: String) -> void:
	var player: String = GameState.player_iso
	if get_node("/root/BuildingSystem").start_build(building_type, province_id, player):
		GameState.country_data_changed.emit(player)
		_show_type_list()  # Go back to main view


func _add_lbl(parent: Node, text: String, min_w: int, fs: int, col: Color, expand: bool = false) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", col)
	if min_w > 0:
		lbl.custom_minimum_size = Vector2(min_w, 0)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(lbl)
