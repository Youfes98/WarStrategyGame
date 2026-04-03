## MapRenderer.gd
## GPU-shader-based layered map rendering.
## Layers: terrain base → country colour overlay → elevation shading →
##         coast glow → noise variation → province/country borders.
## Three Sprite2D tiles for seamless horizontal wrapping (endless map).
extends Node2D

signal country_clicked(iso: String)

const MAP_WIDTH:  float = 8192.0
const MAP_HEIGHT: float = 4096.0
const ZOOM_MIN:   float = 0.15
const ZOOM_MAX:   float = 8.0
const ZOOM_STEP:  float = 0.15
const LUT_SIZE:   int   = 8192

const COLOR_SELECTED: Color = Color(1.0, 0.85, 0.2, 1.0)
const COLOR_PLAYER:   Color = Color(0.3, 0.8, 0.4, 1.0)
const COLOR_ENEMY:    Color = Color(0.75, 0.18, 0.18, 1.0)
const COLOR_OCEAN:    Color = Color(0.12, 0.25, 0.45, 1.0)
const COLOR_MIL_SEL:  Color = Color(0.3, 0.7, 1.0, 1.0)

# Full layered map shader — embedded to avoid file-loading issues.
# If this fails, a minimal fallback shader is used instead.
const SHADER_CODE: String = ""

# Shader state
var _shader_mode:       bool = false
var _map_sprites:       Array = []
var _shader_material:   ShaderMaterial = null
var _color_lut_image:   Image = null
var _color_lut_tex:     ImageTexture = null
var _country_lut_image: Image = null
var _country_lut_tex:   ImageTexture = null
var _base_colors:       Dictionary = {}
var _lut_dirty:         bool = false

# Polygon fallback
var _polygons: Dictionary = {}

var _selected_country: String = ""
var _hover_id:         String = ""
var _mil_sel_iso:      String = ""

var _dragging:    bool    = false
var _drag_origin: Vector2 = Vector2.ZERO
var _cam_origin:  Vector2 = Vector2.ZERO
var _last_hover_pos: Vector2 = Vector2(-9999, -9999)


func _ready() -> void:
	ProvinceDB.data_loaded.connect(_on_data_loaded)
	GameState.country_selected.connect(_on_country_selected)
	GameState.country_deselected.connect(_on_country_deselected)
	GameState.player_country_set.connect(_on_player_set)
	MilitarySystem.territory_selected.connect(_on_mil_territory_selected)
	MilitarySystem.battle_resolved.connect(_on_battle_resolved)
	GameState.war_state_changed.connect(_on_war_state_changed)
	if not ProvinceDB.country_map_data.is_empty():
		_build_map()

func _on_data_loaded() -> void:
	_build_map()

func _build_map() -> void:
	var prov_img: Image = ProvinceDB.get_province_image()
	if prov_img != null and ProvinceDB.has_provinces():
		_build_shader_map(prov_img)
	else:
		_build_polygon_map()


# ── Shader map with all terrain layers ────────────────────────────────────────

