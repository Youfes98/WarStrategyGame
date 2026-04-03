## ClockDisplay.gd
## Top-right time & speed display — ornate grand strategy style.
## Custom-drawn frame with gold accents, speed gauge, and time-of-day bar.
extends Control

const PANEL_W: float = 220.0
const PANEL_H: float = 88.0

const COL_BG:        Color = Color(0.04, 0.05, 0.08, 0.96)
const COL_BG_INNER:  Color = Color(0.06, 0.07, 0.11, 1.0)
const COL_FRAME:     Color = Color(0.35, 0.30, 0.18, 0.90)
const COL_FRAME_LIT: Color = Color(0.65, 0.55, 0.25, 0.80)
const COL_ACCENT:    Color = Color(0.72, 0.60, 0.22)
const COL_DATE:      Color = Color(0.94, 0.92, 0.85)
const COL_TIME:      Color = Color(0.58, 0.55, 0.48)
const COL_SPEED_OFF: Color = Color(0.15, 0.16, 0.22)
const COL_SPEED_ON:  Color = Color(0.30, 0.65, 1.0)
const COL_SPEED_GLO: Color = Color(0.35, 0.70, 1.0, 0.25)
const COL_PAUSED:    Color = Color(0.95, 0.70, 0.15)
const COL_BTN_BG:    Color = Color(0.10, 0.11, 0.16)
const COL_BTN_HOV:   Color = Color(0.16, 0.18, 0.26)
const COL_BTN_TXT:   Color = Color(0.60, 0.58, 0.52)

const TOD_NIGHT: Color = Color(0.08, 0.10, 0.22)
const TOD_DAWN:  Color = Color(0.55, 0.35, 0.20)
const TOD_DAY:   Color = Color(0.40, 0.55, 0.70)
const TOD_DUSK:  Color = Color(0.50, 0.30, 0.18)

var _font:       Font   = null
var _pause_btn:  Button = null
var _speed_btns: Array[Button] = []
var _date_text:  String = ""
var _time_text:  String = ""
var _hour:       int    = 0
var _speed:      int    = 1
var _paused:     bool   = false

const SPEED_COUNT: int = 5


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_font = ThemeDB.fallback_font
	mouse_filter = MOUSE_FILTER_IGNORE

	_pause_btn = _make_btn("||", Vector2(10, 58), Vector2(32, 22))
	_pause_btn.pressed.connect(GameClock.toggle_pause)
	add_child(_pause_btn)

	var speed_x: float = 48.0
	for i: int in SPEED_COUNT:
		var btn: Button = _make_btn(str(i + 1), Vector2(speed_x + i * 30.0, 58), Vector2(26, 22))
		var spd: int = i + 1
		btn.pressed.connect(func() -> void:
			GameClock.set_paused(false)
			GameClock.set_speed(spd)
		)
		add_child(btn)
		_speed_btns.append(btn)

	GameClock.tick_hour.connect(func(_d: Dictionary) -> void: _sync(); queue_redraw())
	GameClock.pause_changed.connect(func(_v: Variant) -> void: _sync(); queue_redraw())
	GameClock.speed_changed.connect(func(_v: Variant) -> void: _sync(); queue_redraw())
	_sync()


func _make_btn(btn_text: String, pos: Vector2, sz: Vector2) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.position = pos
	btn.size = sz
	btn.add_theme_font_size_override("font_size", 10)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_BTN_BG
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COL_BTN_HOV
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = COL_SPEED_ON.darkened(0.4)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", COL_BTN_TXT)
	btn.add_theme_color_override("font_hover_color", COL_DATE)
	return btn


func _sync() -> void:
	_date_text = GameClock.get_date_string()
	_hour = GameClock.date.hour
	_time_text = "%02d:00" % _hour
	_speed = GameClock.speed
	_paused = GameClock.paused
	_pause_btn.text = "||" if not _paused else ">"
	if _paused:
		_pause_btn.add_theme_color_override("font_color", COL_PAUSED)
	else:
		_pause_btn.add_theme_color_override("font_color", COL_BTN_TXT)
	for i: int in _speed_btns.size():
		var active: bool = (_speed == i + 1) and not _paused
		_speed_btns[i].add_theme_color_override("font_color", COL_SPEED_ON if active else COL_BTN_TXT)
		_speed_btns[i].add_theme_color_override("font_hover_color", COL_SPEED_ON if active else COL_DATE)


