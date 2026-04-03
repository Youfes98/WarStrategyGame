## UnitLayer.gd
## Draws HoI4-style rectangular unit counters with NATO icons, composition,
## strength bars, and movement arrows. Multiple armies fan out as stacked chips.
extends Node2D

const MAP_WIDTH: float = 8192.0

# Counter dimensions
const CHIP_W:     float = 72.0
const CHIP_H:     float = 36.0
const CHIP_GAP:   float = 6.0    # vertical gap when stacking
const STRIPE_H:   float = 4.0    # coloured owner stripe at top
const BAR_H:      float = 3.0    # strength bar height
const BAR_GAP:    float = 2.0    # gap between chip and bar

const COL_BG:      Color = Color(0.12, 0.12, 0.16, 0.92)
const COL_PLAYER:  Color = Color(0.25, 0.65, 1.0)
const COL_SEL:     Color = Color(1.0,  0.88, 0.22, 0.9)
const COL_ADJ:     Color = Color(0.35, 0.75, 1.0,  0.22)
const COL_ADJ_RIM: Color = Color(0.40, 0.80, 1.0,  0.55)
const COL_ARROW:   Color = Color(1.0,  0.92, 0.30, 0.75)
const COL_GARRISON: Color = Color(0.85, 0.25, 0.25, 0.75)

# NATO-style unit type symbols
const TYPE_ICONS: Dictionary = {
	"infantry":  "X",
	"armor":     ">>",
	"artillery": "*",
}

var _font:      Font = null
var _font_size: int  = 10
var _font_sm:   int  = 8


func _ready() -> void:
	z_index = 10
	_font = ThemeDB.fallback_font
	_font_size = 10
	_font_sm   = 8
	MilitarySystem.units_changed.connect(queue_redraw)
	MilitarySystem.territory_selected.connect(func(_iso: String) -> void: queue_redraw())
	MilitarySystem.battle_resolved.connect(func(_t: String, _a: String, _d: String, _w: bool) -> void: queue_redraw())


func _draw() -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
		draw_set_transform(Vector2(x_off, 0.0))
		_draw_units()
	draw_set_transform(Vector2.ZERO)


func _draw_units() -> void:
	var player: String = GameState.player_iso
	var sel_army: String = MilitarySystem.selected_army_id
	var sel_iso:  String = MilitarySystem.selected_iso

	# --- Adjacent highlights when army selected ---
	if sel_iso != "":
		for nb: String in ProvinceDB.get_neighbors(sel_iso):
			var c: Vector2 = ProvinceDB.get_centroid(nb)
			if c == Vector2.ZERO:
				continue
			draw_circle(c, 30.0, COL_ADJ)
			draw_arc(c, 30.0, 0.0, TAU, 32, COL_ADJ_RIM, 2.0)

			# Garrison indicator on enemy territories
			var ter_owner: String = GameState.territory_owner.get(nb, nb)
			if ter_owner != player and _font:
				var power: float = MilitarySystem.get_garrison_power(nb)
				var label: String = _garrison_label(power)
				var gpos: Vector2 = c + Vector2(-12.0, -4.0)
				draw_rect(Rect2(gpos, Vector2(24.0, 14.0)), COL_GARRISON.darkened(0.4))
				draw_string(_font, gpos + Vector2(2.0, 11.0), label,
					HORIZONTAL_ALIGNMENT_CENTER, 20, _font_sm, Color.WHITE)

	# --- Group player units by (location, army_id) → {type → count, total_str} ---
	# armies_at[iso] = [{army_id, types: {type→count}, total, avg_str}]
	var armies_at: Dictionary = {}
	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.owner != player:
			continue
		var loc: String = u.location
		var aid: String = u.get("army_id", "")
		if not armies_at.has(loc):
			armies_at[loc] = {}
		if not armies_at[loc].has(aid):
			armies_at[loc][aid] = {"types": {}, "total": 0, "str_sum": 0.0}
		var entry: Dictionary = armies_at[loc][aid]
		var utype: String = u.type
		entry["types"][utype] = entry["types"].get(utype, 0) + 1
		entry["total"] += 1
		entry["str_sum"] += float(u.strength)

	# --- Draw army chips ---
	for iso: String in armies_at:
		var centroid: Vector2 = ProvinceDB.get_centroid(iso)
		if centroid == Vector2.ZERO:
			continue

		var army_ids: Array = armies_at[iso].keys()
		var n: int = army_ids.size()

		for i: int in n:
			var aid: String = army_ids[i]
			var info: Dictionary = armies_at[iso][aid]
			var is_selected: bool = (aid == sel_army)

			# Stack chips vertically, centered on centroid
			var chip_y: float = centroid.y - (float(n) * (CHIP_H + CHIP_GAP)) * 0.5 + float(i) * (CHIP_H + CHIP_GAP)
			var chip_x: float = centroid.x - CHIP_W * 0.5
			var chip_pos: Vector2 = Vector2(chip_x, chip_y)

			_draw_chip(chip_pos, info, is_selected)

	# --- Movement arrows ---
	var drawn: Dictionary = {}
	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.destination.is_empty() or u.owner != player:
			continue
		var key: String = "%s:%s" % [u.get("army_id", uid), u.destination]
		if drawn.has(key):
			continue
		drawn[key] = true
		var from: Vector2 = ProvinceDB.get_centroid(u.location)
		var to:   Vector2 = ProvinceDB.get_centroid(u.destination)
		if from != Vector2.ZERO and to != Vector2.ZERO:
			_draw_arrow(from, to, COL_ARROW)


