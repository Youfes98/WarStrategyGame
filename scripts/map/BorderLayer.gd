## BorderLayer.gd
## Draws country border lines in polygon fallback mode only.
## When provinces are loaded, borders are rendered by the map shader instead.
extends Node2D

const MAP_WIDTH: float = 16384.0
const BORDER_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const BORDER_WIDTH: float = 1.2


func _ready() -> void:
	z_index = 1
	ProvinceDB.data_loaded.connect(queue_redraw)
	if not ProvinceDB.country_map_data.is_empty():
		queue_redraw()


func _draw() -> void:
	if ProvinceDB.has_provinces():
		return   # Borders handled by map.gdshader
	for iso: String in ProvinceDB.country_map_data:
		var points: PackedVector2Array = ProvinceDB.get_polygon_points(iso)
		if points.size() < 3:
			continue
		var closed: PackedVector2Array = PackedVector2Array(points)
		closed.append(points[0])
		draw_polyline(closed, BORDER_COLOR, BORDER_WIDTH, true)
