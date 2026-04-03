## MapCamera.gd
## Handles only keyboard pan (WASD / arrow keys).
## No horizontal limits — world wraps seamlessly. Vertical locked to map height.
extends Camera2D

const MAP_WIDTH:  float = 16384.0
const MAP_HEIGHT: float = 8192.0
const PAN_SPEED:  float = 900.0


func _ready() -> void:
	position     = Vector2(MAP_WIDTH / 2.0, MAP_HEIGHT / 2.0)
	zoom         = Vector2(0.5, 0.5)
	# No left/right limits — map tiles handle the endless look
	limit_left   = -1_000_000
	limit_right  =  1_000_000
	limit_top    = 0
	limit_bottom = int(MAP_HEIGHT)


func _process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):  dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"): dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):    dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):  dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
