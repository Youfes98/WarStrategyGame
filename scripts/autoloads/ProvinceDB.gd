## ProvinceDB.gd
## Autoload — map data: countries + sub-national provinces.
## When provinces.json exists, click detection and movement operate at province
## level (province_id → parent country). Otherwise falls back to country level.
extends Node

signal data_loaded()

# Country-level data loaded from countries.json
var country_map_data:   Dictionary = {}   # iso  → country dict
var adjacencies:        Dictionary = {}   # iso  → [iso, ...] (country-level borders)

# Province-level data loaded from provinces.json (optional)
var province_data:       Dictionary = {}   # pid  → province dict
var province_adjacencies: Dictionary = {}  # pid  → [pid, ...]
var sea_adjacencies:      Dictionary = {}  # coastal pid → [coastal pid, ...]
var country_provinces:   Dictionary = {}   # iso  → [pid, ...] (reverse index)

# Pixel lookup: color_key → province_id or country_iso
var color_to_iso: Dictionary = {}

var _province_image: Image = null
var _province_index_cache: Dictionary = {}   # province_id → int index

const PROVINCE_IMAGE_PATH: String  = "res://assets/map/provinces.png"
const COUNTRIES_DATA_PATH: String  = "res://data/countries.json"
const PROVINCES_DATA_PATH: String  = "res://data/provinces.json"
const ADJ_PATH: String             = "res://data/adjacencies.json"
const PROVINCE_ADJ_PATH: String    = "res://data/province_adjacencies.json"


func _ready() -> void:
	_load_data()


func _load_data() -> void:
	# ── Load countries.json ───────────────────────────────────────────────────
	if not FileAccess.file_exists(COUNTRIES_DATA_PATH):
		push_warning("ProvinceDB: countries.json not found. Run tools/fetch_country_data.py first.")
		return

	var file: FileAccess = FileAccess.open(COUNTRIES_DATA_PATH, FileAccess.READ)
	var json: JSON = JSON.new()
	var err: int = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ProvinceDB: Failed to parse countries.json")
		return

	var country_array: Array = json.get_data()
	for entry in country_array:
		var iso: String = entry.get("iso", "")
		if iso.is_empty():
			continue
		country_map_data[iso] = entry

	GameState.init_countries(country_array)

	# ── Load adjacencies.json (country-level) ─────────────────────────────────
	if FileAccess.file_exists(ADJ_PATH):
		var adj_file: FileAccess = FileAccess.open(ADJ_PATH, FileAccess.READ)
		var adj_json: JSON = JSON.new()
		if adj_json.parse(adj_file.get_as_text()) == OK:
			adjacencies = adj_json.get_data()
		adj_file.close()

	# ── Load provinces.json if present ────────────────────────────────────────
	if FileAccess.file_exists(PROVINCES_DATA_PATH):
		_load_provinces()
	else:
		# Fallback: use country map_colors for pixel detection
		for iso: String in country_map_data:
			var entry: Dictionary = country_map_data[iso]
			var color_key: String = _make_color_key(entry.get("map_color", [255, 255, 255]))
			color_to_iso[color_key] = iso

	# ── Load provinces.png ────────────────────────────────────────────────────
	if FileAccess.file_exists(PROVINCE_IMAGE_PATH):
		_province_image = Image.new()
		_province_image.load(PROVINCE_IMAGE_PATH)
	else:
		push_warning("ProvinceDB: provinces.png not found. Run tools/geojson_to_godot.py first.")

	emit_signal("data_loaded")


