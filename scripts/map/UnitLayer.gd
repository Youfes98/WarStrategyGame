## UnitLayer.gd
## Draws HoI4-style rectangular military counters and movement path lines.
extends Node2D

const MAP_WIDTH: float = 16384.0

const CHIP_W:       float = 80.0
const CHIP_H:       float = 38.0
const CHIP_PAD:     float = 5.0
const STRIPE_H:     float = 4.0
const BAR_H:        float = 3.0
const CHIP_SPACING: float = 86.0

const COL_BG:       Color = Color(0.06, 0.08, 0.12, 0.94)
const COL_OUTLINE:  Color = Color(0.25, 0.35, 0.50, 0.70)
const COL_PLAYER:   Color = Color(0.20, 0.55, 0.95)
const COL_ENEMY:    Color = Color(0.85, 0.20, 0.20)
const COL_SEL:      Color = Color(1.0,  0.85, 0.22, 0.95)
const COL_TEXT:     Color = Color(0.90, 0.92, 0.96)
const COL_TEXT_DIM: Color = Color(0.50, 0.55, 0.62)
const COL_ADJ:      Color = Color(0.30, 0.70, 1.0,  0.12)
const COL_ADJ_RIM:  Color = Color(0.35, 0.75, 1.0,  0.40)
const COL_PATH:     Color = Color(0.90, 0.80, 0.20, 0.55)
const COL_PATH_DOT: Color = Color(1.0,  0.90, 0.30, 0.70)

var _font: Font = null


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
	var scale: float = clampf(1.0 / maxf(zoom, 0.1), 0.35, 3.5)

	for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
		draw_set_transform(Vector2(x_off, 0.0), 0.0, Vector2(scale, scale))
		_draw_world(player, scale)
	draw_set_transform(Vector2.ZERO)


func _draw_world(player: String, scale: float) -> void:
	var sel_army: String = MilitarySystem.selected_army_id
	var sel_iso:  String = MilitarySystem.selected_iso
	var inv_s:    float  = 1.0 / scale

	# Adjacent highlights
	if not sel_iso.is_empty():
		for nb: String in ProvinceDB.get_neighbors(sel_iso):
			var c: Vector2 = ProvinceDB.get_centroid(nb) * inv_s
			if c == Vector2.ZERO:
				continue
			draw_circle(c, 20.0, COL_ADJ)
			draw_arc(c, 20.0, 0.0, TAU, 32, COL_ADJ_RIM, 1.5)

	# Gather army data
	var loc_armies: Dictionary = {}
	var army_paths: Dictionary = {}

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

		var ad: Dictionary = loc_armies[loc][aid]
		var utype: String = u.get("type", "infantry")
		ad[utype] = int(ad.get(utype, 0)) + 1
		ad["unit_count"] = int(ad["unit_count"]) + 1
		ad["strength_sum"] = float(ad["strength_sum"]) + float(u.get("strength", 100))

		var path: Array = u.get("path", [])
		if not path.is_empty() and not army_paths.has(aid):
			army_paths[aid] = {"from": loc, "path": path}

	# Draw movement paths
	for aid: String in army_paths:
		var info: Dictionary = army_paths[aid]
		_draw_path(info["from"], info["path"], inv_s, aid == sel_army)

	# Draw counters
	for loc: String in loc_armies:
		var centroid: Vector2 = ProvinceDB.get_centroid(loc) * inv_s
		if centroid == Vector2.ZERO:
			continue

		var base: Vector2 = centroid - Vector2(0, CHIP_H * 0.9)
		var army_ids: Array = loc_armies[loc].keys()
		var n: int = army_ids.size()
		var total_w: float = (n - 1) * CHIP_SPACING
		var start_x: float = base.x - total_w * 0.5

		for i: int in n:
			var aid: String = army_ids[i]
			var ad: Dictionary = loc_armies[loc][aid]
			var pos: Vector2 = Vector2(start_x + i * CHIP_SPACING, base.y)
			_draw_counter(pos, aid, ad, MilitarySystem.is_army_selected(aid), army_paths.has(aid))


