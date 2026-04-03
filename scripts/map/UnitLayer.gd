## UnitLayer.gd
## Draws unit badges (one per army), garrison indicators, selection rings, and movement arrows.
extends Node2D

const BADGE_R:      float = 11.0
const BADGE_SPACING: float = 26.0   # center-to-center when multiple armies at same location
const COL_PLAYER:   Color = Color(0.25, 0.65, 1.0)
const COL_ENEMY:    Color = Color(0.90, 0.28, 0.28)
const COL_SEL:      Color = Color(1.0,  0.88, 0.22, 0.9)
const COL_ADJ:      Color = Color(0.35, 0.75, 1.0,  0.22)
const COL_ADJ_RIM:  Color = Color(0.40, 0.80, 1.0,  0.55)
const COL_ARROW:    Color = Color(1.0,  0.92, 0.30, 0.75)
const COL_GARRISON: Color = Color(0.85, 0.25, 0.25, 0.75)

var _font:      Font = null
var _font_size: int  = 11


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_font_size = ThemeDB.fallback_font_size
	if _font_size > 14:
		_font_size = 11
	MilitarySystem.units_changed.connect(queue_redraw)
	MilitarySystem.territory_selected.connect(func(_iso: String) -> void: queue_redraw())
	MilitarySystem.battle_resolved.connect(func(_t: String, _a: String, _d: String, _w: bool) -> void: queue_redraw())


const MAP_WIDTH: float = 8192.0

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

	# --- Adjacent highlights + enemy garrison indicators ---
	if sel_iso != "":
		for nb: String in ProvinceDB.get_neighbors(sel_iso):
			var c: Vector2 = ProvinceDB.get_centroid(nb)
			if c == Vector2.ZERO:
				continue
			draw_circle(c, 26.0, COL_ADJ)
			draw_arc(c, 26.0, 0.0, TAU, 32, COL_ADJ_RIM, 2.0)

			# Garrison power on enemy adjacent territories
			var ter_owner: String = GameState.territory_owner.get(nb, nb)
			if ter_owner != player and _font:
				var power: float = MilitarySystem.get_garrison_power(nb)
				var label: String = _garrison_label(power)
				draw_circle(c, BADGE_R, COL_GARRISON.darkened(0.3))
				draw_arc(c, BADGE_R, 0.0, TAU, 32, COL_GARRISON, 2.0)
				draw_string(_font,
					c + Vector2(-BADGE_R, _font_size * 0.38),
					label,
					HORIZONTAL_ALIGNMENT_CENTER,
					int(BADGE_R * 2), _font_size, Color.WHITE)

	# --- Group player units by location → army_id → count ---
	# loc_armies[iso] = { army_id: count }
	var loc_armies: Dictionary = {}
	for id: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[id]
		if u.owner != player:
			continue
		var loc: String = u.location
		var aid: String = u.get("army_id", "")
		if not loc_armies.has(loc):
			loc_armies[loc] = {}
		loc_armies[loc][aid] = loc_armies[loc].get(aid, 0) + 1

	# --- Draw army badges ---
	for iso: String in loc_armies:
		var centroid: Vector2 = ProvinceDB.get_centroid(iso)
		if centroid == Vector2.ZERO:
			continue

		var army_ids: Array = loc_armies[iso].keys()
		var n: int = army_ids.size()
		# Offset badges so they're centered on the centroid
		var total_w: float = (n - 1) * BADGE_SPACING
		var start_x: float = centroid.x - total_w * 0.5

		for i: int in n:
			var army_id: String = army_ids[i]
			var count: int      = loc_armies[iso][army_id]
			var pos: Vector2    = Vector2(start_x + i * BADGE_SPACING, centroid.y)

			var is_selected: bool = (army_id == sel_army)
			if is_selected:
				draw_arc(pos, BADGE_R + 4.0, 0.0, TAU, 36, COL_SEL, 2.5)

			draw_circle(pos, BADGE_R, COL_PLAYER.darkened(0.45))
			draw_arc(pos, BADGE_R, 0.0, TAU, 32, COL_PLAYER.lightened(0.15), 2.0)

			if _font:
				draw_string(_font,
					pos + Vector2(-BADGE_R, _font_size * 0.38),
					str(count),
					HORIZONTAL_ALIGNMENT_CENTER,
					int(BADGE_R * 2), _font_size, Color.WHITE)

		# Strength bar below the badge group (avg strength of all units at location)
		_draw_strength_bar(centroid, iso)

	# --- Movement arrows (one per army per destination) ---
	var drawn: Dictionary = {}
	for id: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[id]
		if u.destination.is_empty() or u.owner != player:
			continue
		var key: String = "%s:%s" % [u.get("army_id", u.id), u.destination]
		if drawn.has(key):
			continue
		drawn[key] = true
		var from: Vector2 = ProvinceDB.get_centroid(u.location)
		var to:   Vector2 = ProvinceDB.get_centroid(u.destination)
		if from != Vector2.ZERO and to != Vector2.ZERO:
			_draw_arrow(from, to, COL_ARROW)


func _draw_strength_bar(centroid: Vector2, iso: String) -> void:
	var all_units: Array = MilitarySystem.get_player_units_at(iso)
	if all_units.is_empty():
		return
	var avg_str: float = 0.0
	for u: Dictionary in all_units:
		avg_str += float(u.strength)
	avg_str /= all_units.size()

	var bar_w: float = BADGE_R * 2.0
	var bar_h: float = 3.0
	var bar_x: float = centroid.x - bar_w * 0.5
	var bar_y: float = centroid.y + BADGE_R + 3.0
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.2, 0.8))
	var fill: float = bar_w * (avg_str / 100.0)
	var col: Color  = Color(0.2, 0.85, 0.2) if avg_str > 60.0 \
					else Color(0.9, 0.75, 0.1) if avg_str > 30.0 \
					else Color(0.9, 0.2, 0.2)
	draw_rect(Rect2(bar_x, bar_y, fill, bar_h), col)


func _garrison_label(power: float) -> String:
	if power >= 250: return "★★★"
	if power >= 150: return "★★"
	if power >= 70:  return "★"
	return "◆"


func _draw_arrow(from: Vector2, to: Vector2, col: Color) -> void:
	draw_line(from, to, col, 2.0)
	var dir:  Vector2 = (to - from).normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var tip:  Vector2 = to - dir * BADGE_R
	draw_line(tip, tip - dir * 10.0 + perp * 5.0, col, 2.0)
	draw_line(tip, tip - dir * 10.0 - perp * 5.0, col, 2.0)
