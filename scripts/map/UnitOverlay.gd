## UnitOverlay.gd
## Renders unit sprites in screen space (HUD CanvasLayer).
## Camera2D zoom has ZERO effect — sprites are always the same pixel size.
## Converts world positions → screen positions each frame.
extends Control

const MAP_WIDTH: float = 16384.0

const BASE_SPRITE_SIZE: float = 32.0
const BASE_RING_RADIUS: float = 14.0
const BASE_RING_WIDTH:  float = 2.0
const BASE_SPACING:     float = 38.0
const FOG_RANGE:    int = 3

const COL_SEL_RING:  Color = Color(1.0, 1.0, 1.0, 0.90)
const COL_HEALTH_OK: Color = Color(0.20, 0.75, 0.25)
const COL_HEALTH_MID:Color = Color(0.85, 0.70, 0.10)
const COL_HEALTH_LOW:Color = Color(0.85, 0.15, 0.12)
const COL_HEALTH_BG: Color = Color(0.0, 0.0, 0.0, 0.40)
const COL_OWNER_RING:Color = Color(1.0, 1.0, 1.0, 0.25)
const COL_PATH:      Color = Color(0.25, 0.65, 0.25, 0.50)
const COL_PATH_SEL:  Color = Color(0.30, 0.80, 0.30, 0.70)

var _font: Font = null
var _sprites: Dictionary = {}
var _visible_provinces: Dictionary = {}
var _cam: Camera2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_load_sprites()
	MilitarySystem.units_changed.connect(_on_units_changed)
	MilitarySystem.selection_changed.connect(queue_redraw)
	MilitarySystem.territory_selected.connect(func(_iso: String) -> void: queue_redraw())
	MilitarySystem.battle_resolved.connect(
		func(_t: String, _a: String, _d: String, _w: bool) -> void: queue_redraw())


func _load_sprites() -> void:
	for type_key: String in MilitarySystem.UNIT_TYPES:
		var sprite_name: String = MilitarySystem.UNIT_TYPES[type_key].get("sprite", type_key)
		var path: String = "res://assets/units/%s.png" % sprite_name
		if ResourceLoader.exists(path):
			_sprites[sprite_name] = load(path)


func _on_units_changed() -> void:
	_rebuild_fog()
	queue_redraw()


func _process(_delta: float) -> void:
	# Redraw every frame so sprites track camera movement/zoom
	queue_redraw()


func _rebuild_fog() -> void:
	_visible_provinces.clear()
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	var seeds: Array = []
	for pid: String in GameState.territory_owner:
		if GameState.territory_owner[pid] == player:
			_visible_provinces[pid] = true
			seeds.append(pid)
	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		if u.owner == player and not _visible_provinces.has(u.location):
			_visible_provinces[u.location] = true
			seeds.append(u.location)
	var frontier: Array = seeds.duplicate()
	for _step: int in FOG_RANGE:
		var next_frontier: Array = []
		for pid: String in frontier:
			for nb: String in ProvinceDB.get_neighbors(pid):
				if not _visible_provinces.has(nb):
					_visible_provinces[nb] = true
					next_frontier.append(nb)
		frontier = next_frontier


## Convert world position to screen position using the map's camera.
func _world_to_screen(world_pos: Vector2) -> Vector2:
	if _cam == null:
		_cam = get_viewport().get_camera_2d()
	if _cam == null:
		return Vector2(-999, -999)
	var canvas_tf: Transform2D = get_viewport().get_canvas_transform()
	return canvas_tf * world_pos