func _draw_counter(pos: Vector2, army_id: String, data: Dictionary,
		selected: bool, moving: bool) -> void:
	var rect: Rect2 = Rect2(pos.x - CHIP_W * 0.5, pos.y - CHIP_H * 0.5, CHIP_W, CHIP_H)

	if selected:
		draw_rect(rect.grow(3.0), COL_SEL, false, 2.5)

	draw_rect(rect, COL_BG)
	draw_rect(rect, COL_OUTLINE, false, 1.0)

	var stripe_col: Color = COL_PLAYER.lightened(0.15) if moving else COL_PLAYER
	draw_rect(Rect2(rect.position.x, rect.position.y, CHIP_W, STRIPE_H), stripe_col)

	if _font == null:
		return

	var y1: float = rect.position.y + STRIPE_H + 14.0
	var x: float = rect.position.x + CHIP_PAD

	# Composition: "5 INF  3 ARM  2 ART"
	var parts: Array[String] = []
	for utype: String in ["infantry", "armor", "artillery"]:
		var count: int = int(data.get(utype, 0))
		if count > 0:
			var short: String = {"infantry": "I", "armor": "A", "artillery": "R"}[utype]
			parts.append("%d%s" % [count, short])
	draw_string(_font, Vector2(x, y1), " ".join(parts),
		HORIZONTAL_ALIGNMENT_LEFT, int(CHIP_W - CHIP_PAD * 2), 10, COL_TEXT)

	# Army label + status
	var y2: float = y1 + 12.0
	var label: String = army_id.replace("a", "Army ")
	if moving:
		label += " (moving)"
	draw_string(_font, Vector2(x, y2), label,
		HORIZONTAL_ALIGNMENT_LEFT, int(CHIP_W - CHIP_PAD * 2), 9, COL_TEXT_DIM)

	# Strength bar
	var bar_y: float = rect.position.y + CHIP_H + 2.0
	draw_rect(Rect2(rect.position.x, bar_y, CHIP_W, BAR_H), Color(0.12, 0.12, 0.12, 0.85))

	var total: int = maxi(int(data.get("unit_count", 0)), 1)
	var avg: float = float(data.get("strength_sum", 0.0)) / float(total)
	var fill: float = CHIP_W * (avg / 100.0)
	var bar_col: Color
	if avg > 60.0:    bar_col = Color(0.15, 0.72, 0.25)
	elif avg > 30.0:  bar_col = Color(0.82, 0.68, 0.10)
	else:             bar_col = Color(0.82, 0.18, 0.15)
	draw_rect(Rect2(rect.position.x, bar_y, fill, BAR_H), bar_col)


func _draw_path(from: String, path: Array, inv_s: float, is_selected: bool) -> void:
	if path.is_empty():
		return
	var col: Color = COL_PATH.lightened(0.3) if is_selected else COL_PATH
	var dot_col: Color = COL_SEL if is_selected else COL_PATH_DOT
	var w: float = 2.0 if is_selected else 1.5

	var prev: Vector2 = ProvinceDB.get_centroid(from) * inv_s
	if prev == Vector2.ZERO:
		return

	for i: int in path.size():
		var next: Vector2 = ProvinceDB.get_centroid(path[i]) * inv_s
		if next == Vector2.ZERO:
			continue
		_draw_dashed_line(prev, next, col, w, 8.0, 4.0)
		draw_circle(next, 3.0, dot_col)
		prev = next

	# Arrowhead at destination
	var dest: Vector2 = ProvinceDB.get_centroid(path[path.size() - 1]) * inv_s
	var before: Vector2
	if path.size() >= 2:
		before = ProvinceDB.get_centroid(path[path.size() - 2]) * inv_s
	else:
		before = ProvinceDB.get_centroid(from) * inv_s
	if dest != Vector2.ZERO and before != Vector2.ZERO:
		var dir: Vector2 = (dest - before).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(dest, dest - dir * 10.0 + perp * 5.0, dot_col, 2.0, true)
		draw_line(dest, dest - dir * 10.0 - perp * 5.0, dot_col, 2.0, true)


func _draw_dashed_line(from: Vector2, to: Vector2, col: Color,
		width: float, dash: float, gap: float) -> void:
	var dir: Vector2 = to - from
	var length: float = dir.length()
	if length < 1.0:
		return
	dir = dir / length
	var at: float = 0.0
	while at < length:
		var end_at: float = minf(at + dash, length)
		draw_line(from + dir * at, from + dir * end_at, col, width, true)
		at = end_at + gap