func _build_shader_map(prov_img: Image) -> void:
	_shader_mode = true
	var prov_tex: ImageTexture = ImageTexture.create_from_image(prov_img)

	# Build colour LUT
	_color_lut_image   = Image.create(LUT_SIZE, 1, false, Image.FORMAT_RGBA8)
	_color_lut_image.fill(COLOR_OCEAN)
	_country_lut_image = Image.create(LUT_SIZE, 1, false, Image.FORMAT_RGBA8)
	_country_lut_image.fill(Color.BLACK)

	var country_idx_map: Dictionary = {}
	var next_ci: int = 1
	var filled: int = 0
	for pid: String in ProvinceDB.province_data:
		var idx: int = ProvinceDB.get_province_index(pid)
		if idx <= 0 or idx >= LUT_SIZE:
			continue
		var parent: String = ProvinceDB.get_parent_iso(pid)
		if not country_idx_map.has(parent):
			country_idx_map[parent] = next_ci
			next_ci += 1
		_country_lut_image.set_pixel(idx, 0, Color(float(country_idx_map[parent]) / 255.0, 0.0, 0.0))
		var col: Color = ProvinceDB.get_display_color(pid)
		_color_lut_image.set_pixel(idx, 0, col)
		_base_colors[idx] = col
		filled += 1

	_color_lut_tex   = ImageTexture.create_from_image(_color_lut_image)
	_country_lut_tex = ImageTexture.create_from_image(_country_lut_image)

	# Load shader from .gdshader file
	var shader: Shader = load("res://assets/shaders/map.gdshader") as Shader
	if shader == null:
		push_error("MapRenderer: failed to load map.gdshader!")
		_build_polygon_map()
		return
	print("  Shader loaded OK")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	_shader_material.set_shader_parameter("province_tex", prov_tex)
	_shader_material.set_shader_parameter("color_lut", _color_lut_tex)
	_shader_material.set_shader_parameter("country_lut", _country_lut_tex)
	_shader_material.set_shader_parameter("lut_size", float(LUT_SIZE))
	_shader_material.set_shader_parameter("tex_pixel_size", Vector2(1.0 / float(prov_img.get_width()), 1.0 / float(prov_img.get_height())))

	# Debug: verify LUT has real colours
	var sample_idx: int = 1
	var sample_col: Color = _color_lut_image.get_pixel(sample_idx, 0)
	print("  LUT[1] = ", sample_col, "  (should NOT be ocean blue)")
	print("  provinces.png size = ", prov_img.get_width(), "x", prov_img.get_height())
	# Verify detect colour at a known land pixel
	var test_px: Color = prov_img.get_pixel(int(prov_img.get_width() / 2.0), int(prov_img.get_height() / 2.0))
	print("  Centre pixel detect = R:", roundi(test_px.r * 255), " G:", roundi(test_px.g * 255), " B:", roundi(test_px.b * 255))

	# Load optional terrain layers
	_load_terrain_layers()

	# 3 tiles for endless wrap
	for i: int in 3:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture  = prov_tex
		sprite.material = _shader_material
		sprite.centered = false
		sprite.position = Vector2((i - 1) * MAP_WIDTH, 0.0)
		sprite.z_index  = -5
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		_map_sprites.append(sprite)

	print("MapRenderer: %d provinces, %d countries, shader mode" % [filled, next_ci - 1])


func _load_terrain_layers() -> void:
	# Terrain base
	if FileAccess.file_exists("res://assets/map/terrain.png"):
		var img: Image = (load("res://assets/map/terrain.png") as Texture2D).get_image()
		var tex: ImageTexture = ImageTexture.create_from_image(img)
		_shader_material.set_shader_parameter("terrain_tex", tex)
		_shader_material.set_shader_parameter("has_terrain", true)
		print("  Terrain layer loaded")

	# Heightmap
	if FileAccess.file_exists("res://assets/map/heightmap.png"):
		var img: Image = (load("res://assets/map/heightmap.png") as Texture2D).get_image()
		var tex: ImageTexture = ImageTexture.create_from_image(img)
		_shader_material.set_shader_parameter("heightmap_tex", tex)
		_shader_material.set_shader_parameter("has_heightmap", true)
		print("  Heightmap layer loaded")

	# Noise
	if FileAccess.file_exists("res://assets/map/noise.png"):
		var img: Image = (load("res://assets/map/noise.png") as Texture2D).get_image()
		var tex: ImageTexture = ImageTexture.create_from_image(img)
		_shader_material.set_shader_parameter("noise_tex", tex)
		_shader_material.set_shader_parameter("has_noise", true)
		print("  Noise layer loaded")


# ── LUT helpers ───────────────────────────────────────────────────────────────

func _set_lut(idx: int, col: Color) -> void:
	if idx > 0 and idx < LUT_SIZE:
		_color_lut_image.set_pixel(idx, 0, col)
		_lut_dirty = true

func _flush_lut() -> void:
	if _lut_dirty:
		_color_lut_tex.update(_color_lut_image)
		_lut_dirty = false

func _set_province_lut(pid: String, col: Color) -> void:
	_set_lut(ProvinceDB.get_province_index(pid), col)

