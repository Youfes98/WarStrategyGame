## UnitLayer.gd
## HoI4-style army counters at fixed screen size + fog of war.
## Converts world positions to screen space, draws counters without camera scaling.
extends Node2D

const MAP_WIDTH: float = 16384.0

const CHIP_W:       float = 28.0
const CHIP_H:       float = 16.0
const BAR_H:        float = 1.5
const CHIP_SPACING: float = 32.0
const FOG_RANGE:    float = 3  # provinces away from your territory/units to see enemies

const COL_SEL:      Color = Color(1.0, 1.0, 1.0, 0.95)
const COL_ICON:     Color = Color(1.0, 1.0, 1.0, 0.88)
const COL_DARKEN:   Color = Color(0.0, 0.0, 0.0, 0.22)
const COL_OUTLINE:  Color = Color(0.0, 0.0, 0.0, 0.45)
const COL_BAR_BG:   Color = Color(0.0, 0.0, 0.0, 0.55)
const COL_ORG:      Color = Color(0.25, 0.52, 0.30)
const COL_PATH:     Color = Color(0.0, 0.0, 0.0, 0.30)
const COL_PATH_SEL: Color = Color(0.12, 0.55, 0.12, 0.50)

var _font: Font = null
var _visible_provinces: Dictionary = {}  # provinces where enemy units are visible


func _ready() -> void:
	z_index = 10
	_font = ThemeDB.fallback_font
	MilitarySystem.units_changed.connect(_on_units_changed)
	MilitarySystem.selection_changed.connect(queue_redraw)
	MilitarySystem.territory_selected.connect(func(_iso: String) -> void: queue_redraw())
	MilitarySystem.battle_resolved.connect(
		func(_t: String, _a: String, _d: String, _w: bool) -> void: queue_redraw())


func _on_units_changed() -> void:
	_rebuild_fog()
	queue_redraw()


func _rebuild_fog() -> void:
	_visible_provinces.clear()
	var player: String = GameState.player_iso
	if player.is_empty():
		return

	# All provinces you own or have units in are visible
	var seeds: Array = []
	for pid: String in GameState.territory_owner:
		if GameState.territory_owner[pid] == player:
			_visible_provinces[pid] = true
			seeds.append(pid)

	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.owner == player:
			var loc: String = u.location
			if not _visible_provinces.has(loc):
				_visible_provinces[loc] = true
				seeds.append(loc)

	# BFS outward N steps from all seeds
	var frontier: Array = seeds.duplicate()
	for _step: int in int(FOG_RANGE):
		var next_frontier: Array = []
		for pid: String in frontier:
			for nb: String in ProvinceDB.get_neighbors(pid):
				if not _visible_provinces.has(nb):
					_visible_provinces[nb] = true
					next_frontier.append(nb)
		frontier = next_frontier


func _draw() -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var zoom: float = cam.zoom.x
	var cam_pos: Vector2 = cam.global_position
	var vp_size: Vector2 = get_viewport_rect().size

	# Gather army data — player units always, enemy units only in visible provinces
	var loc_armies: Dictionary = {}
	var army_paths: Dictionary = {}

	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		var is_player: bool = u.owner == player

		# Fog of war: skip enemy units in non-visible provinces
		if not is_player and not _visible_provinces.has(u.location):
			continue

		var loc: String = u.location
		var aid: String = u.get("army_id", "")
		if not loc_armies.has(loc):
			loc_armies[loc] = {}
		if not loc_armies[loc].has(aid):
			loc_armies[loc][aid] = {"n": 0, "str": 0.0, "inf": 0, "arm": 0, "art": 0, "owner": u.owner}
		var ad: Dictionary = loc_armies[loc][aid]
		match u.get("type", "infantry"):
			"infantry":  ad["inf"] = int(ad["inf"]) + 1
			"armor":     ad["arm"] = int(ad["arm"]) + 1
			"artillery": ad["art"] = int(ad["art"]) + 1
		ad["n"] = int(ad["n"]) + 1
		ad["str"] = float(ad["str"]) + float(u.get("strength", 100))

		# Only show paths for player armies
		if is_player:
			var path: Array = u.get("path", [])
			if not path.is_empty() and not army_paths.has(aid):
				army_paths[aid] = {"from": loc, "path": path}

	var sel_army: String = MilitarySystem.selected_army_id

	# Draw paths in world space
	draw_set_transform(Vector2.ZERO)
	for aid: String in army_paths:
		var info: Dictionary = army_paths[aid]
		_draw_path(info["from"], info["path"], aid == sel_army)

	# Draw counters at FIXED SCREEN SIZE
	# Strategy: use draw_set_transform to place at world pos with 1/zoom scale
	# The key insight: we set transform per-counter so position is exact
	for loc: String in loc_armies:
		var world_pos: Vector2 = ProvinceDB.get_centroid(loc)
		if world_pos == Vector2.ZERO:
			continue

		# Check all 3 wrapping positions, pick the one closest to screen center
		var best_world: Vector2 = world_pos
		var screen_center: float = cam_pos.x
		for x_off in [-MAP_WIDTH, MAP_WIDTH]:
			var alt: Vector2 = world_pos + Vector2(x_off, 0)
			if absf(alt.x - screen_center) < absf(best_world.x - screen_center):
				best_world = alt

		# Frustum cull: check if world pos is roughly on screen
		var half_vp: Vector2 = vp_size / (2.0 * zoom)
		if absf(best_world.x - cam_pos.x) > half_vp.x + 100 or \
		   absf(best_world.y - cam_pos.y) > half_vp.y + 100:
			continue

		var aids: Array = loc_armies[loc].keys()
		var draw_n: int = mini(aids.size(), 4)
		var s: float = 1.0 / zoom

		for i: int in draw_n:
			var ad: Dictionary = loc_armies[loc][aids[i]]
			var owner_iso: String = ad.get("owner", player)
			var odata: Dictionary = GameState.get_country(owner_iso)
			var omc: Array = odata.get("map_color", [80, 120, 180])
			var army_col: Color = Color(omc[0] / 255.0, omc[1] / 255.0, omc[2] / 255.0)

			var offset_x: float = (i - (draw_n - 1) * 0.5) * CHIP_SPACING * s
			var draw_pos: Vector2 = best_world + Vector2(offset_x, -(CHIP_H + 10) * s)
			draw_set_transform(draw_pos, 0.0, Vector2(s, s))
			_draw_counter(ad, army_col,
				MilitarySystem.is_army_selected(aids[i]),
				army_paths.has(aids[i]))

	draw_set_transform(Vector2.ZERO)


