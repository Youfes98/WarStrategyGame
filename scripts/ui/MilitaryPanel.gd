## MilitaryPanel.gd
## Bottom-left HUD: unit counts by domain, recruit buttons, split/merge army controls.
extends PanelContainer

var _sections:  Dictionary = {}  # domain → {labels: {type→Label}, btns: {type→Button}}
var _sel_label:  Label      = null
var _army_info:  Label      = null
var _hint:       Label      = null
var _split_btn:  Button     = null
var _merge_btn:  Button     = null

const DOMAIN_HEADERS: Dictionary = {
	"land": "LAND FORCES",
	"sea":  "NAVAL FORCES",
	"air":  "AIR FORCES",
}
const DOMAIN_COLORS: Dictionary = {
	"land": Color(0.7, 0.85, 1.0),
	"sea":  Color(0.4, 0.75, 1.0),
	"air":  Color(0.85, 0.85, 0.5),
}


func _ready() -> void:
	custom_minimum_size = Vector2(290, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var title := Label.new()
	title.text = "MILITARY FORCES"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Build sections by domain — each section has a container we can hide/show
	for domain: String in ["land", "sea", "air"]:
		var sec_container := VBoxContainer.new()
		sec_container.add_theme_constant_override("separation", 2)
		vbox.add_child(sec_container)

		sec_container.add_child(HSeparator.new())
		var hdr := Label.new()
		hdr.text = DOMAIN_HEADERS[domain]
		hdr.add_theme_font_size_override("font_size", 9)
		hdr.add_theme_color_override("font_color", DOMAIN_COLORS[domain])
		sec_container.add_child(hdr)

		var sec: Dictionary = {"labels": {}, "btns": {}, "container": sec_container}
		for type_key: String in MilitarySystem.UNIT_TYPES:
			var tdata: Dictionary = MilitarySystem.UNIT_TYPES[type_key]
			if tdata.get("domain", "land") != domain:
				continue

			var row := HBoxContainer.new()
			sec_container.add_child(row)

			var lbl := Label.new()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(lbl)
			sec["labels"][type_key] = lbl

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(80, 20)
			btn.add_theme_font_size_override("font_size", 9)
			var t: String = type_key
			btn.pressed.connect(func() -> void: _recruit(t))
			row.add_child(btn)
			sec["btns"][type_key] = btn

		_sections[domain] = sec

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

	_army_info = Label.new()
	_army_info.add_theme_font_size_override("font_size", 9)
	_army_info.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	_army_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_info.visible = false
	vbox.add_child(_army_info)

	_hint = Label.new()
	_hint.text = "Left-click your territory to select\nRight-click to move"
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint)

	visible = false
	GameState.player_country_set.connect(func(_iso: String) -> void: _refresh())
	MilitarySystem.units_changed.connect(_refresh)
	MilitarySystem.selection_changed.connect(_on_selection_changed)
	MilitarySystem.territory_selected.connect(_on_territory_selected)


