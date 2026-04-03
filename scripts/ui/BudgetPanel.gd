## BudgetPanel.gd
## Budget management panel — tax rate slider + 4 spending category sliders.
## Shows monthly breakdown: Revenue, Debt Service, Upkeep, Discretionary, Surplus/Deficit.
extends PanelContainer

var _tax_slider:    HSlider = null
var _tax_lbl:       Label   = null
var _mil_slider:    HSlider = null
var _infra_slider:  HSlider = null
var _social_slider: HSlider = null
var _res_slider:    HSlider = null
var _mil_pct:       Label   = null
var _infra_pct:     Label   = null
var _social_pct:    Label   = null
var _res_pct:       Label   = null
var _breakdown_lbl: Label   = null
var _updating:      bool    = false

const BG_COLOR:     Color = Color(0.08, 0.08, 0.10, 0.92)
const HEADER_COLOR: Color = Color(0.85, 0.75, 0.45)
const LABEL_COLOR:  Color = Color(0.75, 0.75, 0.75)
const VALUE_COLOR:  Color = Color(0.9, 0.9, 0.9)


func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "NATIONAL BUDGET"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Tax rate slider
	var tax_row := _make_slider_row(vbox, "Tax Rate")
	_tax_slider = tax_row[0]
	_tax_lbl = tax_row[1]
	_tax_slider.min_value = 5
	_tax_slider.max_value = 50
	_tax_slider.step = 1
	_tax_slider.value = 25
	_tax_slider.value_changed.connect(_on_tax_changed)

	vbox.add_child(HSeparator.new())

	# Budget allocation header
	var alloc_hdr := Label.new()
	alloc_hdr.text = "BUDGET ALLOCATION"
	alloc_hdr.add_theme_font_size_override("font_size", 11)
	alloc_hdr.add_theme_color_override("font_color", HEADER_COLOR)
	vbox.add_child(alloc_hdr)

	# 4 budget sliders — controls ministerial auto-build priority
	var mil_row := _make_slider_row(vbox, "Military")
	_mil_slider = mil_row[0]; _mil_pct = mil_row[1]
	_mil_slider.value_changed.connect(_on_budget_changed)

	var infra_row := _make_slider_row(vbox, "Infrastructure")
	_infra_slider = infra_row[0]; _infra_pct = infra_row[1]
	_infra_slider.value_changed.connect(_on_budget_changed)

	var social_row := _make_slider_row(vbox, "Social")
	_social_slider = social_row[0]; _social_pct = social_row[1]
	_social_slider.value_changed.connect(_on_budget_changed)

	var res_row := _make_slider_row(vbox, "Research")
	_res_slider = res_row[0]; _res_pct = res_row[1]
	_res_slider.value_changed.connect(_on_budget_changed)

	vbox.add_child(HSeparator.new())

	# Monthly breakdown
	_breakdown_lbl = Label.new()
	_breakdown_lbl.add_theme_font_size_override("font_size", 11)
	_breakdown_lbl.add_theme_color_override("font_color", VALUE_COLOR)
	vbox.add_child(_breakdown_lbl)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void: visible = false)
	vbox.add_child(close_btn)

	GameState.player_country_set.connect(func(_iso: String) -> void: _load_from_data())
	GameState.country_data_changed.connect(func(iso: String) -> void:
		if iso == GameState.player_iso and not _updating:
			_refresh_breakdown())


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B and GameState.player_iso != "":
			visible = not visible
			if visible:
				_load_from_data()
			get_viewport().set_input_as_handled()