func _draw() -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		return

	var vp_size: Vector2 = get_viewport_rect().size
	var cam_pos: Vector2 = _cam.global_position

	# Subtle zoom scaling: sprites grow a bit when zoomed in, shrink when zoomed out
	# At zoom 1.0 = base size, zoom 4.0 = ~1.5x, zoom 0.3 = ~0.7x
	var zoom: float = _cam.zoom.x
	var size_scale: float = clampf(0.6 + zoom * 0.25, 0.5, 1.8)
	var SPRITE_SIZE: float = BASE_SPRITE_SIZE * size_scale
	var RING_RADIUS: float = BASE_RING_RADIUS * size_scale
	var RING_WIDTH:  float = BASE_RING_WIDTH * size_scale
	var UNIT_SPACING: float = BASE_SPACING * size_scale

	# Gather units by army, track interpolated world positions
	var army_data: Dictionary = {}   # army_id → {units, owner, world_pos}
	var army_paths: Dictionary = {}

	var hour_frac: float = float(GameClock.date.hour) / 24.0

	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		var is_player: bool = u.owner == player
		if not is_player and not _visible_provinces.has(u.location):
			continue
		var aid: String = u.get("army_id", uid)
		if not army_data.has(aid):
			# Compute interpolated world position for this army
			var loc: String = u.location
			var path: Array = u.get("path", [])
			var world_pos: Vector2 = ProvinceDB.get_centroid(loc)

			if not path.is_empty() and world_pos != Vector2.ZERO:
				var next_prov: String = path[0]
				var next_pos: Vector2 = ProvinceDB.get_centroid(next_prov)
				if next_pos != Vector2.ZERO:
					var total_days: float = float(u.get("travel_days_total", u.get("days_remaining", 1)))
					if total_days < 1.0:
						total_days = 1.0
					var remaining: float = float(u.get("days_remaining", 0)) - hour_frac
					var progress: float = clampf(1.0 - remaining / total_days, 0.0, 1.0)
					world_pos = world_pos.lerp(next_pos, progress)

				if is_player:
					army_paths[aid] = {"from": loc, "path": path}

			army_data[aid] = {"units": [], "owner": u.owner, "world_pos": world_pos}
		(army_data[aid]["units"] as Array).append(u)

	var sel_army: String = MilitarySystem.selected_army_id

	# Draw movement paths (in screen space)
	for aid: String in army_paths:
		var info: Dictionary = army_paths[aid]
		_draw_path_screen(info["from"], info["path"], aid == sel_army, cam_pos)

	# Draw each army at its interpolated position
	for aid: String in army_data:
		var ad: Dictionary = army_data[aid]
		var world_pos: Vector2 = ad["world_pos"]
		if world_pos == Vector2.ZERO:
			continue

		# Pick best wrapping tile
		var best: Vector2 = world_pos
		for x_off in [-MAP_WIDTH, MAP_WIDTH]:
			var alt: Vector2 = world_pos + Vector2(x_off, 0)
			if absf(alt.x - cam_pos.x) < absf(best.x - cam_pos.x):
				best = alt

		var screen_pos: Vector2 = _world_to_screen(best)

		# Frustum cull
		if screen_pos.x < -60 or screen_pos.x > vp_size.x + 60 \
		   or screen_pos.y < -60 or screen_pos.y > vp_size.y + 60:
			continue

		var army_units: Array = ad["units"]
		var owner_iso: String = ad["owner"]

		# Compute army stats
		var type_counts: Dictionary = {}
		var total_str: float = 0.0
		var total_mor: float = 0.0
		var total_n: int = 0
		for u: Dictionary in army_units:
			var t: String = u.get("type", "infantry")
			type_counts[t] = int(type_counts.get(t, 0)) + 1
			total_str += float(u.get("strength", 100))
			total_mor += float(u.get("morale", 80))
			total_n += 1

		var dominant_type: String = "infantry"
		var max_count: int = 0
		for t: String in type_counts:
			if int(type_counts[t]) > max_count:
				max_count = type_counts[t]
				dominant_type = t

		var avg_str: float = total_str / maxf(total_n, 1)
		var avg_mor: float = total_mor / maxf(total_n, 1)

		var odata: Dictionary = GameState.get_country(owner_iso)
		var omc: Array = odata.get("map_color", [80, 120, 180])
		var owner_col: Color = Color(omc[0] / 255.0, omc[1] / 255.0, omc[2] / 255.0)

		var is_sel: bool = MilitarySystem.is_army_selected(aid)

		_draw_unit_at(screen_pos - Vector2(0, SPRITE_SIZE * 0.5), dominant_type,
			total_n, avg_str, avg_mor, owner_col, is_sel, size_scale)

	# Draw capital stars
	_draw_capital_stars(cam_pos, vp_size, size_scale)


func _draw_capital_stars(cam_pos: Vector2, vp_size: Vector2, ss: float) -> void:
	var star_size: float = 4.0 * ss
	var star_col: Color = Color(0.95, 0.85, 0.25, 0.85)
	var outline_col: Color = Color(0.0, 0.0, 0.0, 0.60)

	for iso: String in GameState.countries:
		var cap_pid: String = ProvinceDB.get_capital_province(iso)
		if cap_pid.is_empty():
			continue
		var world_pos: Vector2 = ProvinceDB.get_centroid(cap_pid)
		if world_pos == Vector2.ZERO:
			continue

		# Pick best wrap
		var best: Vector2 = world_pos
		for x_off in [-MAP_WIDTH, MAP_WIDTH]:
			var alt: Vector2 = world_pos + Vector2(x_off, 0)
			if absf(alt.x - cam_pos.x) < absf(best.x - cam_pos.x):
				best = alt

		var sp: Vector2 = _world_to_screen(best)
		if sp.x < -20 or sp.x > vp_size.x + 20 or sp.y < -20 or sp.y > vp_size.y + 20:
			continue

		# Draw small 4-pointed star
		_draw_star(sp, star_size, star_col, outline_col)


func _draw_star(pos: Vector2, sz: float, col: Color, outline: Color) -> void:
	# Simple 4-pointed star
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 8:
		var angle: float = i * TAU / 8.0 - PI * 0.5
		var r: float = sz if i % 2 == 0 else sz * 0.4
		points.append(pos + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, col)
	# Outline
	var outline_pts: PackedVector2Array = points.duplicate()
	outline_pts.append(points[0])
	draw_polyline(outline_pts, outline, 1.0, true)