func _recruit(type_key: String) -> void:
	var recruit_loc: String = ""
	if not MilitarySystem.selected_army_ids.is_empty():
		recruit_loc = MilitarySystem._get_army_location(MilitarySystem.selected_army_ids[0])
	elif not MilitarySystem.recruit_iso.is_empty():
		recruit_loc = MilitarySystem.recruit_iso
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

	# Count all player units by type
	var counts: Dictionary = {}
	var in_transit: Dictionary = {}
	for type_key: String in MilitarySystem.UNIT_TYPES:
		counts[type_key] = 0
		in_transit[type_key] = 0
	for id: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[id]
		if u.owner == player and counts.has(u.type):
			counts[u.type] += 1
			if not (u.get("path", []) as Array).is_empty():
				in_transit[u.type] += 1

	# Current recruit location
	var recruit_loc: String = MilitarySystem.recruit_iso
	if recruit_loc.is_empty() and not MilitarySystem.selected_army_ids.is_empty():
		recruit_loc = MilitarySystem._get_army_location(MilitarySystem.selected_army_ids[0])

	# Determine which domains are available at this location
	var capital: String = ProvinceDB.get_capital_province(player)
	var at_capital: bool = recruit_loc == capital
	var at_coast: bool = not recruit_loc.is_empty() and ProvinceDB.is_coastal(recruit_loc)

	# Hide/show domain sections based on what can be built here
	# Land: always show (infantry recruitable at capital)
	(_sections["land"]["container"] as Control).visible = true
	# Sea: only show if at a coastal province
	(_sections["sea"]["container"] as Control).visible = at_coast
	# Air: only show at capital (until airfields exist)
	(_sections["air"]["container"] as Control).visible = at_capital

	# Update all visible sections
	for domain: String in _sections:
		var sec: Dictionary = _sections[domain]
		if not (sec["container"] as Control).visible:
			continue
		for type_key: String in sec["labels"]:
			var tdata: Dictionary = MilitarySystem.UNIT_TYPES[type_key]
			var tname: String = tdata["label"]
			var total: int = counts.get(type_key, 0)
			var moving: int = in_transit.get(type_key, 0)
			var txt: String = "%s  x%d" % [tname, total]
			if moving > 0:
				txt += "  (%d moving)" % moving
			(sec["labels"][type_key] as Label).text = txt

			var cost: float = float(tdata.get("cost", 0))
			var cost_str: String = "$%.1fB" % cost if cost >= 1.0 else "$%.0fM" % (cost * 1000.0)
			var btn: Button = sec["btns"][type_key]
			btn.text = "+ %s" % cost_str
			if not recruit_loc.is_empty():
				btn.disabled = not MilitarySystem.can_recruit_at(type_key, recruit_loc)
			else:
				btn.disabled = not MilitarySystem.can_recruit(type_key)

	var sel_aid: String = MilitarySystem.selected_army_id
	_split_btn.disabled = sel_aid.is_empty() or MilitarySystem.is_army_moving(sel_aid)

	# Army info card
	if not sel_aid.is_empty():
		_army_info.visible = true
		var total_str: float = 0.0
		var total_mor: float = 0.0
		var unit_count: int = 0
		var dest_prov: String = ""
		var days_left: int = 0
		var composition: Dictionary = {}

		for uid: String in MilitarySystem.units:
			var u: Dictionary = MilitarySystem.units[uid]
			if u.get("army_id", "") == sel_aid and u.owner == player:
				total_str += float(u.get("strength", 100))
				total_mor += float(u.get("morale", 80))
				unit_count += 1
				var utype: String = u.get("type", "infantry")
				composition[utype] = int(composition.get(utype, 0)) + 1
				var path: Array = u.get("path", [])
				if not path.is_empty() and dest_prov.is_empty():
					dest_prov = path[path.size() - 1]
					days_left = int(u.get("days_remaining", 0))

		if unit_count > 0:
			var avg_str: float = total_str / unit_count
			var avg_mor: float = total_mor / unit_count
			var supply: int = int(MilitarySystem.units.values()[0].get("supply_distance", 0)) if not MilitarySystem.units.is_empty() else 0
			# Get supply for first unit of this army
			for uid: String in MilitarySystem.units:
				var u: Dictionary = MilitarySystem.units[uid]
				if u.get("army_id", "") == sel_aid:
					supply = int(u.get("supply_distance", 0))
					break

			var comp_parts: PackedStringArray = PackedStringArray()
			for t: String in composition:
				comp_parts.append("%d %s" % [composition[t], MilitarySystem.UNIT_TYPES.get(t, {}).get("label", t)])

			var info_text: String = "Units: %s\nStrength: %.0f%%  |  Morale: %.0f%%\nSupply: %d provinces" % [
				", ".join(comp_parts), avg_str, avg_mor, supply]

			if not dest_prov.is_empty():
				var dest_name: String = ProvinceDB.province_data.get(dest_prov, {}).get("name", dest_prov)
				info_text += "\nDestination: %s (~%d days)" % [dest_name, days_left]

			_army_info.text = info_text

			# Color morale
			if avg_mor < 30:
				_army_info.add_theme_color_override("font_color", Color(0.90, 0.40, 0.35))
			elif avg_mor < 60:
				_army_info.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
			else:
				_army_info.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
		else:
			_army_info.visible = false
	else:
		_army_info.visible = false

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


func _on_selection_changed() -> void:
	# Only show panel when an army is actively selected
	visible = not MilitarySystem.selected_army_ids.is_empty()
	_refresh()


func _on_territory_selected(iso: String) -> void:
	if iso.is_empty() and MilitarySystem.recruit_iso.is_empty():
		_sel_label.visible = false
		_hint.text = "Left-click your territory to select\nRight-click to move"
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
	_hint.text = "Right-click to move | Click same to cycle/deselect"
