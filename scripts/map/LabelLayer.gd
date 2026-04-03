## LabelLayer.gd
## Zoom-responsive country labels with overlap rejection.
## Labels scale with zoom, hide when too small, prioritize large countries.
extends Node2D

const MAP_WIDTH:     float = 8192.0
const TEXT_COLOR:    Color = Color(1.0, 1.0, 1.0, 0.88)
const SHADOW_COLOR:  Color = Color(0.0, 0.0, 0.0, 0.60)
const PLAYER_COLOR:  Color = Color(0.55, 1.0, 0.65, 1.0)

var _font: Font = null
var _last_zoom: float = -1.0


func _ready() -> void:
	z_index = 5
	_font = ThemeDB.fallback_font
	ProvinceDB.data_loaded.connect(queue_redraw)
	MilitarySystem.battle_resolved.connect(
		func(_t: String, _a: String, _d: String, _w: bool) -> void: queue_redraw())


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var z: float = cam.zoom.x
	# Only redraw if zoom changed noticeably or camera moved
	if absf(z - _last_zoom) > 0.01:
		_last_zoom = z
		queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var zoom: float = cam.zoom.x
	var player_iso: String = GameState.player_iso

	# Font size: small when zoomed out, large when zoomed in
	# At zoom 0.5 → size 7, zoom 1.0 → size 11, zoom 2.0 → size 14, zoom 4.0 → size 18
	var base_size: int = clampi(int(8.0 + 6.0 * log(zoom + 0.5) / log(2.0)), 6, 20)

	# ── Build label entries sorted by polygon area ────────────────────────────
	var entries: Array = []
	var player_centroids: Array = []

	for iso: String in ProvinceDB.country_map_data:
		var data: Dictionary = ProvinceDB.country_map_data[iso]
		var centroid: Vector2 = ProvinceDB.get_centroid(iso)
		if centroid == Vector2.ZERO:
			continue

		var poly: Array = data.get("polygon", [])
		var area: float = _poly_area(poly)
		# Use real area_km2 as fallback for tiny polygon countries
		var area_km2: float = float(data.get("area_km2", 0))
		if area < 100.0 and area_km2 > 0.0:
			area = maxf(area, area_km2 * 0.05)

		# Check player ownership
		if not player_iso.is_empty():
			var is_player: bool
			if ProvinceDB.has_provinces():
				is_player = GameState.get_country_owner(iso) == player_iso
			else:
				is_player = GameState.territory_owner.get(iso, iso) == player_iso
			if is_player:
				player_centroids.append(centroid)
				continue

		var cname: String = data.get("name", iso)
		entries.append({"iso": iso, "name": cname, "pos": centroid, "area": area})

	# Sort largest first — they get label priority
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.area > b.area)

	# ── Draw labels with overlap rejection ────────────────────────────────────
	var used_rects: Array = []

	for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
		for e: Dictionary in entries:
			var area: float = e.area
			# Skip if country is too small at this zoom to show a label
			var screen_area: float = area * zoom * zoom
			if screen_area < 80.0:
				continue

			var cname: String = e.name
			var fsize: int = base_size
			if screen_area < 600.0:
				fsize = maxi(5, base_size - 3)
				if cname.length() > 5:
					cname = e.iso
			elif screen_area < 2000.0:
				fsize = maxi(6, base_size - 2)
				if cname.length() > 8:
					cname = e.iso

			var pos: Vector2 = e.pos + Vector2(x_off, 0.0)
			var sz: Vector2  = _font.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)

			var rect: Rect2 = Rect2(pos.x - sz.x * 0.5, pos.y - sz.y * 0.5, sz.x, sz.y)

			# Overlap check
			var blocked: bool = false
			for r: Rect2 in used_rects:
				if rect.grow(3.0).intersects(r):
					blocked = true
					break
			if blocked:
				continue

			used_rects.append(rect)
			_label(pos, cname, TEXT_COLOR, fsize)

	# ── Player empire label ───────────────────────────────────────────────────
	if player_centroids.size() > 0:
		var avg: Vector2 = Vector2.ZERO
		for c: Vector2 in player_centroids:
			avg += c
		avg /= float(player_centroids.size())
		var pname: String = GameState.get_country(player_iso).get("name", player_iso)
		var pfsize: int = clampi(base_size + 3, 8, 22)
		for x_off: float in [-MAP_WIDTH, 0.0, MAP_WIDTH]:
			_label(avg + Vector2(x_off, 0.0), pname, PLAYER_COLOR, pfsize)


func _label(center: Vector2, text: String, col: Color, fsize: int) -> void:
	var sz: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var origin: Vector2 = center - Vector2(sz.x * 0.5, -sz.y * 0.35)
	draw_string(_font, origin + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, SHADOW_COLOR)
	draw_string(_font, origin, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _poly_area(poly: Array) -> float:
	var n: int = poly.size()
	if n < 3:
		return 0.0
	var area: float = 0.0
	var step: int = maxi(1, int(n / 30.0))
	for i: int in range(0, n, step):
		var j: int = (i + step) % n
		area += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1]
	return absf(area) * 0.5