func _load_provinces() -> void:
	var file: FileAccess = FileAccess.open(PROVINCES_DATA_PATH, FileAccess.READ)
	var json: JSON = JSON.new()
	var err: int = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_warning("ProvinceDB: Failed to parse provinces.json — using country-level fallback.")
		return

	var parray: Array = json.get_data()
	for entry in parray:
		var pid: String    = entry.get("id", "")
		var parent: String = entry.get("parent_iso", "")
		if pid.is_empty():
			continue
		province_data[pid] = entry

		# Detect-color → province_id lookup
		var dc: Array = entry.get("detect_color", [])
		if dc.size() >= 3:
			var key: String = "%d_%d_%d" % [int(dc[0]), int(dc[1]), int(dc[2])]
			color_to_iso[key] = pid

		# Reverse index: country → [province_ids]
		if not parent.is_empty():
			if not country_provinces.has(parent):
				country_provinces[parent] = []
			(country_provinces[parent] as Array).append(pid)

	# Province-level adjacency
	if FileAccess.file_exists(PROVINCE_ADJ_PATH):
		var af: FileAccess = FileAccess.open(PROVINCE_ADJ_PATH, FileAccess.READ)
		var aj: JSON = JSON.new()
		if aj.parse(af.get_as_text()) == OK:
			province_adjacencies = aj.get_data()
		af.close()

	# Sea adjacency (coastal-to-coastal connections)
	const SEA_ADJ_PATH: String = "res://data/sea_adjacencies.json"
	if FileAccess.file_exists(SEA_ADJ_PATH):
		var sf: FileAccess = FileAccess.open(SEA_ADJ_PATH, FileAccess.READ)
		var sj: JSON = JSON.new()
		if sj.parse(sf.get_as_text()) == OK:
			sea_adjacencies = sj.get_data()
		sf.close()
		print("ProvinceDB: Loaded %d sea adjacency entries." % sea_adjacencies.size())

	GameState.init_provinces(parray)
	print("ProvinceDB: Loaded %d provinces for %d countries." % [parray.size(), country_provinces.size()])


# ── Lookups ───────────────────────────────────────────────────────────────────

func get_iso_at_map_pos(map_pos: Vector2) -> String:
	if _province_image == null:
		return ""
	var px: int = int(map_pos.x)
	var py: int = int(map_pos.y)
	if px < 0 or py < 0 or px >= _province_image.get_width() or py >= _province_image.get_height():
		return ""
	var pixel: Color = _province_image.get_pixel(px, py)
	var key: String  = _color_to_key(pixel)
	return color_to_iso.get(key, "")


## Returns the parent country ISO for a province_id, or the iso itself if it's already a country.
func get_parent_iso(id: String) -> String:
	var pdata: Dictionary = province_data.get(id, {})
	if not pdata.is_empty():
		return pdata.get("parent_iso", id)
	if country_map_data.has(id):
		return id
	return id


## Centroid for either a province_id or a country ISO.
func get_centroid(id: String) -> Vector2:
	var pdata: Dictionary = province_data.get(id, {})
	if not pdata.is_empty():
		var c: Array = pdata.get("centroid", [0.0, 0.0])
		return Vector2(c[0], c[1])
	var cdata: Dictionary = country_map_data.get(id, {})
	var c2: Array = cdata.get("centroid", [0.0, 0.0])
	return Vector2(c2[0], c2[1])


## Polygon points for either a province_id or a country ISO.
func get_polygon_points(id: String) -> PackedVector2Array:
	var raw: Array = []
	var pdata: Dictionary = province_data.get(id, {})
	if not pdata.is_empty():
		raw = pdata.get("polygon", [])
	else:
		raw = country_map_data.get(id, {}).get("polygon", [])
	var points: PackedVector2Array = PackedVector2Array()
	for pt in raw:
		points.append(Vector2(pt[0], pt[1]))
	return points


## Display color for a province (inherits parent country's map_color) or country.
func get_display_color(id: String) -> Color:
	var parent: String = get_parent_iso(id)
	var cdata: Dictionary = country_map_data.get(parent, {})
	var c: Array = cdata.get("map_color", [200, 200, 200])
	return Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)


## Alias kept for backward compatibility.
func get_map_color(iso: String) -> Color:
	return get_display_color(iso)


## Neighbors at the most granular available level.
func get_neighbors(id: String) -> Array:
	if province_adjacencies.has(id):
		return province_adjacencies.get(id, [])
	return adjacencies.get(id, [])


