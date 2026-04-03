## ResourceBar.gd
## Top-left HUD: flag + country name/tier + treasury (with balance indicator).
## Click → opens BudgetPanel.
extends PanelContainer

var _flag_tex:     TextureRect = null
var _badge:        Control = null
var _badge_color:  Color = Color(0.3, 0.5, 0.8)
var _badge_iso:    String = ""
var _name_lbl:     Label = null
var _tier_lbl:     Label = null
var _treasury_lbl: Label = null
var _balance_lbl:  Label = null

const BG_COLOR: Color = Color(0.06, 0.06, 0.08, 0.92)
const TIER_COLORS: Dictionary = {
	"S": Color(0.95, 0.80, 0.25), "A": Color(0.55, 0.75, 1.0),
	"B": Color(0.45, 0.80, 0.45), "C": Color(0.65, 0.65, 0.65),
	"D": Color(0.75, 0.35, 0.30),
}
const TIER_NAMES: Dictionary = {
	"S": "Superpower", "A": "Great Power", "B": "Regional Power",
	"C": "Minor Nation", "D": "Weak State",
}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click to open Budget Panel"

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# ── Flag image ──
	_flag_tex = TextureRect.new()
	_flag_tex.custom_minimum_size = Vector2(38, 38)
	_flag_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_flag_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_flag_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_flag_tex)

	# Fallback badge
	_badge = Control.new()
	_badge.custom_minimum_size = Vector2(38, 38)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.draw.connect(_draw_badge)
	_badge.visible = false
	hbox.add_child(_badge)

	# ── Name + Tier ──
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", -2)
	hbox.add_child(name_col)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 14)
	_name_lbl.add_theme_color_override("font_color", Color(0.92, 0.93, 0.96))
	name_col.add_child(_name_lbl)

	_tier_lbl = Label.new()
	_tier_lbl.add_theme_font_size_override("font_size", 10)
	name_col.add_child(_tier_lbl)

	hbox.add_child(VSeparator.new())

	# ── Treasury + balance underneath ──
	var t_col := VBoxContainer.new()
	t_col.add_theme_constant_override("separation", -2)
	hbox.add_child(t_col)

	var t_hdr := Label.new()
	t_hdr.text = "TREASURY"
	t_hdr.add_theme_font_size_override("font_size", 8)
	t_hdr.add_theme_color_override("font_color", Color(0.45, 0.50, 0.55))
	t_col.add_child(t_hdr)

	_treasury_lbl = Label.new()
	_treasury_lbl.add_theme_font_size_override("font_size", 14)
	_treasury_lbl.add_theme_color_override("font_color", Color(0.80, 1.0, 0.80))
	t_col.add_child(_treasury_lbl)

	_balance_lbl = Label.new()
	_balance_lbl.add_theme_font_size_override("font_size", 10)
	t_col.add_child(_balance_lbl)

	GameState.player_country_set.connect(_on_player_set)
	GameState.country_data_changed.connect(_on_data_changed)
	visible = false


func _draw_badge() -> void:
	var center: Vector2 = Vector2(20, 20)
	_badge.draw_circle(center, 17.0, _badge_color)
	_badge.draw_arc(center, 17.0, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.5), 1.5)
	var font: Font = ThemeDB.fallback_font
	if font != null and not _badge_iso.is_empty():
		_badge.draw_string(font, Vector2(center.x, center.y + 4.0), _badge_iso,
			HORIZONTAL_ALIGNMENT_CENTER, 34, 11, Color(1.0, 1.0, 1.0, 0.92))


func _on_player_set(iso: String) -> void:
	visible = true
	_refresh(iso)


func _on_data_changed(iso: String) -> void:
	if iso == GameState.player_iso:
		_refresh(iso)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Left half (flag + name) → Rankings panel
		# Right half (treasury) → Budget panel
		var click_x: float = event.position.x
		var mid: float = size.x * 0.4  # roughly where treasury section starts

		if click_x < mid:
			# Open rankings
			var rankings: Control = get_parent().get_node_or_null("RankingsPanel")
			if rankings != null and rankings.has_method("show_rankings"):
				# Close budget if open
				var budget: Control = get_parent().get_node_or_null("BudgetPanel")
				if budget != null:
					budget.visible = false
				rankings.show_rankings()
		else:
			# Open budget
			var budget: Control = get_parent().get_node_or_null("BudgetPanel")
			if budget != null:
				# Close rankings if open
				var rankings: Control = get_parent().get_node_or_null("RankingsPanel")
				if rankings != null:
					rankings.visible = false
				budget.visible = not budget.visible
				if budget.visible and budget.has_method("_load_from_data"):
					budget._load_from_data()
		accept_event()


func _refresh(iso: String) -> void:
	var data: Dictionary = GameState.get_country(iso)
	if data.is_empty():
		return

	# Flag
	var iso2: String = data.get("iso2", "")
	var flag_path: String = "res://assets/flags/%s.png" % iso2
	if not iso2.is_empty() and ResourceLoader.exists(flag_path):
		_flag_tex.texture = load(flag_path)
		_flag_tex.visible = true
		_badge.visible = false
	else:
		_flag_tex.visible = false
		_badge.visible = true
		var mc: Array = data.get("map_color", [80, 120, 180])
		_badge_color = Color(mc[0] / 255.0, mc[1] / 255.0, mc[2] / 255.0)
		_badge_iso = iso2 if not iso2.is_empty() else iso.substr(0, 2)
		_badge.queue_redraw()

	# Name + tier
	_name_lbl.text = data.get("name", iso)
	var tier: String = data.get("power_tier", "C")
	_tier_lbl.text = TIER_NAMES.get(tier, tier)
	_tier_lbl.add_theme_color_override("font_color", TIER_COLORS.get(tier, Color.GRAY))

	# Treasury
	var treasury: float = float(data.get("treasury", 0.0))
	_treasury_lbl.text = _fmt(treasury)
	_treasury_lbl.add_theme_color_override("font_color",
		Color(0.80, 1.0, 0.80) if treasury > 1.0 else Color(0.95, 0.35, 0.25))

	# Balance (green if positive, red if negative)
	var balance: float = float(data.get("_monthly_balance", 0.0))
	if absf(balance) < 0.001:
		# Compute live if no cached value yet (before first month tick)
		var gdp: float = float(data.get("gdp_raw_billions", 1.0))
		var tax: float = float(data.get("tax_rate", 0.25))
		var rev: float = gdp * tax / 12.0
		var dr: float = float(data.get("debt_to_gdp", 60))
		var cr: float = float(data.get("credit_rating", 50))
		var ir: float = lerpf(0.15, 0.01, cr / 100.0)
		var debt_svc: float = gdp * (dr / 100.0) * (ir / 12.0)
		var upkeep: float = MilitarySystem.get_total_upkeep(GameState.player_iso)
		balance = rev - debt_svc - upkeep
	if balance >= 0.01:
		_balance_lbl.text = "+%s/mo" % _fmt(balance)
		_balance_lbl.add_theme_color_override("font_color", Color(0.40, 0.78, 0.40))
	elif balance <= -0.01:
		_balance_lbl.text = "-%s/mo" % _fmt(absf(balance))
		_balance_lbl.add_theme_color_override("font_color", Color(0.90, 0.35, 0.28))
	else:
		_balance_lbl.text = "$0/mo"
		_balance_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))


func _fmt(b: float) -> String:
	if absf(b) >= 1000.0: return "$%.1fT" % (b / 1000.0)
	if absf(b) >= 1.0:    return "$%.1fB" % b
	if absf(b) >= 0.01:   return "$%.0fM" % (b * 1000.0)
	return "$0"
