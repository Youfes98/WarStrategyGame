## MilitaryPanel.gd
## Bottom-left HUD: unit counts, recruit buttons, split/merge army controls.
extends PanelContainer

var _labels:    Dictionary = {}
var _btns:      Dictionary = {}
var _sel_label: Label      = null
var _hint:      Label      = null
var _split_btn: Button     = null
var _merge_btn: Button     = null


func _ready() -> void:
	custom_minimum_size = Vector2(290, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	add_child(vbox)

	var header := Label.new()
	header.text = "MILITARY FORCES"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	for type_key: String in ["infantry", "armor", "artillery"]:
		var row := HBoxContainer.new()
		vbox.add_child(row)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(lbl)
		_labels[type_key] = lbl

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 22)
		btn.add_theme_font_size_override("font_size", 10)
		var t: String = type_key
		btn.pressed.connect(func() -> void: _recruit(t))
		row.add_child(btn)
		_btns[type_key] = btn

	vbox.add_child(HSeparator.new())

	# Army controls
	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 6)
	vbox.add_child(ctrl_row)

	_split_btn = Button.new()
	_split_btn.text = "Split Army"
	_split_btn.add_theme_font_size_override("font_size", 10)
	_split_btn.custom_minimum_size = Vector2(0, 24)
	_split_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_btn.pressed.connect(_on_split)
	_split_btn.disabled = true
	ctrl_row.add_child(_split_btn)

	_merge_btn = Button.new()
	_merge_btn.text = "Merge"
	_merge_btn.add_theme_font_size_override("font_size", 10)
	_merge_btn.custom_minimum_size = Vector2(0, 24)
	_merge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merge_btn.pressed.connect(_on_merge)
	_merge_btn.disabled = true
	ctrl_row.add_child(_merge_btn)

	vbox.add_child(HSeparator.new())

	_sel_label = Label.new()
	_sel_label.add_theme_font_size_override("font_size", 10)
	_sel_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_label.visible = false
	vbox.add_child(_sel_label)

	_hint = Label.new()
	_hint.text = "Left-click your territory to select army\nRight-click any territory to move"
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint)

	GameState.player_country_set.connect(func(_iso: String) -> void: visible = true; _refresh())
	MilitarySystem.units_changed.connect(_refresh)
	MilitarySystem.territory_selected.connect(_on_territory_selected)


func _recruit(type_key: String) -> void:
	var recruit_loc: String = ""
	var sel: String = MilitarySystem.selected_iso
	if not sel.is_empty():
		var parent: String = ProvinceDB.get_parent_iso(sel)
		var ter_owner: String = GameState.territory_owner.get(sel, parent)
		if ter_owner == GameState.player_iso:
			recruit_loc = sel
	MilitarySystem.recruit_unit(type_key, recruit_loc)


func _on_split() -> void:
	var aid: String = MilitarySystem.selected_army_id
	if aid.is_empty():
		return
	MilitarySystem.split_army(aid)


func _on_merge() -> void:
	var iso: String = MilitarySystem.selected_iso
	var player: String = GameState.player_iso
	if iso.is_empty() or player.is_empty():
		return
	var armies: Array = []
	var seen: Dictionary = {}
	for id: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[id]
		if u.owner == player and u.location == iso:
			var aid: String = u.get("army_id", "")
			if not aid.is_empty() and not seen.has(aid):
				seen[aid] = true
				armies.append(aid)
	if armies.size() < 2:
		UIManager.push_notification("Need multiple armies here to merge.", "info")
		return
	for i: int in range(1, armies.size()):
		MilitarySystem.merge_armies(armies[0], armies[i])


func _refresh() -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return

	var counts: Dictionary = {"infantry": 0, "armor": 0, "artillery": 0}
	var in_transit: Dictionary = {"infantry": 0, "armor": 0, "artillery": 0}
	for id: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[id]
		if u.owner == player and counts.has(u.type):
			counts[u.type] += 1
			if not (u.get("path", []) as Array).is_empty():
				in_transit[u.type] += 1

	const COSTS: Dictionary = {"infantry": "$5B", "armor": "$15B", "artillery": "$10B"}
	for type_key: String in _labels:
		var tname: String = MilitarySystem.UNIT_TYPES[type_key]["label"]
		var total: int    = counts[type_key]
		var moving: int   = in_transit[type_key]
		var txt: String   = "%s  x%d" % [tname, total]
		if moving > 0:
			txt += "  (%d moving)" % moving
		_labels[type_key].text = txt
		_btns[type_key].text   = "+ %s" % COSTS[type_key]
		_btns[type_key].disabled = not MilitarySystem.can_recruit(type_key)

	var sel_aid: String = MilitarySystem.selected_army_id
	_split_btn.disabled = sel_aid.is_empty() or MilitarySystem.is_army_moving(sel_aid)

	var sel_iso: String = MilitarySystem.selected_iso
	var armies_here: int = 0
	if not sel_iso.is_empty():
		var seen: Dictionary = {}
		for id: String in MilitarySystem.units:
			var u: Dictionary = MilitarySystem.units[id]
			if u.owner == player and u.location == sel_iso:
				var aid: String = u.get("army_id", "")
				if not seen.has(aid):
					seen[aid] = true
					armies_here += 1
	_merge_btn.disabled = armies_here < 2


func _on_territory_selected(iso: String) -> void:
	if iso.is_empty():
		_sel_label.visible = false
		_hint.text = "Left-click your territory to select army\nRight-click any territory to move"
		return

	var sel_name: String
	var pdata: Dictionary = ProvinceDB.province_data.get(iso, {})
	if not pdata.is_empty():
		var pname: String = pdata.get("name", iso)
		var parent_iso: String = pdata.get("parent_iso", "")
		var cname: String = GameState.get_country(parent_iso).get("name", parent_iso)
		sel_name = "%s, %s" % [pname, cname] if not cname.is_empty() else pname
	else:
		sel_name = GameState.get_country(iso).get("name", iso)

	_sel_label.visible = true
	_sel_label.text = "Selected: %s" % sel_name
	_hint.text = "Right-click any territory to move\nClick same territory to cycle/deselect"
