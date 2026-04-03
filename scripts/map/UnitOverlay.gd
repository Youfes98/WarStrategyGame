## UnitOverlay.gd
## Renders unit sprites in screen space (HUD CanvasLayer).
## Camera2D zoom has ZERO effect — sprites are always the same pixel size.
## Converts world positions → screen positions each frame.
extends Control

const MAP_WIDTH: float = 16384.0

const SPRITE_SIZE: float = 32.0
const RING_RADIUS: float = 14.0
const RING_WIDTH:  float = 2.0
const UNIT_SPACING: float = 38.0
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

	# Gather units
	var loc_armies: Dictionary = {}
	var army_paths: Dictionary = {}

	for uid: String in MilitarySystem.units:
		var u: Dictionary = MilitarySystem.units[uid]
		var is_player: bool = u.owner == player
		if not is_player and not _visible_provinces.has(u.location):
			continue
		var loc: String = u.location
		var aid: String = u.get("army_id", "")
		if not loc_armies.has(loc):
			loc_armies[loc] = {}
		if not loc_armies[loc].has(aid):
			loc_armies[loc][aid] = {"units": [], "owner": u.owner}
		(loc_armies[loc][aid]["units"] as Array).append(u)
		if is_player:
			var path: Array = u.get("path", [])
			if not path.is_empty() and not army_paths.has(aid):
				army_paths[aid] = {"from": loc, "path": path}

	var sel_army: String = MilitarySystem.selected_army_id

	# Draw movement paths (in screen space)
	for aid: String in army_paths:
		var info: Dictionary = army_paths[aid]
		_draw_path_screen(info["from"], info["path"], aid == sel_army, cam_pos)

	# Draw unit sprites at fixed screen pixel size
	for loc: String in loc_armies:
		var world_pos: Vector2 = ProvinceDB.get_centroid(loc)
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

		var armies: Dictionary = loc_armies[loc]
		var army_keys: Array = armies.keys()
		var n: int = army_keys.size()
		var draw_n: int = mini(n, 6)
		var total_w: float = (draw_n - 1) * UNIT_SPACING
		var start_x: float = screen_pos.x - total_w * 0.5
		var base_y: float = screen_pos.y - SPRITE_SIZE * 0.8

		for i: int in draw_n:
			var aid: String = army_keys[i]
			var army_data: Dictionary = armies[aid]
			var army_units: Array = army_data["units"]
			var owner_iso: String = army_data["owner"]

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

			var cx: float = start_x + i * UNIT_SPACING
			var cy: float = base_y
			var is_sel: bool = MilitarySystem.is_army_selected(aid)

			_draw_unit_at(Vector2(cx, cy), dominant_type, total_n, avg_str, avg_mor,
				owner_col, is_sel)


func _draw_unit_at(pos: Vector2, unit_type: String, count: int,
		avg_str: float, avg_mor: float, owner_col: Color, selected: bool) -> void:
	var cx: float = pos.x
	var cy: float = pos.y

	# Health ring background
	draw_arc(pos, RING_RADIUS, 0.0, TAU, 24, COL_HEALTH_BG, RING_WIDTH + 1.0)

	# Owner color ring
	draw_arc(pos, RING_RADIUS + 2.0, 0.0, TAU, 24, owner_col.lightened(0.3), 1.5)

	# Health arc
	var health_pct: float = avg_str / 100.0
	var health_col: Color
	if avg_str > 70.0:   health_col = COL_HEALTH_OK
	elif avg_str > 35.0: health_col = COL_HEALTH_MID
	else:                health_col = COL_HEALTH_LOW
	if health_pct > 0.01:
		draw_arc(pos, RING_RADIUS, -PI * 0.5,
			-PI * 0.5 + TAU * health_pct, 24, health_col, RING_WIDTH)

	# Selection ring
	if selected:
		draw_arc(pos, RING_RADIUS + 4.0, 0.0, TAU, 24, COL_SEL_RING, 2.0)

	# Unit sprite
	var sprite_name: String = MilitarySystem.UNIT_TYPES.get(unit_type, {}).get("sprite", "infantry")
	var tex: Texture2D = _sprites.get(sprite_name)
	if tex != null:
		var tex_size: Vector2 = tex.get_size()
		var draw_size: float = SPRITE_SIZE * 0.7
		var scale_f: float = draw_size / maxf(tex_size.x, tex_size.y)
		var offset: Vector2 = pos - tex_size * scale_f * 0.5
		draw_texture_rect(tex, Rect2(offset, tex_size * scale_f), false)

	# Unit count badge
	if count > 1 and _font != null:
		draw_string(_font, Vector2(cx + 10.0, cy + RING_RADIUS + 2.0),
			str(count), HORIZONTAL_ALIGNMENT_CENTER, 20, 9, Color.WHITE)

	# Morale indicator (small bar below health ring)
	if avg_mor < 70.0:
		var mor_w: float = 16.0
		var mor_h: float = 2.0
		var mor_x: float = cx - mor_w * 0.5
		var mor_y: float = cy + RING_RADIUS + 6.0
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