func _set_country_lut(ciso: String, col: Color) -> void:
	for pid: String in ProvinceDB.get_country_province_ids(ciso):
		_set_province_lut(pid, col)

func _restore_province_lut(pid: String) -> void:
	var idx: int = ProvinceDB.get_province_index(pid)
	_set_lut(idx, _base_colors.get(idx, COLOR_OCEAN))

func _restore_country_lut(ciso: String) -> void:
	for pid: String in ProvinceDB.get_country_province_ids(ciso):
		_restore_province_lut(pid)


# ── Polygon fallback ─────────────────────────────────────────────────────────

func _build_polygon_map() -> void:
	_shader_mode = false
	var ocean: ColorRect = ColorRect.new()
	ocean.color = COLOR_OCEAN
	ocean.size  = Vector2(MAP_WIDTH * 3.0, MAP_HEIGHT)
	ocean.position = Vector2(-MAP_WIDTH, 0.0)
	ocean.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ocean.z_index = -10
	add_child(ocean)
	for iso: String in ProvinceDB.country_map_data:
		var pts: PackedVector2Array = ProvinceDB.get_polygon_points(iso)
		if pts.is_empty():
			continue
		var poly: Polygon2D = Polygon2D.new()
		poly.polygon = pts
		poly.color   = ProvinceDB.get_map_color(iso)
		poly.z_index = 0
		add_child(poly)
		_polygons[iso] = poly


# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = mb.pressed
				if _dragging:
					var cam := get_viewport().get_camera_2d()
					_drag_origin = mb.position
					_cam_origin  = cam.position if cam else Vector2.ZERO
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(mb.position, 1)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(mb.position, -1)
					get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			var cam := get_viewport().get_camera_2d()
			if cam:
				cam.position = _cam_origin - (mm.position - _drag_origin) / cam.zoom
			get_viewport().set_input_as_handled()
		else:
			if mm.position.distance_squared_to(_last_hover_pos) > 16.0:
				_last_hover_pos = mm.position
				_handle_hover(mm.position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			if not MilitarySystem.selected_iso.is_empty():
				MilitarySystem.deselect()
			else:
				GameState.deselect()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not _dragging:
			_handle_click(mb.position)

func _handle_click(vp: Vector2) -> void:
	var mp: Vector2 = _wrap_x(_to_map(vp))
	var rid: String = ProvinceDB.get_iso_at_map_pos(mp)
	if rid.is_empty() and not _shader_mode:
		rid = _hit_test(mp)
	if rid.is_empty():
		if not MilitarySystem.selected_iso.is_empty():
			MilitarySystem.deselect()
		else:
			GameState.deselect()
		return
	if not GameState.player_iso.is_empty():
		if MilitarySystem.handle_territory_click(rid):
			return
	var ciso: String = ProvinceDB.get_parent_iso(rid)
	emit_signal("country_clicked", ciso)
	GameState.select_country(ciso)

func _hit_test(mp: Vector2) -> String:
	for iso: String in _polygons:
		if Geometry2D.is_point_in_polygon(mp, (_polygons[iso] as Polygon2D).polygon):
			return iso
	return ""

func _handle_hover(vp: Vector2) -> void:
	var mp: Vector2 = _wrap_x(_to_map(vp))
	var rid: String = ProvinceDB.get_iso_at_map_pos(mp)
	if rid.is_empty() and not _shader_mode:
		rid = _hit_test(mp)
	if rid != _hover_id:
		_set_hover(rid)

func _to_map(vp: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * vp

func _wrap_x(mp: Vector2) -> Vector2:
	var x: float = fmod(mp.x, MAP_WIDTH)
	if x < 0.0:
		x += MAP_WIDTH
	return Vector2(x, mp.y)

func _zoom(vp: Vector2, dir: int) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var oz: float = cam.zoom.x
	var nz: float = clampf(oz + dir * ZOOM_STEP * oz, ZOOM_MIN, ZOOM_MAX)
	if nz == oz:
		return
	var before: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * vp
	cam.zoom = Vector2(nz, nz)
	var after: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * vp
	cam.position += before - after


# ── Colour events ─────────────────────────────────────────────────────────────

func _on_country_selected(ciso: String) -> void:
	_clear_selected()
	_selected_country = ciso
	if _shader_mode:
		_set_country_lut(ciso, COLOR_SELECTED)
		_flush_lut()
	elif _polygons.has(ciso):
		(_polygons[ciso] as Polygon2D).color = COLOR_SELECTED

func _on_country_deselected() -> void:
	_clear_selected()

func _on_player_set(ciso: String) -> void:
	_update_base(ciso)

func _clear_selected() -> void:
	var prev: String = _selected_country
	_selected_country = ""
	if not prev.is_empty():
		if _shader_mode:
			_restore_country_lut(prev)
			_flush_lut()
		elif _polygons.has(prev):
			(_polygons[prev] as Polygon2D).color = ProvinceDB.get_map_color(prev)

func _set_hover(id: String) -> void:
	if _shader_mode:
		if not _hover_id.is_empty() and _hover_id != _mil_sel_iso:
			if ProvinceDB.get_parent_iso(_hover_id) == _selected_country:
				_set_province_lut(_hover_id, COLOR_SELECTED)
			else:
				_restore_province_lut(_hover_id)
		_hover_id = id
		if not id.is_empty() and id != _mil_sel_iso:
			if ProvinceDB.get_parent_iso(id) != _selected_country:
				var idx: int = ProvinceDB.get_province_index(id)
				_set_lut(idx, _base_colors.get(idx, COLOR_OCEAN).lightened(0.18))
		_flush_lut()
	else:
		if not _hover_id.is_empty() and _polygons.has(_hover_id):
			(_polygons[_hover_id] as Polygon2D).color = ProvinceDB.get_map_color(_hover_id)
		_hover_id = id
		if not id.is_empty() and _polygons.has(id):
			(_polygons[id] as Polygon2D).color = ProvinceDB.get_map_color(id).lightened(0.18)

func _on_battle_resolved(tid: String, _a: String, _d: String, _w: bool) -> void:
	refresh_country_color(tid)

func _on_war_state_changed(a: String, b: String, _w: bool) -> void:
	_update_base(a)
	_update_base(b)

func _on_mil_territory_selected(id: String) -> void:
	var prev: String = _mil_sel_iso
	_mil_sel_iso = id
	if not prev.is_empty():
		refresh_country_color(prev)
	if not id.is_empty():
		if _shader_mode:
			_set_province_lut(id, COLOR_MIL_SEL)
			_flush_lut()
		elif _polygons.has(id):
			(_polygons[id] as Polygon2D).color = COLOR_MIL_SEL

func refresh_country_color(id: String) -> void:
	if _shader_mode:
		var idx: int = ProvinceDB.get_province_index(id)
		if idx <= 0:
			return
		var col: Color = _compute_color(id)
		_base_colors[idx] = col
		_set_lut(idx, col)
		_flush_lut()
	elif _polygons.has(id):
		(_polygons[id] as Polygon2D).color = _compute_color(id)

func _update_base(ciso: String) -> void:
	if _shader_mode:
		for pid: String in ProvinceDB.get_country_province_ids(ciso):
			var idx: int = ProvinceDB.get_province_index(pid)
			if idx <= 0:
				continue
			var col: Color = _compute_color(pid)
			_base_colors[idx] = col
			_set_lut(idx, col)
		_flush_lut()

func _compute_color(id: String) -> Color:
	var parent: String = ProvinceDB.get_parent_iso(id)
	var ter_owner: String  = GameState.territory_owner.get(id, parent)
	if parent == _selected_country:
		return COLOR_SELECTED
	if id == _mil_sel_iso:
		return COLOR_MIL_SEL
	if ter_owner == GameState.player_iso:
		return COLOR_PLAYER
	if not GameState.player_iso.is_empty() and GameState.is_at_war(GameState.player_iso, ter_owner):
		return COLOR_ENEMY
	return ProvinceDB.get_display_color(id)