func _draw_chip(pos: Vector2, info: Dictionary, selected: bool) -> void:
	var types: Dictionary = info["types"]
	var total: int        = info["total"]
	var avg_str: float    = info["str_sum"] / maxf(float(total), 1.0)

	# Selection glow
	if selected:
		draw_rect(Rect2(pos - Vector2(3, 3), Vector2(CHIP_W + 6, CHIP_H + 6)), COL_SEL, false, 2.0)

	# Background
	draw_rect(Rect2(pos, Vector2(CHIP_W, CHIP_H)), COL_BG)

	# Owner stripe at top
	draw_rect(Rect2(pos, Vector2(CHIP_W, STRIPE_H)), COL_PLAYER)

	# Border
	draw_rect(Rect2(pos, Vector2(CHIP_W, CHIP_H)), Color(0.4, 0.5, 0.6, 0.6), false, 1.0)

	if _font == null:
		return

	# Unit composition lines
	var line_y: float = pos.y + STRIPE_H + 2.0
	for utype: String in types:
		var count: int = types[utype]
		var icon: String = TYPE_ICONS.get(utype, "?")
		var label: String = "%s %d" % [icon, count]
		draw_string(_font, Vector2(pos.x + 4.0, line_y + _font_sm),
			label, HORIZONTAL_ALIGNMENT_LEFT, int(CHIP_W - 8.0), _font_sm, Color(0.85, 0.9, 0.95))
		line_y += float(_font_sm) + 2.0

	# Total count on the right side
	var total_str: String = str(total)
	draw_string(_font, Vector2(pos.x + CHIP_W - 20.0, pos.y + CHIP_H - 4.0),
		total_str, HORIZONTAL_ALIGNMENT_RIGHT, 18, _font_size,
		Color(0.9, 0.95, 1.0, 0.8))

	# Strength bar below chip
	var bar_y: float = pos.y + CHIP_H + BAR_GAP
	var bar_w: float = CHIP_W
	draw_rect(Rect2(pos.x, bar_y, bar_w, BAR_H), Color(0.15, 0.15, 0.15, 0.8))
	var fill: float = bar_w * (avg_str / 100.0)
	var bar_col: Color = Color(0.2, 0.85, 0.2) if avg_str > 60.0 \
		else Color(0.9, 0.75, 0.1) if avg_str > 30.0 \
		else Color(0.9, 0.2, 0.2)
	draw_rect(Rect2(pos.x, bar_y, fill, BAR_H), bar_col)


func _garrison_label(power: float) -> String:
	if power >= 250.0: return "III"
	if power >= 150.0: return "II"
	if power >= 70.0:  return "I"
	return "0"


func _draw_arrow(from: Vector2, to: Vector2, col: Color) -> void:
	draw_line(from, to, col, 2.0)
	var dir:  Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip:  Vector2 = to - dir * 14.0
	draw_line(tip, tip - dir * 10.0 + perp * 5.0, col, 2.0)
	draw_line(tip, tip - dir * 10.0 - perp * 5.0, col, 2.0)