func _draw_counter(data: Dictionary, col: Color, selected: bool, moving: bool) -> void:
	var r: Rect2 = Rect2(-CHIP_W * 0.5, 0, CHIP_W, CHIP_H)

	if selected:
		draw_rect(r.grow(1.5), COL_SEL, false, 1.5)

	var fc: Color = col.lightened(0.10) if moving else col
	draw_rect(r, fc)
	draw_rect(Rect2(r.position.x, CHIP_H * 0.5, CHIP_W, CHIP_H * 0.5), COL_DARKEN)

	var inf: int = int(data.get("inf", 0))
	var arm: int = int(data.get("arm", 0))
	var art: int = int(data.get("art", 0))
	if arm >= inf and arm >= art:
		_draw_tank(0, CHIP_H * 0.4)
	elif art > inf and art > arm:
		_draw_artillery(0, CHIP_H * 0.4)
	else:
		_draw_infantry(0, CHIP_H * 0.4)

	if _font != null and int(data.get("n", 0)) > 1:
		draw_string(_font, Vector2(CHIP_W * 0.5 - 2.0, CHIP_H - 2.0),
			str(int(data.get("n", 0))), HORIZONTAL_ALIGNMENT_RIGHT, 12, 7, COL_ICON)

	draw_rect(r, COL_OUTLINE, false, 0.8)

	var avg: float = float(data.get("str", 0.0)) / float(maxi(int(data.get("n", 0)), 1))
	var fill: float = CHIP_W * (avg / 100.0)
	draw_rect(Rect2(-CHIP_W * 0.5, CHIP_H, CHIP_W, BAR_H), COL_BAR_BG)
	var bc: Color
	if avg > 70.0:   bc = Color(0.22, 0.70, 0.28)
	elif avg > 35.0: bc = Color(0.78, 0.62, 0.12)
	else:            bc = Color(0.78, 0.18, 0.14)
	draw_rect(Rect2(-CHIP_W * 0.5, CHIP_H, fill, BAR_H), bc)
	draw_rect(Rect2(-CHIP_W * 0.5, CHIP_H + BAR_H, CHIP_W, BAR_H), COL_BAR_BG)
	draw_rect(Rect2(-CHIP_W * 0.5, CHIP_H + BAR_H, fill, BAR_H), COL_ORG)


func _draw_infantry(cx: float, cy: float) -> void:
	var s: float = 3.5
	draw_line(Vector2(cx - s, cy - s), Vector2(cx + s, cy + s), COL_ICON, 1.2, true)
	draw_line(Vector2(cx + s, cy - s), Vector2(cx - s, cy + s), COL_ICON, 1.2, true)

func _draw_tank(cx: float, cy: float) -> void:
	draw_rect(Rect2(cx - 5.0, cy - 1.5, 10.0, 4.0), COL_ICON)
	draw_rect(Rect2(cx - 2.5, cy - 3.5, 5.0, 3.0), COL_ICON)
	draw_line(Vector2(cx + 2.5, cy - 2.5), Vector2(cx + 6.5, cy - 2.5), COL_ICON, 1.0, true)

func _draw_artillery(cx: float, cy: float) -> void:
	draw_line(Vector2(cx - 4.0, cy + 2.0), Vector2(cx + 1.0, cy + 2.0), COL_ICON, 1.5, true)
	draw_line(Vector2(cx, cy + 1.0), Vector2(cx + 5.0, cy - 3.0), COL_ICON, 1.2, true)
	draw_arc(Vector2(cx - 1.0, cy + 2.0), 2.0, 0.0, TAU, 8, COL_ICON, 0.8)


func _draw_path(from: String, path: Array, is_selected: bool) -> void:
	if path.is_empty():
		return
	var col: Color = COL_PATH_SEL if is_selected else COL_PATH
	var w: float = 3.0 if is_selected else 2.0
	var prev: Vector2 = ProvinceDB.get_centroid(from)
	if prev == Vector2.ZERO:
		return
	for i: int in path.size():
		var next: Vector2 = ProvinceDB.get_centroid(path[i])
		if next == Vector2.ZERO:
			continue
		draw_line(prev, next, col, w, true)
		prev = next
	var dest: Vector2 = ProvinceDB.get_centroid(path[path.size() - 1])
	var before: Vector2 = ProvinceDB.get_centroid(path[path.size() - 2] if path.size() >= 2 else from)
	if dest != Vector2.ZERO and before != Vector2.ZERO:
		var dir: Vector2 = (dest - before).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		draw_line(dest, dest - dir * 12.0 + perp * 6.0, col, 2.5, true)
		draw_line(dest, dest - dir * 12.0 - perp * 6.0, col, 2.5, true)
