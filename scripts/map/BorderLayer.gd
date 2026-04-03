## BorderLayer.gd
## Vector-based border rendering on top of the shader map.
## Province borders: thin, subtle. Country borders: thick, dark.
## Drawn from polygon data so they stay smooth at any zoom level.
## Shader still handles fills/terrain — this only draws edges.
extends Node2D

const MAP_WIDTH: float = 16384.0

const COUNTRY_COLOR:  Color = Color(0.02, 0.02, 0.04, 0.55)
const PROVINCE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.12)
const COUNTRY_WIDTH:  float = 2.0
const PROVINCE_WIDTH: float = 0.8

var _country_borders: Array = []   # [{points: PackedVector2Array, closed: bool}]
var _province_borders: Array = []
var _built: bool = false


func _ready() -> void:
	z_index = 3
	ProvinceDB.data_loaded.connect(_build_borders)
	if not ProvinceDB.country_map_data.is_empty():
		_build_borders()


func _build_borders() -> void:
	_country_borders.clear()
	_province_borders.clear()

	if not ProvinceDB.has_provinces():
		# Fallback: country-level borders only
		for iso: String in ProvinceDB.country_map_data:
			var pts: PackedVector2Array = ProvinceDB.get_polygon_points(iso)
			if pts.size() >= 3:
				var closed: PackedVector2Array = PackedVector2Array(pts)
				closed.append(pts[0])
				_country_borders.append(closed)
	else:
		# Province-level: classify each border as province or country
		for pid: String in ProvinceDB.province_data:
			var pts: PackedVector2Array = ProvinceDB.get_polygon_points(pid)
			if pts.size() < 3:
				continue
			var closed: PackedVector2Array = PackedVector2Array(pts)
			closed.append(pts[0])
			_province_borders.append(closed)

		# Country outlines from admin-0 polygon data
		for iso: String in ProvinceDB.country_map_data:
			var data: Dictionary = ProvinceDB.country_map_data[iso]
			var raw: Array = data.get("polygon", [])
			if raw.size() < 3:
				continue
			var pts: PackedVector2Array = PackedVector2Array()
			for pt in raw:
				pts.append(Vector2(pt[0], pt[1]))
			pts.append(Vector2(raw[0][0], raw[0][1]))
			_country_borders.append(pts)

	_built = true
	print("BorderLayer: %d province borders, %d country borders" % [_province_borders.size(), _country_borders.size()])
	queue_redraw()


func _draw() -> void:
	if not _built:
		return

	for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
		draw_set_transform(Vector2(x_off, 0.0))

		# Province borders first (thin, subtle)
		for border: PackedVector2Array in _province_borders:
			draw_polyline(border, PROVINCE_COLOR, PROVINCE_WIDTH, true)

		# Country borders on top (thick, dark, antialiased)
		for border: PackedVector2Array in _country_borders:
			draw_polyline(border, COUNTRY_COLOR, COUNTRY_WIDTH, true)

	draw_set_transform(Vector2.ZERO)
