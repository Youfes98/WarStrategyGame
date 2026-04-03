## Main.gd
## Root scene controller.
## Manages the "pick your country" phase before the game starts.
extends Node

@onready var _country_card: PanelContainer = $HUD/CountryCard
@onready var _pick_banner:  PanelContainer = $HUD/PickBanner


# Watchdog: quit cleanly if FPS stays critically low (GPU runaway protection)
var _low_fps_ticks: int = 0
const LOW_FPS_THRESHOLD: float = 4.0
const LOW_FPS_QUIT_TICKS: int  = 180   # ~3 seconds at 60fps


func _process(_delta: float) -> void:
	if Engine.get_frames_per_second() < LOW_FPS_THRESHOLD:
		_low_fps_ticks += 1
		if _low_fps_ticks >= LOW_FPS_QUIT_TICKS:
			get_tree().quit()
	else:
		_low_fps_ticks = 0


func _ready() -> void:
	GameClock.set_paused(true)
	_country_card.set_picking_mode(true)
	_country_card.country_confirmed.connect(_on_country_confirmed)


func _on_country_confirmed(iso: String) -> void:
	_country_card.set_picking_mode(false)
	_pick_banner.visible = false

	# Center camera on the chosen country with smooth transition
	var centroid: Vector2 = ProvinceDB.get_centroid(iso)
	if centroid != Vector2.ZERO:
		var cam := get_viewport().get_camera_2d()
		if cam:
			var tween: Tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(cam, "position", centroid, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tween.tween_property(cam, "zoom", Vector2(1.0, 1.0), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	GameState.set_player_country(iso)
	GameState.deselect()
	UIManager.push_notification(
		"Welcome, %s. The world is watching." % GameState.get_country(iso).get("name", iso),
		"info"
	)
	GameClock.set_paused(false)
