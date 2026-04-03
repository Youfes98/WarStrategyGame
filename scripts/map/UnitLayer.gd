## UnitLayer.gd
## Draws HoI4-style rectangular military counters per army.
## Each counter shows: colored faction stripe, NATO unit symbols,
## composition counts, army ID, and a strength bar.
extends Node2D

const MAP_WIDTH: float = 8192.0

# Counter dimensions (in map-space pixels, scaled by zoom)
const CHIP_W:       float = 72.0
const CHIP_H:       float = 34.0
const CHIP_PAD:     float = 4.0
const STRIPE_H:     float = 4.0
const BAR_H:        float = 3.0
const CHIP_SPACING: float = 78.0   # horizontal gap between stacked armies

# Colors
const COL_BG:        Color = Color(0.08, 0.10, 0.14, 0.92)
const COL_BG_HOVER:  Color = Color(0.12, 0.15, 0.22, 0.92)
const COL_PLAYER:    Color = Color(0.20, 0.55, 0.95)
const COL_ENEMY:     Color = Color(0.85, 0.20, 0.20)
const COL_NEUTRAL:   Color = Color(0.50, 0.50, 0.50)
const COL_SEL_RING:  Color = Color(1.0,  0.88, 0.22, 0.9)
const COL_TEXT:      Color = Color(0.88, 0.90, 0.94)
const COL_TEXT_DIM:  Color = Color(0.55, 0.58, 0.65)
const COL_ADJ:       Color = Color(0.35, 0.75, 1.0,  0.18)
const COL_ADJ_RIM:   Color = Color(0.40, 0.80, 1.0,  0.50)
const COL_ARROW:     Color = Color(1.0,  0.92, 0.30, 0.70)
const COL_GARRISON:  Color = Color(0.70, 0.20, 0.20, 0.70)

# NATO-style symbols for unit types
const UNIT_SYMBOLS: Dictionary = {
	"infantry":  "X",
	"armor":     ">>",
	"artillery": "*",
}

const UNIT_SHORT: Dictionary = {
	"infantry":  "Inf",
	"armor":     "Arm",
	"artillery": "Art",
}

var _font:      Font = null
var _font_sm:   int  = 9
var _font_md:   int  = 11
var _font_lg:   int  = 13


func _ready() -> void:
	z_index = 10
	_font = ThemeDB.fallback_font
	MilitarySystem.units_changed.connect(queue_redraw)
	MilitarySystem.territory_selected.connect(func(_iso: String) -> void: queue_redraw())
	MilitarySystem.battle_resolved.connect(
		func(_t: String, _a: String, _d: String, _w: bool) -> void: queue_redraw())


func _draw() -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var zoom: float = cam.zoom.x

	# Scale chips so they stay readable at any zoom
	var inv_zoom: float = 1.0 / maxf(zoom, 0.1)
	var scale: float = clampf(inv_zoom, 0.4, 3.0)

	for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
		draw_set_transform(Vector2(x_off, 0.0), 0.0, Vector2(scale, scale))
		_draw_all(player, scale)
	draw_set_transform(Vector2.ZERO)


func _draw_all(player: String, scale: float) -> void:
	var sel_army: String = MilitarySystem.selected_army_id
	var sel_iso:  String = MilitarySystem.selected_iso
	var inv_s: float = 1.0 / scale

	# ── Adjacent territory highlights ─────────────────────────────────────
	if sel_iso != "":
		for nb: String in ProvinceDB.get_neighbors(sel_iso):
			var c: Vector2 = ProvinceDB.get_centroid(nb) * inv_s
			if c == Vector2.ZERO:
				continue
			draw_circle(c, 22.0, COL_ADJ)
			draw_arc(c, 22.0, 0.0, TAU, 32, COL_ADJ_RIM, 1.5)

	# ── Group player armies by location ───────────────────────────────────
	var loc_armies: Dictionary = {}
	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.owner != player:
			continue
		var loc: String = u.location
		var aid: String = u.get("army_id", "")
		if not loc_armies.has(loc):
			loc_armies[loc] = {}
		if not loc_armies[loc].has(aid):
			loc_armies[loc][aid] = {"unit_count": 0, "strength_sum": 0.0}
		var army_data: Dictionary = loc_armies[loc][aid]
		var utype: String = u.get("type", "infantry")
		army_data[utype] = army_data.get(utype, 0) + 1
		army_data["unit_count"] = int(army_data["unit_count"]) + 1
		army_data["strength_sum"] = float(army_data["strength_sum"]) + float(u.get("strength", 100))

	# ── Draw army counters ────────────────────────────────────────────────
	for loc: String in loc_armies:
		var centroid: Vector2 = ProvinceDB.get_centroid(loc)
		if centroid == Vector2.ZERO:
			continue

		var base: Vector2 = centroid * inv_s
		base.y -= CHIP_H * 0.8

		var army_ids: Array = loc_armies[loc].keys()
		var n: int = army_ids.size()
		var total_w: float = (n - 1) * CHIP_SPACING
		var start_x: float = base.x - total_w * 0.5

		for i: int in n:
			var army_id: String = army_ids[i]
			var army_data: Dictionary = loc_armies[loc][army_id]
			var pos: Vector2 = Vector2(start_x + i * CHIP_SPACING, base.y)
			var is_selected: bool = (army_id == sel_army)

			_draw_counter(pos, army_id, army_data, is_selected, COL_PLAYER)

	# ── Movement arrows ───────────────────────────────────────────────────
	var drawn: Dictionary = {}
	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.destination.is_empty() or u.owner != player:
			continue
		var key: String = "%s:%s" % [u.get("army_id", u.id), u.destination]
		if drawn.has(key):
			continue
		drawn[key] = true
		var from: Vector2 = ProvinceDB.get_centroid(u.location) * inv_s
		var to:   Vector2 = ProvinceDB.get_centroid(u.destination) * inv_s
		if from != Vector2.ZERO and to != Vector2.ZERO:
			_draw_arrow(from, to)


