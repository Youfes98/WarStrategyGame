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
var _pop_lbl:      Label = null
var _pop_change:   Label = null
var _treasury_col: VBoxContainer = null
var _pop_col:      VBoxContainer = null
var _pop_panel:    PanelContainer = null
var _pop_detail:   Label = null

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
	_treasury_col = VBoxContainer.new()
	var t_col: VBoxContainer = _treasury_col
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

	hbox.add_child(VSeparator.new())

	# ── Population ──
	_pop_col = VBoxContainer.new()
	var p_col: VBoxContainer = _pop_col
	p_col.add_theme_constant_override("separation", -2)
	hbox.add_child(p_col)

	var p_hdr := Label.new()
	p_hdr.text = "POPULATION"
	p_hdr.add_theme_font_size_override("font_size", 8)
	p_hdr.add_theme_color_override("font_color", Color(0.45, 0.50, 0.55))
	p_col.add_child(p_hdr)

	_pop_lbl = Label.new()
	_pop_lbl.add_theme_font_size_override("font_size", 14)
	_pop_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	p_col.add_child(_pop_lbl)

	_pop_change = Label.new()
	_pop_change.add_theme_font_size_override("font_size", 10)
	p_col.add_child(_pop_change)

	# ── Population dropdown panel ──
	_pop_panel = PanelContainer.new()
	_pop_panel.visible = false
	_pop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Color(0.06, 0.06, 0.08, 0.94)
	pop_style.corner_radius_bottom_left = 6
	pop_style.corner_radius_bottom_right = 6
	pop_style.content_margin_left = 12
	pop_style.content_margin_right = 12
	pop_style.content_margin_top = 8
	pop_style.content_margin_bottom = 8
	_pop_panel.add_theme_stylebox_override("panel", pop_style)
	_pop_detail = Label.new()
	_pop_detail.add_theme_font_size_override("font_size", 11)
	_pop_detail.add_theme_color_override("font_color", Color(0.80, 0.82, 0.88))
	_pop_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pop_panel.add_child(_pop_detail)
	# Will be positioned in _show_pop_info

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
		var click_x: float = event.position.x
		# Use actual column positions for accurate click zones
		var zone_1: float = _treasury_col.global_position.x - global_position.x if _treasury_col else size.x * 0.33
		var zone_2: float = _pop_col.global_position.x - global_position.x if _pop_col else size.x * 0.66

		# Close all panels first
		var rankings: Control = get_parent().get_node_or_null("RankingsPanel")
		var budget: Control = get_parent().get_node_or_null("BudgetPanel")

		if click_x < zone_1:
			# Flag/Name → Rankings
			if budget != null: budget.visible = false
			_pop_panel.visible = false
			if rankings != null and rankings.has_method("show_rankings"):
				rankings.show_rankings()
		elif click_x < zone_2:
			# Treasury → Budget
			if rankings != null: rankings.visible = false
			_pop_panel.visible = false
			if budget != null:
				budget.visible = not budget.visible
				if budget.visible and budget.has_method("_load_from_data"):
					budget._load_from_data()
		else:
			# Population → show population tooltip/info
			if rankings != null: rankings.visible = false
			if budget != null: budget.visible = false
			_show_pop_info()
		accept_event()


func _show_pop_info() -> void:
	# Toggle dropdown
	if _pop_panel.visible:
		_pop_panel.visible = false
		return

	# Add to HUD if not already
	if _pop_panel.get_parent() == null:
		get_parent().add_child(_pop_panel)

	var data: Dictionary = GameState.get_country(GameState.player_iso)
	var pop: int = int(data.get("population", 0))
	var gdp: float = float(data.get("gdp_raw_billions", 1.0))
	var gdp_pc: float = gdp * 1_000_000_000.0 / maxf(pop, 1.0)
	var stab: float = float(data.get("stability", 50))
	var literacy: int = int(data.get("literacy_rate", 50))
	var growth_rate: float
	if gdp_pc > 30000: growth_rate = 0.3
	elif gdp_pc > 10000: growth_rate = 0.7
	else: growth_rate = 1.0
	var stab_effect: String = "Positive" if stab > 40 else "Negative (emigration)"
	var at_war: bool = false
	for other: String in GameState.countries:
		if GameState.is_at_war(GameState.player_iso, other):
			at_war = true
			break

	_pop_detail.text = (
		"POPULATION OVERVIEW\n\n" +
		"Total: %s\n" % _fmt_pop(pop) +
		"GDP per capita: $%sK\n" % str(int(gdp_pc / 1000)) +
		"Annual growth: %.1f%%\n" % growth_rate +
		"Literacy rate: %d%%\n" % literacy +
		"Stability effect: %s\n" % stab_effect +
		"%s" % ("War penalty: -0.5%/yr" if at_war else "No active war penalties")
	)

	# Position below the ResourceBar, right-aligned to pop column
	_pop_panel.position = Vector2(
		maxf(_pop_col.global_position.x - 20 if _pop_col else size.x - 200, 0),
		size.y
	)
	_pop_panel.custom_minimum_size = Vector2(220, 0)
	_pop_panel.visible = true


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

	# Population
	var pop: int = int(data.get("population", 0))
	_pop_lbl.text = _fmt_pop(pop)
	var pop_delta: int = int(data.get("_pop_monthly_change", 0))
	if pop_delta == 0 and pop > 0:
		# Estimate before first month tick
		var gdp_b: float = float(data.get("gdp_raw_billions", 1.0))
		var gdp_pc: float = gdp_b * 1_000_000_000.0 / maxf(pop, 1.0)
		var annual: float = 0.01
		if gdp_pc > 30000: annual = 0.003
		elif gdp_pc > 10000: annual = 0.007
		pop_delta = int(float(pop) * annual / 12.0)
	if pop_delta > 0:
		_pop_change.text = "+%s/mo" % _fmt_pop(pop_delta)
		_pop_change.add_theme_color_override("font_color", Color(0.40, 0.78, 0.40))
	elif pop_delta < 0:
		_pop_change.text = "-%s/mo" % _fmt_pop(absi(pop_delta))
		_pop_change.add_theme_color_override("font_color", Color(0.90, 0.35, 0.28))
	else:
		_pop_change.text = ""


func _fmt_pop(p: int) -> String:
	if p >= 1_000_000_000: return "%.2fB" % (float(p) / 1_000_000_000.0)
	if p >= 1_000_000:     return "%.1fM" % (float(p) / 1_000_000.0)
	if p >= 1_000:         return "%.0fK" % (float(p) / 1_000.0)
	return str(p)


func _fmt(b: float) -> String:
	if absf(b) >= 1000.0: return "$%.1fT" % (b / 1000.0)
	if absf(b) >= 1.0:    return "$%.1fB" % b
	if absf(b) >= 0.01:   return "$%.0fM" % (b * 1000.0)
	return "$0"
