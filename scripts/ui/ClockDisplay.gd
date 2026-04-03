## ClockDisplay.gd
## Top-right HUD: circular clock face with speed/pause buttons in a U-arc below it.
## All children created programmatically — no child nodes needed in the scene.
extends Control

const CLOCK_R:  float   = 36.0
const CLOCK_C:  Vector2 = Vector2(75.0, 46.0)
const ARC_R:    float   = 54.0
const BTN_SIZE: Vector2 = Vector2(28, 20)

const COL_FACE:   Color = Color(0.07, 0.11, 0.20, 0.93)
const COL_RIM:    Color = Color(0.28, 0.44, 0.72, 1.0)
const COL_RIM2:   Color = Color(0.14, 0.24, 0.48, 1.0)
const COL_TICK:   Color = Color(0.50, 0.66, 0.92, 0.70)
const COL_TICK_H: Color = Color(0.78, 0.88, 1.0,  1.0)
const COL_HAND:   Color = Color(0.94, 0.94, 1.0,  1.0)
const COL_DOT:    Color = Color(1.0,  0.84, 0.28, 1.0)

# Ordered left→right around the U arc: [label, speed_index (0 = pause)]
const BTN_DEFS: Array[Dictionary] = [
	{"label": "1x", "speed": 1},
	{"label": "2x", "speed": 2},
	{"label": "⏸",  "speed": 0},
	{"label": "3x", "speed": 3},
	{"label": "4x", "speed": 4},
	{"label": "5x", "speed": 5},
]

var _speed_btns: Array[Button] = []
var _pause_btn:  Button        = null
var _time_lbl:   Label         = null
var _date_lbl:   Label         = null


func _ready() -> void:
	custom_minimum_size = Vector2(150, 118)
	mouse_filter = MOUSE_FILTER_IGNORE  # don't block map clicks on empty areas

	_make_labels()
	_make_buttons()

	GameClock.tick_hour.connect(_on_tick)
	GameClock.pause_changed.connect(_on_changed)
	GameClock.speed_changed.connect(_on_changed)
	_refresh()
	queue_redraw()


func _make_labels() -> void:
	_time_lbl = Label.new()
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_lbl.position = Vector2(CLOCK_C.x - 34, CLOCK_C.y - 12)
	_time_lbl.size     = Vector2(68, 18)
	_time_lbl.add_theme_font_size_override("font_size", 14)
	_time_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_time_lbl)

	_date_lbl = Label.new()
	_date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_lbl.position = Vector2(CLOCK_C.x - 38, CLOCK_C.y + 6)
	_date_lbl.size     = Vector2(76, 13)
	_date_lbl.add_theme_font_size_override("font_size", 9)
	_date_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_date_lbl)


func _make_buttons() -> void:
	var count:       int   = BTN_DEFS.size()
	# In Godot's Y-down space, 90° = downward. Arc from 150°→30° curves through the
	# bottom (90°), forming a natural U-shape below the clock face.
	var angle_start: float = deg_to_rad(150.0)
	var angle_end:   float = deg_to_rad(30.0)

	for i in count:
		var t:     float   = float(i) / float(count - 1)
		var angle: float   = lerp(angle_start, angle_end, t)
		var center: Vector2 = CLOCK_C + Vector2(cos(angle), sin(angle)) * ARC_R

		var btn := Button.new()
		btn.text               = BTN_DEFS[i]["label"]
		btn.custom_minimum_size = BTN_SIZE
		btn.size               = BTN_SIZE
		btn.position           = center - BTN_SIZE * 0.5
		add_child(btn)

		var spd: int = BTN_DEFS[i]["speed"]
		if spd == 0:
			_pause_btn = btn
			btn.pressed.connect(GameClock.toggle_pause)
		else:
			btn.toggle_mode = true
			_speed_btns.append(btn)
			btn.pressed.connect(func() -> void: GameClock.set_speed(spd))


func _on_tick(_d: Dictionary) -> void:
	_refresh()
	queue_redraw()


func _on_changed(_v: Variant) -> void:
	_refresh()


func _refresh() -> void:
	if _time_lbl == null:
		return
	_time_lbl.text = "%02d:00" % GameClock.date.hour
	_date_lbl.text = GameClock.get_date_string()
	var p: bool = GameClock.paused
	if _pause_btn:
		_pause_btn.text = "▶" if p else "⏸"
	for i in _speed_btns.size():
		_speed_btns[i].button_pressed = (GameClock.speed == i + 1) and not p


func _draw() -> void:
	# Outer glow ring
	draw_arc(CLOCK_C, CLOCK_R + 3.0, 0.0, TAU, 64, COL_RIM2, 2.0)
	# Face fill
	draw_circle(CLOCK_C, CLOCK_R, COL_FACE)
	# Rim
	draw_arc(CLOCK_C, CLOCK_R, 0.0, TAU, 64, COL_RIM, 2.5)

	# Tick marks
	for i: int in 12:
		var a:     float   = (float(i) / 12.0) * TAU - PI * 0.5
		var major: bool    = i % 3 == 0
		var inner: Vector2 = CLOCK_C + Vector2(cos(a), sin(a)) * (CLOCK_R - (9.0 if major else 5.0))
		var outer: Vector2 = CLOCK_C + Vector2(cos(a), sin(a)) * (CLOCK_R - 1.5)
		draw_line(inner, outer, COL_TICK_H if major else COL_TICK, 2.0 if major else 1.0)

	# Hour hand (with drop shadow)
	var h12:  float   = float(GameClock.date.hour % 12)
	var ha:   float   = (h12 / 12.0) * TAU - PI * 0.5
	var hend: Vector2 = CLOCK_C + Vector2(cos(ha), sin(ha)) * (CLOCK_R * 0.56)
	draw_line(CLOCK_C + Vector2(1, 1), hend + Vector2(1, 1), Color(0, 0, 0, 0.4), 4.0, true)
	draw_line(CLOCK_C, hend, COL_HAND, 3.0, true)

	# Center dot
	draw_circle(CLOCK_C, 4.0, COL_DOT)
	draw_circle(CLOCK_C, 2.0, Color(1, 1, 1, 0.9))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("speed_1"): GameClock.set_speed(1)
	elif event.is_action_pressed("speed_2"): GameClock.set_speed(2)
	elif event.is_action_pressed("speed_3"): GameClock.set_speed(3)
	elif event.is_action_pressed("speed_4"): GameClock.set_speed(4)
	elif event.is_action_pressed("speed_5"): GameClock.set_speed(5)