func _draw_counter(pos: Vector2, army_id: String, data: Dictionary, selected: bool, faction_col: Color) -> void:
	var rect: Rect2 = Rect2(pos.x - CHIP_W * 0.5, pos.y - CHIP_H * 0.5, CHIP_W, CHIP_H)

	# Selection glow
	if selected:
		draw_rect(rect.grow(3.0), COL_SEL_RING, false, 2.0)

	# Background
	draw_rect(rect, COL_BG)

	# Faction stripe across top
	draw_rect(Rect2(rect.position.x, rect.position.y, CHIP_W, STRIPE_H), faction_col)

	# ── Unit composition ──────────────────────────────────────────────────
	var y_line1: float = rect.position.y + STRIPE_H + 2.0 + _font_md
	var x_cursor: float = rect.position.x + CHIP_PAD

	# Build composition string: "X5 >>3 *2"
	var comp_parts: Array[String] = []
	for utype: String in ["infantry", "armor", "artillery"]:
		var count: int = int(data.get(utype, 0))
		if count > 0:
			comp_parts.append("%s%d" % [UNIT_SYMBOLS.get(utype, "?"), count])

	var comp_text: String = " ".join(comp_parts)
	if _font:
		draw_string(_font, Vector2(x_cursor, y_line1), comp_text,
			HORIZONTAL_ALIGNMENT_LEFT, int(CHIP_W - CHIP_PAD * 2), _font_md, COL_TEXT)

	# Army ID (small, right-aligned)
	var army_label: String = army_id.to_upper().replace("A0", "#")
	if _font:
		draw_string(_font, Vector2(rect.position.x + CHIP_W - CHIP_PAD - 24.0, y_line1),
			army_label, HORIZONTAL_ALIGNMENT_RIGHT, 24, _font_sm, COL_TEXT_DIM)

	# ── Total unit count (line 2) ─────────────────────────────────────────
	var total: int = int(data.get("unit_count", 0))
	var y_line2: float = y_line1 + _font_sm + 1.0
	if _font:
		draw_string(_font, Vector2(x_cursor, y_line2), "%d units" % total,
			HORIZONTAL_ALIGNMENT_LEFT, int(CHIP_W - CHIP_PAD * 2), _font_sm, COL_TEXT_DIM)

	# ── Strength bar ──────────────────────────────────────────────────────
	var bar_y: float = rect.position.y + CHIP_H + 2.0
	draw_rect(Rect2(rect.position.x, bar_y, CHIP_W, BAR_H), Color(0.15, 0.15, 0.15, 0.8))

	var avg_str: float = 0.0
	if total > 0:
		avg_str = float(data.get("strength_sum", 0.0)) / float(total)
	var fill_w: float = CHIP_W * (avg_str / 100.0)
	var bar_col: Color
	if avg_str > 60.0:
		bar_col = Color(0.15, 0.75, 0.25)
	elif avg_str > 30.0:
		bar_col = Color(0.85, 0.70, 0.10)
	else:
		bar_col = Color(0.85, 0.20, 0.15)
	draw_rect(Rect2(rect.position.x, bar_y, fill_w, BAR_H), bar_col)


func _draw_arrow(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, COL_ARROW, 2.0, true)
	var dir:  Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip:  Vector2 = to - dir * 12.0
	draw_line(tip, tip - dir * 10.0 + perp * 5.0, COL_ARROW, 2.0, true)
	draw_line(tip, tip - dir * 10.0 - perp * 5.0, COL_ARROW, 2.0, true)
