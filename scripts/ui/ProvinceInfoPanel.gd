## ProvinceInfoPanel.gd
## Rectangle info card shown when clicking a province.
## Shows: province name, country, population estimate, GDP contribution,
## terrain, buildings, and build options.
extends PanelContainer

var _province_id: String = ""
var _vbox: VBoxContainer = null
var _name_lbl: Label = null
var _country_lbl: Label = null
var _terrain_lbl: Label = null
var _pop_lbl: Label = null
var _gdp_lbl: Label = null
var _buildings_list: VBoxContainer = null

const BG_COLOR:     Color = Color(0.07, 0.07, 0.09, 0.94)
const HEADER_COLOR: Color = Color(0.85, 0.75, 0.45)
const TEXT_COLOR:   Color = Color(0.85, 0.86, 0.90)
const DIM_COLOR:    Color = Color(0.50, 0.52, 0.55)
const TERRAIN_COLORS: Dictionary = {
	"plains": Color(0.45, 0.75, 0.40),
	"forest": Color(0.30, 0.65, 0.30),
	"mountain": Color(0.65, 0.55, 0.45),
	"desert": Color(0.85, 0.75, 0.45),
	"jungle": Color(0.25, 0.55, 0.25),
	"tundra": Color(0.60, 0.70, 0.80),
}


func _ready() -> void:
	custom_minimum_size = Vector2(250, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("province_info_panel")
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 3)
	add_child(_vbox)

	# Province name
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 13)
	_name_lbl.add_theme_color_override("font_color", HEADER_COLOR)
	_vbox.add_child(_name_lbl)

	# Country + owner
	_country_lbl = Label.new()
	_country_lbl.add_theme_font_size_override("font_size", 10)
	_country_lbl.add_theme_color_override("font_color", DIM_COLOR)
	_vbox.add_child(_country_lbl)

	_vbox.add_child(HSeparator.new())

	# Terrain
	_terrain_lbl = Label.new()
	_terrain_lbl.add_theme_font_size_override("font_size", 10)
	_vbox.add_child(_terrain_lbl)

	# Population estimate
	_pop_lbl = Label.new()
	_pop_lbl.add_theme_font_size_override("font_size", 10)
	_pop_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	_vbox.add_child(_pop_lbl)

	# GDP contribution
	_gdp_lbl = Label.new()
	_gdp_lbl.add_theme_font_size_override("font_size", 10)
	_gdp_lbl.add_theme_color_override("font_color", TEXT_COLOR)
	_vbox.add_child(_gdp_lbl)

	_vbox.add_child(HSeparator.new())

	# Buildings section
	var bld_hdr := Label.new()
	bld_hdr.text = "BUILDINGS"
	bld_hdr.add_theme_font_size_override("font_size", 9)
	bld_hdr.add_theme_color_override("font_color", DIM_COLOR)
	_vbox.add_child(bld_hdr)

	_buildings_list = VBoxContainer.new()
	_buildings_list.add_theme_constant_override("separation", 1)
	_vbox.add_child(_buildings_list)

	# Listen for province clicks
	GameState.country_selected.connect(_on_country_selected)
	GameState.country_deselected.connect(func() -> void: visible = false)


func _on_country_selected(_iso: String) -> void:
	# We need the actual province ID, not just the country
	# This gets called via MapRenderer — check if we have a province click
	pass


## Called externally by MapRenderer when a province is clicked.
func show_province(province_id: String) -> void:
	# Don't show during country picking (before player has chosen)
	if GameState.player_iso.is_empty():
		return
	_province_id = province_id
	visible = true
	_refresh()


