## BorderLayer.gd
## Draws vector borders from province polygon data — smooth at any zoom.
## Country borders: thick, dark. Province borders: thin, subtle.
## Shader handles fills/terrain. This layer handles borders only.
extends Node2D

const MAP_WIDTH:  float = 16384.0
const MAP_HEIGHT: float = 8192.0

const COUNTRY_COLOR:  Color = Color(0.02, 0.02, 0.04, 0.70)
const COUNTRY_WIDTH:  float = 2.5
const PROVINCE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.22)
const PROVINCE_WIDTH: float = 1.0
const CULL_MARGIN: float = 200.0

var _country_borders: Array = []
var _province_borders: Array = []
var _built: bool = false
var _last_zoom: float = -1.0
var _last_cam_pos: Vector2 = Vector2(-99999, -99999)


func _ready() -> void:
	z_index = 1
	ProvinceDB.data_loaded.connect(_build_borders)
	GameState.war_state_changed.connect(func(_a: String, _b: String, _w: bool) -> void: queue_redraw())
	MilitarySystem.battle_resolved.connect(
		func(_t: String, _a: String, _d: String, _w: bool) -> void: _rebuild_country_set(); queue_redraw())
	if not ProvinceDB.country_map_data.is_empty():
		_build_borders()


func _build_borders() -> void:
	if not ProvinceDB.has_provinces():
		_built = false
		return

	_country_borders.clear()
	_province_borders.clear()

	for pid: String in ProvinceDB.province_data:
		var pdata: Dictionary = ProvinceDB.province_data[pid]
		var parent: String = pdata.get("parent_iso", "")
		var polygon: Array = pdata.get("polygon", [])
		if polygon.size() < 3:
			continue

		var points: PackedVector2Array = PackedVector2Array()
		for pt in polygon:
			points.append(Vector2(pt[0], pt[1]))
		points.append(Vector2(polygon[0][0], polygon[0][1]))

		var neighbors: Array = ProvinceDB.province_adjacencies.get(pid, [])
		var has_foreign_neighbor: bool = false
		for nb_id: String in neighbors:
			var nb_data: Dictionary = ProvinceDB.province_data.get(nb_id, {})
			var nb_parent: String = nb_data.get("parent_iso", "")
			if nb_parent != parent and not nb_parent.is_empty():
				has_foreign_neighbor = true
				break

		var centroid_arr: Array = pdata.get("centroid", [0.0, 0.0])
		var centroid: Vector2 = Vector2(centroid_arr[0], centroid_arr[1])

		if has_foreign_neighbor:
			_country_borders.append({"points": points, "centroid": centroid})

		_province_borders.append({"points": points, "centroid": centroid})

	_built = true
	print("BorderLayer: %d country, %d province borders" % [_country_borders.size(), _province_borders.size()])
	queue_redraw()


func _rebuild_country_set() -> void:
	_build_borders()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var z: float = cam.zoom.x
	var pos: Vector2 = cam.position
	if absf(z - _last_zoom) > 0.005 or pos.distance_squared_to(_last_cam_pos) > 100.0:
		_last_zoom = z
		_last_cam_pos = pos
		queue_redraw()


func _draw() -> void:
	if not _built:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var zoom: float = cam.zoom.x
	var vp_size: Vector2 = get_viewport_rect().size / zoom
	var cam_pos: Vector2 = cam.position
	var view_rect: Rect2 = Rect2(
		cam_pos - vp_size * 0.5 - Vector2(CULL_MARGIN, CULL_MARGIN),
		vp_size + Vector2(CULL_MARGIN * 2, CULL_MARGIN * 2))

	# Skip all borders at world view
	if zoom < 0.3:
		return

	var country_w: float = COUNTRY_WIDTH / maxf(zoom, 0.2)
	var province_w: float = PROVINCE_WIDTH / maxf(zoom, 0.2)
	if zoom > 4.0:
		country_w = maxf(country_w, 0.8)
		province_w = maxf(province_w, 0.3)

	var draw_province: bool = zoom > 1.5

	for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
		var offset: Vector2 = Vector2(x_off, 0.0)

		if draw_province:
			for border: Dictionary in _province_borders:
				var c: Vector2 = (border["centroid"] as Vector2) + offset
				if not view_rect.has_point(c):
					continue
				_draw_offset_polyline(border["points"] as PackedVector2Array, offset, PROVINCE_COLOR, province_w)

		for border: Dictionary in _country_borders:
			var c: Vector2 = (border["centroid"] as Vector2) + offset
			if not view_rect.has_point(c):
				continue
			_draw_offset_polyline(border["points"] as PackedVector2Array, offset, COUNTRY_COLOR, country_w)


func _draw_offset_polyline(points: PackedVector2Array, offset: Vector2,
		col: Color, width: float) -> void:
	if offset == Vector2.ZERO:
		draw_polyline(points, col, width, true)
	else:
		var shifted: PackedVector2Array = PackedVector2Array()
		shifted.resize(points.size())
		for i: int in points.size():
			shifted[i] = points[i] + offset
		draw_polyline(shifted, col, width, true)