## All province IDs belonging to a country (empty if no provinces loaded).
func get_country_province_ids(country_iso: String) -> Array:
	return country_provinces.get(country_iso, [])


## Returns the capital/main province ID for a country (largest province).
## Falls back to country ISO if no provinces loaded.
func get_main_province(country_iso: String) -> String:
	var pids: Array = country_provinces.get(country_iso, [])
	if pids.is_empty():
		return country_iso
	return pids[0]   # first = largest (sorted by area in pipeline)


## Whether provinces data has been loaded.
func has_provinces() -> bool:
	return not province_data.is_empty()


## Returns all territory IDs that should be rendered on the map.
## If provinces are loaded, returns province_ids; otherwise country ISOs.
func get_render_ids() -> Array:
	if has_provinces():
		return province_data.keys()
	return country_map_data.keys()


## Province index from detect_color (used for shader LUT).
func get_province_index(id: String) -> int:
	if _province_index_cache.has(id):
		return _province_index_cache[id]
	var pdata: Dictionary = province_data.get(id, {})
	if pdata.is_empty():
		return 0
	var dc: Array = pdata.get("detect_color", [])
	if dc.size() < 3:
		return 0
	var idx: int = int(dc[0]) * 65536 + int(dc[1]) * 256 + int(dc[2])
	_province_index_cache[id] = idx
	return idx


func get_province_image() -> Image:
	return _province_image


func _make_color_key(rgb: Array) -> String:
	return "%d_%d_%d" % [rgb[0], rgb[1], rgb[2]]


func _color_to_key(color: Color) -> String:
	return "%d_%d_%d" % [roundi(color.r * 255), roundi(color.g * 255), roundi(color.b * 255)]


## Get neighbors for a specific unit domain.
func get_neighbors_for_domain(id: String, domain: String) -> Array:
	match domain:
		"sea":
			# Naval: use sea adjacencies (coastal-to-coastal)
			# Also include land neighbors that are coastal (for docking)
			var sea_nb: Array = sea_adjacencies.get(id, [])
			# Add coastal land neighbors too (so ships can move along coast)
			for nb: String in province_adjacencies.get(id, []):
				if is_coastal(nb) and nb not in sea_nb:
					sea_nb.append(nb)
			return sea_nb
		"air":
			# Air doesn't pathfind — uses range-based projection
			return []
		_:
			# Land: normal adjacency only
			return get_neighbors(id)


## Terrain type for a province (baked into provinces.json by pipeline).
func get_province_terrain(pid: String) -> String:
	return province_data.get(pid, {}).get("terrain", "plains")


## Whether a province is coastal (has "coastal" flag baked by pipeline).
func is_coastal(pid: String) -> bool:
	return province_data.get(pid, {}).get("coastal", false)


## Find the nearest coastal province owned by a country.
func get_nearest_coast(country_iso: String) -> String:
	var pids: Array = country_provinces.get(country_iso, [])
	for pid: String in pids:
		if is_coastal(pid):
			return pid
	return ""


## Get the capital province for a country (closest province to actual capital city).
func get_capital_province(country_iso: String) -> String:
	var cdata: Dictionary = country_map_data.get(country_iso, {})
	# Use capital_centroid (actual capital city coords) if available, fall back to centroid
	var cap_centroid: Array = cdata.get("capital_centroid", cdata.get("centroid", []))
	if cap_centroid.size() < 2:
		return get_main_province(country_iso)
	var cap_pos: Vector2 = Vector2(cap_centroid[0], cap_centroid[1])
	var pids: Array = country_provinces.get(country_iso, [])
	if pids.is_empty():
		return country_iso
	var best_pid: String = pids[0]
	var best_dist: float = INF
	for pid: String in pids:
		var pc: Array = province_data[pid].get("centroid", [0, 0])
		var dist: float = cap_pos.distance_squared_to(Vector2(pc[0], pc[1]))
		if dist < best_dist:
			best_dist = dist
			best_pid = pid
	return best_pid