func _refresh() -> void:
	if _province_id.is_empty():
		visible = false
		return

	var pdata: Dictionary = ProvinceDB.province_data.get(_province_id, {})
	if pdata.is_empty():
		visible = false
		return

	var parent_iso: String = pdata.get("parent_iso", "")
	var ter_owner: String = GameState.territory_owner.get(_province_id, parent_iso)
	var owner_data: Dictionary = GameState.get_country(ter_owner)
	var parent_data: Dictionary = GameState.get_country(parent_iso)

	# Name
	_name_lbl.text = pdata.get("name", _province_id)

	# Country info
	var country_name: String = parent_data.get("name", parent_iso)
	if ter_owner != parent_iso and not ter_owner.is_empty():
		var owner_name: String = owner_data.get("name", ter_owner)
		_country_lbl.text = "%s (occupied by %s)" % [country_name, owner_name]
	else:
		_country_lbl.text = country_name

	# Terrain
	var terrain: String = pdata.get("terrain", "plains")
	_terrain_lbl.text = "Terrain: %s" % terrain.capitalize()
	_terrain_lbl.add_theme_color_override("font_color",
		TERRAIN_COLORS.get(terrain, TEXT_COLOR))

	# Population (baked from pipeline, or fallback to even split)
	var est_pop: int = int(pdata.get("est_population", 0))
	if est_pop == 0:
		var country_pop: int = int(owner_data.get("population", 100000))
		var prov_count: int = maxi(ProvinceDB.get_country_province_ids(ter_owner).size(), 1)
		est_pop = country_pop / prov_count
	_pop_lbl.text = "Population: ~%s" % _fmt_pop(est_pop)

	# GDP (baked from pipeline with terrain/coastal/capital modifiers)
	var prov_gdp: float = float(pdata.get("gdp_billions", 0.0))
	var country_gdp: float = float(owner_data.get("gdp_raw_billions", 1.0))
	if prov_gdp < 0.001:
		var prov_count: int = maxi(ProvinceDB.get_country_province_ids(ter_owner).size(), 1)
		prov_gdp = country_gdp / float(prov_count)
	# Buildings boost province GDP
	var bs: Node = get_node_or_null("/root/BuildingSystem")
	var prov_buildings: Array = bs.get_buildings_at(_province_id) if bs != null else []
	var gdp_mult: float = 1.0
	for b: Dictionary in prov_buildings:
		var btype: String = b.get("type", "")
		if btype == "civilian_factory": gdp_mult += 0.3
		elif btype == "port": gdp_mult += 0.15
		elif btype == "power_plant": gdp_mult += 0.2
	prov_gdp *= gdp_mult
	var contribution_pct: float = prov_gdp / maxf(country_gdp, 0.01) * 100.0

	_gdp_lbl.text = "GDP: ~%s (%.1f%% of national)" % [_fmt_money(prov_gdp), contribution_pct]
	_gdp_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5) if gdp_mult > 1.0 else TEXT_COLOR)

	# Buildings
	for child: Node in _buildings_list.get_children():
		child.queue_free()

	var buildings: Array = prov_buildings  # already fetched above

	if buildings.is_empty():
		var none := Label.new()
		none.text = "No buildings"
		none.add_theme_font_size_override("font_size", 9)
		none.add_theme_color_override("font_color", Color(0.50, 0.45, 0.45))
		_buildings_list.add_child(none)
	else:
		for b: Dictionary in buildings:
			var btype: String = b.get("type", "")
			var bdef: Dictionary = {}
			if bs != null:
				bdef = bs.BUILDING_TYPES.get(btype, {})
			var lbl := Label.new()
			lbl.text = "• %s" % bdef.get("label", btype.capitalize())
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", TEXT_COLOR)
			_buildings_list.add_child(lbl)

	# Actions (only if player owns this province)
	if ter_owner == GameState.player_iso:
		# Recruitment buttons for units this province can produce
		var can_recruit_any: bool = false
		if bs != null:
			for unit_type: String in MilitarySystem.UNIT_TYPES:
				if MilitarySystem.can_recruit_at(unit_type, _province_id):
					can_recruit_any = true
					var udata: Dictionary = MilitarySystem.UNIT_TYPES[unit_type]
					var cost: float = float(udata.get("cost", 0))
					var cost_str: String = "$%.1fB" % cost if cost >= 1.0 else "$%.0fM" % (cost * 1000)
					var recruit_btn := Button.new()
					recruit_btn.text = "Recruit %s  %s" % [udata["label"], cost_str]
					recruit_btn.add_theme_font_size_override("font_size", 9)
					var treasury: float = float(GameState.get_country(GameState.player_iso).get("treasury", 0))
					recruit_btn.disabled = treasury < cost
					var ut: String = unit_type
					var pid: String = _province_id
					recruit_btn.pressed.connect(func() -> void:
						MilitarySystem.recruit_unit(ut, pid)
						_refresh())
					_buildings_list.add_child(recruit_btn)

		if not can_recruit_any:
			var no_recruit := Label.new()
			no_recruit.text = "No recruitment buildings"
			no_recruit.add_theme_font_size_override("font_size", 9)
			no_recruit.add_theme_color_override("font_color", DIM_COLOR)
			_buildings_list.add_child(no_recruit)

		_buildings_list.add_child(HSeparator.new())

		var build_btn := Button.new()
		build_btn.text = "Build Here (V)"
		build_btn.add_theme_font_size_override("font_size", 10)
		build_btn.pressed.connect(func() -> void:
			var bp: Control = get_parent().get_node_or_null("BuildPanel")
			if bp != null:
				bp.visible = true
				if bp.has_method("_show_type_list"):
					bp._show_type_list()
		)
		_buildings_list.add_child(build_btn)

	# Coastal indicator
	if pdata.get("coastal", false):
		var coast := Label.new()
		coast.text = "Coastal province"
		coast.add_theme_font_size_override("font_size", 9)
		coast.add_theme_color_override("font_color", Color(0.40, 0.70, 1.0))
		_buildings_list.add_child(coast)


func _fmt_pop(p: int) -> String:
	if p >= 1_000_000_000: return "%.2fB" % (float(p) / 1_000_000_000.0)
	if p >= 1_000_000:     return "%.1fM" % (float(p) / 1_000_000.0)
	if p >= 1_000:         return "%.0fK" % (float(p) / 1_000.0)
	return str(p)


func _fmt_money(b: float) -> String:
	if absf(b) >= 1000.0: return "$%.1fT" % (b / 1000.0)
	if absf(b) >= 1.0:    return "$%.1fB" % b
	if absf(b) >= 0.01:   return "$%.0fM" % (b * 1000.0)
	return "$0"
