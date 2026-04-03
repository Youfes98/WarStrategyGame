## ClockDisplay.gd
## Top-right HUD: clean date display + speed controls in a compact horizontal bar.
## Styled after Paradox grand strategy games — no analog clock.
extends Control

const COL_BG:       Color = Color(0.06, 0.08, 0.12, 0.94)
const COL_BORDER:   Color = Color(0.20, 0.28, 0.42, 0.80)
const COL_DATE:     Color = Color(0.92, 0.94, 0.98)
const COL_TIME:     Color = Color(0.60, 0.68, 0.78)
const COL_ACTIVE:   Color = Color(0.30, 0.65, 1.0)
const COL_PAUSED:   Color = Color(1.0,  0.75, 0.20)
const COL_BTN_BG:   Color = Color(0.12, 0.15, 0.22)
const COL_BTN_HOV:  Color = Color(0.18, 0.22, 0.32)
const COL_BTN_TXT:  Color = Color(0.65, 0.70, 0.78)

var _date_lbl:     Label  = null
var _time_lbl:     Label  = null
var _status_lbl:   Label  = null
var _pause_btn:    Button = null
var _speed_btns:   Array[Button] = []

const SPEED_LABELS: Array[String] = ["1", "2", "3", "4", "5"]


func _ready() -> void:
	custom_minimum_size = Vector2(200, 72)
	mouse_filter = MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_BORDER
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 0
	style.border_width_top = 0
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# Row 1: Date + Time
	var date_row := HBoxContainer.new()
	date_row.add_theme_constant_override("separation", 8)
	vbox.add_child(date_row)

	_date_lbl = Label.new()
	_date_lbl.add_theme_font_size_override("font_size", 16)
	_date_lbl.add_theme_color_override("font_color", COL_DATE)
	_date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	date_row.add_child(_date_lbl)

	_time_lbl = Label.new()
	_time_lbl.add_theme_font_size_override("font_size", 12)
	_time_lbl.add_theme_color_override("font_color", COL_TIME)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	date_row.add_child(_time_lbl)

	# Row 2: Speed controls
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 2)
	vbox.add_child(speed_row)

	_pause_btn = _make_speed_btn(">>", 36)
	_pause_btn.pressed.connect(GameClock.toggle_pause)
	speed_row.add_child(_pause_btn)

	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(4, 0)
	speed_row.add_child(sep)

	for i: int in 5:
		var btn: Button = _make_speed_btn(SPEED_LABELS[i], 28)
		var spd: int = i + 1
		btn.pressed.connect(func() -> void:
			GameClock.set_paused(false)
			GameClock.set_speed(spd)
		)
		speed_row.add_child(btn)
		_speed_btns.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(spacer)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 10)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	speed_row.add_child(_status_lbl)

	GameClock.tick_hour.connect(_on_tick)
	GameClock.pause_changed.connect(func(_v: Variant) -> void: _refresh())
	GameClock.speed_changed.connect(func(_v: Variant) -> void: _refresh())
	_refresh()


func _make_speed_btn(btn_text: String, width: int) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(width, 24)
	btn.add_theme_font_size_override("font_size", 11)

	var normal := StyleBoxFlat.new()
	normal.bg_color = COL_BTN_BG
	normal.corner_radius_top_left = 3
	normal.corner_radius_top_right = 3
	normal.corner_radius_bottom_left = 3
	normal.corner_radius_bottom_right = 3
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COL_BTN_HOV
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = COL_ACTIVE.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", COL_BTN_TXT)
	btn.add_theme_color_override("font_hover_color", COL_DATE)
	return btn


func _on_tick(_d: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	if _date_lbl == null:
		return

	_date_lbl.text = GameClock.get_date_string()
	_time_lbl.text = "%02d:00" % GameClock.date.hour

	_pause_btn.text = ">>" if GameClock.paused else "||"

	for i: int in _speed_btns.size():
		var btn: Button = _speed_btns[i]
		var is_active: bool = (GameClock.speed == i + 1) and not GameClock.paused
		if is_active:
			btn.add_theme_color_override("font_color", COL_ACTIVE)
			btn.add_theme_color_override("font_hover_color", COL_ACTIVE)
		else:
			btn.add_theme_color_override("font_color", COL_BTN_TXT)
			btn.add_theme_color_override("font_hover_color", COL_DATE)

	if GameClock.paused:
		_status_lbl.text = "PAUSED"
		_status_lbl.add_theme_color_override("font_color", COL_PAUSED)
	else:
		_status_lbl.text = "Speed %d" % GameClock.speed
		_status_lbl.add_theme_color_override("font_color", COL_ACTIVE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("speed_1"): GameClock.set_paused(false); GameClock.set_speed(1)
	elif event.is_action_pressed("speed_2"): GameClock.set_paused(false); GameClock.set_speed(2)
	elif event.is_action_pressed("speed_3"): GameClock.set_paused(false); GameClock.set_speed(3)
	elif event.is_action_pressed("speed_4"): GameClock.set_paused(false); GameClock.set_speed(4)
	elif event.is_action_pressed("speed_5"): GameClock.set_paused(false); GameClock.set_speed(5)