func _make_slider_row(parent: VBoxContainer, label_text: String) -> Array:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(90, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = 25
	slider.custom_minimum_size = Vector2(100, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "25%"
	val_lbl.custom_minimum_size = Vector2(40, 0)
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", VALUE_COLOR)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	return [slider, val_lbl]


func _load_from_data() -> void:
	var data: Dictionary = GameState.get_country(GameState.player_iso)
	if data.is_empty():
		return

	_updating = true
	var tax_pct: float = float(data.get("tax_rate", 0.25)) * 100.0
	_tax_slider.min_value = float(data.get("tax_min", 0.10)) * 100.0
	_tax_slider.max_value = float(data.get("tax_max", 0.45)) * 100.0
	_tax_slider.value = tax_pct
	_tax_lbl.text = "%.0f%%" % tax_pct

	_mil_slider.value = float(data.get("budget_military", 20))
	_infra_slider.value = float(data.get("budget_infrastructure", 25))
	_social_slider.value = float(data.get("budget_social", 30))
	_res_slider.value = float(data.get("budget_research", 25))
	_update_pct_labels()
	_updating = false
	_refresh_breakdown()


func _on_tax_changed(value: float) -> void:
	_tax_lbl.text = "%.0f%%" % value
	if _updating:
		return
	var data: Dictionary = GameState.get_country(GameState.player_iso)
	var mn: float = float(data.get("tax_min", 0.10))
	var mx: float = float(data.get("tax_max", 0.45))
	data["tax_rate"] = clampf(value / 100.0, mn, mx)
	GameState.country_data_changed.emit(GameState.player_iso)
	_refresh_breakdown()


func _on_budget_changed(_value: float) -> void:
	_update_pct_labels()
	if _updating:
		return
	var bdata: Dictionary = GameState.get_country(GameState.player_iso)
	var total: float = _mil_slider.value + _infra_slider.value \
					   + _social_slider.value + _res_slider.value
	if total > 0.01:
		bdata["budget_military"] = _mil_slider.value / total * 100.0
		bdata["budget_infrastructure"] = _infra_slider.value / total * 100.0
		bdata["budget_social"] = _social_slider.value / total * 100.0
		bdata["budget_research"] = _res_slider.value / total * 100.0
	GameState.country_data_changed.emit(GameState.player_iso)
	_refresh_breakdown()


func _update_pct_labels() -> void:
	var total: float = _mil_slider.value + _infra_slider.value \
					   + _social_slider.value + _res_slider.value
	if total < 0.01:
		total = 1.0
	_mil_pct.text = "%.0f%%" % (_mil_slider.value / total * 100.0)
	_infra_pct.text = "%.0f%%" % (_infra_slider.value / total * 100.0)
	_social_pct.text = "%.0f%%" % (_social_slider.value / total * 100.0)
	_res_pct.text = "%.0f%%" % (_res_slider.value / total * 100.0)


func _refresh_breakdown() -> void:
	var iso: String = GameState.player_iso
	if iso.is_empty():
		return
	var data: Dictionary = GameState.get_country(iso)
	var gdp: float = float(data.get("gdp_raw_billions", 1.0))
	var tax: float = float(data.get("tax_rate", 0.25))
	var revenue: float = gdp * tax / 12.0
	var debt_svc: float = float(data.get("_monthly_debt_service", 0.0))
	if debt_svc < 0.001:
		var dr: float = float(data.get("debt_to_gdp", 60))
		var cr: float = float(data.get("credit_rating", 50))
		var ir: float = lerpf(0.15, 0.01, cr / 100.0)
		debt_svc = gdp * (dr / 100.0) * (ir / 12.0)
	var upkeep: float = MilitarySystem.get_total_upkeep(iso)
	var balance: float = revenue - debt_svc - upkeep

	var stability: float = float(data.get("stability", 50))
	var debt_ratio: float = float(data.get("debt_to_gdp", 60))
	var infra: float = float(data.get("infrastructure", 50))

	var bal_sign: String = "+" if balance >= 0 else ""
	_breakdown_lbl.text = (
		"GDP: %s    Stability: %.0f    Debt/GDP: %.0f%%\n" % [_fmt(gdp), stability, debt_ratio] +
		"Infrastructure: %.0f    Credit: %.0f\n" % [infra, float(data.get("credit_rating", 50))] +
		"\n" +
		"Revenue:      +%s/mo\n" % _fmt(revenue) +
		"Debt service: -%s/mo\n" % _fmt(debt_svc) +
		"Unit upkeep:  -%s/mo\n" % _fmt(upkeep) +
		"Balance:      %s%s/mo" % [bal_sign, _fmt(balance)]
	)

	if balance < 0:
		_breakdown_lbl.add_theme_color_override("font_color", Color(0.95, 0.6, 0.5))
	else:
		_breakdown_lbl.add_theme_color_override("font_color", VALUE_COLOR)


func _fmt(b: float) -> String:
	if absf(b) >= 1000.0: return "$%.1fT" % (b / 1000.0)
	if absf(b) >= 1.0:    return "$%.1fB" % b
	if absf(b) >= 0.01:   return "$%.0fM" % (b * 1000.0)
	return "$0"