func _draw_unit_at(pos: Vector2, unit_type: String, count: int,
		avg_str: float, avg_mor: float, owner_col: Color, selected: bool,
		ss: float = 1.0) -> void:
	var cx: float = pos.x
	var cy: float = pos.y
	var ring_r: float = BASE_RING_RADIUS * ss
	var ring_w: float = BASE_RING_WIDTH * ss
	var spr_size: float = BASE_SPRITE_SIZE * ss

	# Health ring background
	draw_arc(pos, ring_r, 0.0, TAU, 24, COL_HEALTH_BG, ring_w + 1.0)

	# Owner color ring
	draw_arc(pos, ring_r + 2.0 * ss, 0.0, TAU, 24, owner_col.lightened(0.3), 1.5 * ss)

	# Health arc
	var health_pct: float = avg_str / 100.0
	var health_col: Color
	if avg_str > 70.0:   health_col = COL_HEALTH_OK
	elif avg_str > 35.0: health_col = COL_HEALTH_MID
	else:                health_col = COL_HEALTH_LOW
	if health_pct > 0.01:
		draw_arc(pos, ring_r, -PI * 0.5,
			-PI * 0.5 + TAU * health_pct, 24, health_col, ring_w)

	# Selection ring
	if selected:
		draw_arc(pos, ring_r + 4.0 * ss, 0.0, TAU, 24, COL_SEL_RING, 2.0 * ss)

	# Unit sprite
	var sprite_name: String = MilitarySystem.UNIT_TYPES.get(unit_type, {}).get("sprite", "infantry")
	var tex: Texture2D = _sprites.get(sprite_name)
	if tex != null:
		var tex_size: Vector2 = tex.get_size()
		var draw_size: float = spr_size * 0.7
		var scale_f: float = draw_size / maxf(tex_size.x, tex_size.y)
		var offset: Vector2 = pos - tex_size * scale_f * 0.5
		draw_texture_rect(tex, Rect2(offset, tex_size * scale_f), false)

	# Unit count badge
	if count > 1 and _font != null:
		var fs: int = maxi(7, int(9.0 * ss))
		draw_string(_font, Vector2(cx + 10.0 * ss, cy + ring_r + 2.0),
			str(count), HORIZONTAL_ALIGNMENT_CENTER, 20, fs, Color.WHITE)

	# Morale indicator (small bar below health ring)
	if avg_mor < 70.0:
		var mor_w: float = 16.0 * ss
		var mor_h: float = 2.0 * ss
		var mor_x: float = cx - mor_w * 0.5
		var mor_y: float = cy + ring_r + 6.0 * ss
		draw_rect(Rect2(mor_x, mor_y, mor_w, mor_h), COL_HEALTH_BG)
		var mor_fill: float = mor_w * (avg_mor / 100.0)
		var mor_col: Color = Color(0.6, 0.6, 0.2) if avg_mor > 40 else Color(0.8, 0.2, 0.1)
		draw_rect(Rect2(mor_x, mor_y, mor_fill, mor_h), mor_col)


func _draw_path_screen(from: String, path: Array, is_selected: bool, cam_pos: Vector2) -> void:
	if path.is_empty():
		return
	var col: Color = COL_PATH_SEL if is_selected else COL_PATH
	var w: float = 2.5 if is_selected else 1.5

	var prev_world: Vector2 = ProvinceDB.get_centroid(from)
	if prev_world == Vector2.ZERO:
		return
	# Pick best wrap for start
	for x_off in [-MAP_WIDTH, MAP_WIDTH]:
		var alt: Vector2 = prev_world + Vector2(x_off, 0)
		if absf(alt.x - cam_pos.x) < absf(prev_world.x - cam_pos.x):
			prev_world = alt

	var prev_screen: Vector2 = _world_to_screen(prev_world)

	for i: int in path.size():
		var next_world: Vector2 = ProvinceDB.get_centroid(path[i])
		if next_world == Vector2.ZERO:
			continue
		for x_off in [-MAP_WIDTH, MAP_WIDTH]:
			var alt: Vector2 = next_world + Vector2(x_off, 0)
			if absf(alt.x - cam_pos.x) < absf(next_world.x - cam_pos.x):
				next_world = alt
		var next_screen: Vector2 = _world_to_screen(next_world)
		draw_line(prev_screen, next_screen, col, w, true)
		draw_circle(next_screen, 2.5, col)
		prev_screen = next_screen

	# Arrowhead
	if path.size() >= 1:
		var dest: Vector2 = _world_to_screen(ProvinceDB.get_centroid(path[path.size() - 1]))
		var before_id: String = path[path.size() - 2] if path.size() >= 2 else from
		var before: Vector2 = _world_to_screen(ProvinceDB.get_centroid(before_id))
		if dest.distance_squared_to(before) > 1.0:
			var dir: Vector2 = (dest - before).normalized()
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			draw_line(dest, dest - dir * 8.0 + perp * 4.0, col, 2.0, true)
			draw_line(dest, dest - dir * 8.0 - perp * 4.0, col, 2.0, true)
