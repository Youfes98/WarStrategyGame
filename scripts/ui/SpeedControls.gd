## SpeedControls.gd
extends HBoxContainer

@onready var _pause_btn:  Button = $PauseButton
@onready var _date_label: Label  = $DateLabel
@onready var _s1: Button = $Speed1
@onready var _s2: Button = $Speed2
@onready var _s3: Button = $Speed3
@onready var _s4: Button = $Speed4
@onready var _s5: Button = $Speed5


func _ready() -> void:
	GameClock.speed_changed.connect(_on_speed_changed)
	GameClock.pause_changed.connect(_on_pause_changed)
	GameClock.tick_day.connect(_on_day)

	_pause_btn.pressed.connect(GameClock.toggle_pause)
	_s1.pressed.connect(func() -> void: GameClock.set_speed(1))
	_s2.pressed.connect(func() -> void: GameClock.set_speed(2))
	_s3.pressed.connect(func() -> void: GameClock.set_speed(3))
	_s4.pressed.connect(func() -> void: GameClock.set_speed(4))
	_s5.pressed.connect(func() -> void: GameClock.set_speed(5))

	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		GameClock.toggle_pause()
	elif event.is_action_pressed("speed_1"): GameClock.set_speed(1)
	elif event.is_action_pressed("speed_2"): GameClock.set_speed(2)
	elif event.is_action_pressed("speed_3"): GameClock.set_speed(3)
	elif event.is_action_pressed("speed_4"): GameClock.set_speed(4)
	elif event.is_action_pressed("speed_5"): GameClock.set_speed(5)


func _on_speed_changed(_speed: int) -> void:
	_refresh_ui()


func _on_pause_changed(_paused: bool) -> void:
	_refresh_ui()


func _on_day(_date: Dictionary) -> void:
	_date_label.text = GameClock.get_date_string()


func _refresh_ui() -> void:
	_pause_btn.text = ">" if GameClock.paused else "||"
	_date_label.text = GameClock.get_date_string()
	_s1.button_pressed = GameClock.speed == 1 and not GameClock.paused
	_s2.button_pressed = GameClock.speed == 2 and not GameClock.paused
	_s3.button_pressed = GameClock.speed == 3 and not GameClock.paused
	_s4.button_pressed = GameClock.speed == 4 and not GameClock.paused
	_s5.button_pressed = GameClock.speed == 5 and not GameClock.paused
