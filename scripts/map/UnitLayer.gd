## UnitLayer.gd
## Renders unit sprites on the map — World Conqueror 4 style.
## Each unit shows its type sprite with a health ring underneath.
## Fixed screen size regardless of zoom. Fog of war hides distant enemies.
extends Node2D

const MAP_WIDTH: float = 16384.0

# Sprite sizing (screen pixels)
const SPRITE_SIZE: float = 32.0
const RING_RADIUS: float = 16.0
const RING_WIDTH:  float = 2.5
const UNIT_SPACING: float = 36.0
const FOG_RANGE:    int = 3

# Colors
const COL_SEL_RING:  Color = Color(1.0, 1.0, 1.0, 0.90)
const COL_HEALTH_OK: Color = Color(0.20, 0.75, 0.25)
const COL_HEALTH_MID:Color = Color(0.85, 0.70, 0.10)
const COL_HEALTH_LOW:Color = Color(0.85, 0.15, 0.12)
const COL_HEALTH_BG: Color = Color(0.0, 0.0, 0.0, 0.40)
const COL_OWNER_RING:Color = Color(1.0, 1.0, 1.0, 0.25)
const COL_PATH:      Color = Color(0.0, 0.0, 0.0, 0.30)
const COL_PATH_SEL:  Color = Color(0.12, 0.55, 0.12, 0.50)

var _font: Font = null
var _sprites: Dictionary = {}  # sprite_name → Texture2D
var _visible_provinces: Dictionary = {}


func _ready() -> void:
	z_index = 10
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
		if u.owner == player:
			var loc: String = u.location
			if not _visible_provinces.has(loc):
				_visible_provinces[loc] = true
				seeds.append(loc)
	var frontier: Array = seeds.duplicate()
	for _step: int in FOG_RANGE:
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
	var half_vp: Vector2 = vp_size / (2.0 * zoom)
	var s: float = 1.0 / zoom  # scale to get fixed screen size

	# Gather units by location → army
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

	# Draw paths in world space
	draw_set_transform(Vector2.ZERO)
	for aid: String in army_paths:
		var info: Dictionary = army_paths[aid]
		_draw_path(info["from"], info["path"], aid == sel_army)

	# Draw unit sprites at fixed screen size
	for loc: String in loc_armies:
		var world_pos: Vector2 = ProvinceDB.get_centroid(loc)
		if world_pos == Vector2.ZERO:
			continue

		# Pick best wrapping position
		var best: Vector2 = world_pos
		for x_off in [-MAP_WIDTH, MAP_WIDTH]:
			var alt: Vector2 = world_pos + Vector2(x_off, 0)
			if absf(alt.x - cam_pos.x) < absf(best.x - cam_pos.x):
				best = alt

		# Frustum cull
		if absf(best.x - cam_pos.x) > half_vp.x + 100 or \
		   absf(best.y - cam_pos.y) > half_vp.y + 100:
			continue

		var armies: Dictionary = loc_armies[loc]
		var army_keys: Array = armies.keys()
		var n_armies: int = army_keys.size()

		# Lay out armies in a row centered on the province
		var total_w: float = (mini(n_armies, 6) - 1) * UNIT_SPACING * s
		var start_x: float = best.x - total_w * 0.5
		var base_y: float = best.y - SPRITE_SIZE * s

		for i: int in mini(n_armies, 6):
			var aid: String = army_keys[i]
			var army_data: Dictionary = armies[aid]
			var army_units: Array = army_data["units"]
			var owner_iso: String = army_data["owner"]
			var is_sel: bool = MilitarySystem.is_army_selected(aid)
			var is_moving: bool = army_paths.has(aid)

			var ax: float = start_x + i * UNIT_SPACING * s
			var ay: float = base_y

			# Find the dominant unit type for the main sprite
			var type_counts: Dictionary = {}
			var total_str: float = 0.0
			var total_n: int = 0
			for u: Dictionary in army_units:
				var t: String = u.get("type", "infantry")
				type_counts[t] = int(type_counts.get(t, 0)) + 1
				total_str += float(u.get("strength", 100))
				total_n += 1

			var dominant_type: String = "infantry"
			var max_count: int = 0
			for t: String in type_counts:
				if int(type_counts[t]) > max_count:
					max_count = type_counts[t]
					dominant_type = t

			var avg_str: float = total_str / maxf(total_n, 1)

			# Get owner color for tinting
			var odata: Dictionary = GameState.get_country(owner_iso)
			var omc: Array = odata.get("map_color", [80, 120, 180])
			var owner_col: Color = Color(omc[0] / 255.0, omc[1] / 255.0, omc[2] / 255.0)

			draw_set_transform(Vector2(ax, ay), 0.0, Vector2(s, s))
			_draw_unit(dominant_type, total_n, avg_str, owner_col, is_sel, is_moving)

	draw_set_transform(Vector2.ZERO)


func _draw_unit(unit_type: String, count: int, avg_strength: float,
		owner_col: Color, selected: bool, moving: bool) -> void:
	var cx: float = 0.0
	var cy: float = 0.0

	# Health ring background
	draw_arc(Vector2(cx, cy), RING_RADIUS, 0.0, TAU, 32, COL_HEALTH_BG, RING_WIDTH + 1.0)

	# Owner color ring (subtle)
	draw_arc(Vector2(cx, cy), RING_RADIUS + 2.0, 0.0, TAU, 32, owner_col.lightened(0.2), 1.5)

	# Health arc (portion filled based on strength)
	var health_pct: float = avg_strength / 100.0
	var health_col: Color
	if avg_strength > 70.0:   health_col = COL_HEALTH_OK
	elif avg_strength > 35.0: health_col = COL_HEALTH_MID
	else:                     health_col = COL_HEALTH_LOW
	if health_pct > 0.01:
		draw_arc(Vector2(cx, cy), RING_RADIUS, -PI * 0.5,
			-PI * 0.5 + TAU * health_pct, 32, health_col, RING_WIDTH)

	# Selection ring
	if selected:
		draw_arc(Vector2(cx, cy), RING_RADIUS + 4.0, 0.0, TAU, 32, COL_SEL_RING, 2.0)

	# Unit sprite
	var sprite_name: String = MilitarySystem.UNIT_TYPES.get(unit_type, {}).get("sprite", "infantry")
	var tex: Texture2D = _sprites.get(sprite_name)
	if tex != null:
		var tex_size: Vector2 = tex.get_size()
		var draw_size: float = SPRITE_SIZE * 0.8
		var scale_f: float = draw_size / maxf(tex_size.x, tex_size.y)
		var offset: Vector2 = -tex_size * scale_f * 0.5
		draw_texture_rect(tex, Rect2(offset, tex_size * scale_f), false, owner_col.lightened(0.5))
	else:
		# Fallback: draw type initial
		if _font != null:
			var initial: String = unit_type.substr(0, 1).to_upper()
			draw_string(_font, Vector2(cx, cy + 4.0), initial,
				HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)

	# Unit count badge (bottom-right)
	if count > 1 and _font != null:
		draw_string(_font, Vector2(cx + 10.0, cy + RING_RADIUS + 2.0),
			str(count), HORIZONTAL_ALIGNMENT_CENTER, 20, 8, Color.WHITE)


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