func _draw() -> void:
	var rect: Rect2 = Rect2(0, 0, PANEL_W, PANEL_H)

	# Drop shadow
	draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.3))
	# Main BG
	draw_rect(rect, COL_BG)
	# Inner panel
	var inner: Rect2 = Rect2(4, 4, PANEL_W - 8, PANEL_H - 8)
	draw_rect(inner, COL_BG_INNER)
	# Frame borders
	draw_rect(rect, COL_FRAME, false, 1.5)
	draw_rect(inner, Color(COL_FRAME.r, COL_FRAME.g, COL_FRAME.b, 0.3), false, 1.0)

	# Corner accents (gold L-shapes)
	var cl: float = 12.0
	var cw: float = 2.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(PANEL_W, 0), Vector2(0, PANEL_H), Vector2(PANEL_W, PANEL_H)]:
		var dx: float = -1.0 if corner.x > 0 else 1.0
		var dy: float = -1.0 if corner.y > 0 else 1.0
		draw_line(corner, corner + Vector2(dx * cl, 0), COL_FRAME_LIT, cw)
		draw_line(corner, corner + Vector2(0, dy * cl), COL_FRAME_LIT, cw)

	# Time-of-day bar
	draw_rect(Rect2(4, 4, PANEL_W - 8, 3), _get_tod_color(_hour))

	# Date + time text
	if _font:
		draw_string(_font, Vector2(12, 30), _date_text,
			HORIZONTAL_ALIGNMENT_LEFT, int(PANEL_W - 60), 18, COL_DATE)
		draw_string(_font, Vector2(PANEL_W - 56, 30), _time_text,
			HORIZONTAL_ALIGNMENT_RIGHT, 44, 13, COL_TIME)

	# Speed gauge pips
	var gx: float = 12.0
	var gy: float = 40.0
	var pw: float = 28.0
	var ph: float = 5.0
	var pg: float = 3.0
	for i: int in SPEED_COUNT:
		var px: float = gx + i * (pw + pg)
		if not _paused and _speed >= i + 1:
			draw_rect(Rect2(px, gy, pw, ph), COL_SPEED_ON)
			draw_rect(Rect2(px, gy - 2, pw, 2), COL_SPEED_GLO)
		else:
			draw_rect(Rect2(px, gy, pw, ph), COL_SPEED_OFF)

	# Status after pips
	if _font:
		var lx: float = gx + SPEED_COUNT * (pw + pg) + 4
		if _paused:
			draw_string(_font, Vector2(lx, gy + ph), "PAUSED",
				HORIZONTAL_ALIGNMENT_LEFT, 60, 9, COL_PAUSED)
		else:
			draw_string(_font, Vector2(lx, gy + ph), "x%d" % _speed,
				HORIZONTAL_ALIGNMENT_LEFT, 30, 9, COL_SPEED_ON)

	# Separator above buttons
	draw_line(Vector2(8, 54), Vector2(PANEL_W - 8, 54), COL_FRAME, 0.5)


func _get_tod_color(hour: int) -> Color:
	if hour >= 22 or hour < 5:   return TOD_NIGHT
	elif hour < 7:  return TOD_NIGHT.lerp(TOD_DAWN, (hour - 5.0) / 2.0)
	elif hour < 10: return TOD_DAWN.lerp(TOD_DAY, (hour - 7.0) / 3.0)
	elif hour < 17: return TOD_DAY
	elif hour < 20: return TOD_DAY.lerp(TOD_DUSK, (hour - 17.0) / 3.0)
	else:           return TOD_DUSK.lerp(TOD_NIGHT, (hour - 20.0) / 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("speed_1"): GameClock.set_paused(false); GameClock.set_speed(1)
	elif event.is_action_pressed("speed_2"): GameClock.set_paused(false); GameClock.set_speed(2)
	elif event.is_action_pressed("speed_3"): GameClock.set_paused(false); GameClock.set_speed(3)
	elif event.is_action_pressed("speed_4"): GameClock.set_paused(false); GameClock.set_speed(4)
	elif event.is_action_pressed("speed_5"): GameClock.set_paused(false); GameClock.set_speed(5)
