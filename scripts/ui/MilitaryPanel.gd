## MilitaryPanel.gd
## Bottom-left HUD panel: player unit counts + recruit buttons.
## All children created programmatically.
extends PanelContainer

var _labels:    Dictionary = {}   # type_key → Label (count)
var _btns:      Dictionary = {}   # type_key → Button (recruit)
var _sel_label: Label      = null # shows currently selected territory + adjacent targets
var _hint:      Label      = null


func _ready() -> void:
	custom_minimum_size = Vector2(290, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "MILITARY FORCES"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(header)

	vbox.add_child(HSeparator.new())

	# Unit rows
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

	# Selection status
	_sel_label = Label.new()
	_sel_label.add_theme_font_size_override("font_size", 10)
	_sel_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sel_label.visible = false
	vbox.add_child(_sel_label)

	# Hint
	_hint = Label.new()
	_hint.text = "Click your territory to select an army\nClick same territory again to cycle armies"
	_hint.add_theme_font_size_override("font_size", 9)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint)

	GameState.player_country_set.connect(func(_iso: String) -> void: visible = true; _refresh())
	MilitarySystem.units_changed.connect(_refresh)
	MilitarySystem.territory_selected.connect(_on_territory_selected)


func _recruit(type_key: String) -> void:
	MilitarySystem.recruit_unit(type_key)
	# No notification per-recruit — the count label updates immediately.


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
			if not u.destination.is_empty():
				in_transit[u.type] += 1

	const COSTS: Dictionary = {"infantry": "$5B", "armor": "$15B", "artillery": "$10B"}
	for type_key: String in _labels:
		var tname: String = MilitarySystem.UNIT_TYPES[type_key]["label"]
		var total: int    = counts[type_key]
		var moving: int   = in_transit[type_key]
		var txt: String   = "%s  ×%d" % [tname, total]
		if moving > 0:
			txt += "  (%d moving)" % moving
		_labels[type_key].text = txt
		_btns[type_key].text   = "+ %s" % COSTS[type_key]
		_btns[type_key].disabled = not MilitarySystem.can_recruit(type_key)


func _on_territory_selected(iso: String) -> void:
	if iso.is_empty():
		_sel_label.visible = false
		_hint.text = "Click your territory to select an army\nClick same territory again to cycle armies"
		return

	# Build display name: "Province, Country" when province data is loaded
	var sel_name: String
	var pdata: Dictionary = ProvinceDB.province_data.get(iso, {})
	if not pdata.is_empty():
		var pname: String   = pdata.get("name", iso)
		var parent_iso: String = pdata.get("parent_iso", "")
		var cname: String   = GameState.get_country(parent_iso).get("name", parent_iso)
		sel_name = "%s, %s" % [pname, cname] if not cname.is_empty() else pname
	else:
		sel_name = GameState.get_country(iso).get("name", iso)

	var neighbors: Array = ProvinceDB.get_neighbors(iso)
	var targets: Array[String] = []
	for nb: String in neighbors:
		var nb_pdata: Dictionary = ProvinceDB.province_data.get(nb, {})
		if not nb_pdata.is_empty():
			targets.append(nb_pdata.get("name", nb))
		else:
			targets.append(GameState.get_country(nb).get("name", nb))

	_sel_label.visible = true
	if targets.is_empty():
		_sel_label.text = "Selected: %s\nNo adjacent territories" % sel_name
	else:
		# Show at most 4 neighbor names to keep it compact
		var shown: Array = targets.slice(0, 4)
		var suffix: String = ("..." if targets.size() > 4 else "")
		_sel_label.text = "Selected: %s\n→ %s%s" % [sel_name, ", ".join(shown), suffix]

	_hint.text = "Click highlighted neighbor to move\nClick same territory to cycle/deselect"
