## PauseMenu.gd
## Escape key → pause menu overlay with Save, Load, Resume, Quit.
extends Control

var _panel: PanelContainer = null

const BG_COLOR:   Color = Color(0.0, 0.0, 0.0, 0.60)
const PANEL_BG:   Color = Color(0.08, 0.08, 0.10, 0.95)
const TITLE_COL:  Color = Color(0.85, 0.75, 0.45)
const BTN_MIN:    Vector2 = Vector2(200, 36)


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Full-screen dark overlay
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Centered panel
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(260, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "GAME PAUSED"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", TITLE_COL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_add_button(vbox, "Resume", _on_resume)
	_add_button(vbox, "Quick Save (F5)", _on_save)
	_add_button(vbox, "Quick Load (F9)", _on_load)
	vbox.add_child(HSeparator.new())
	_add_button(vbox, "Quit to Desktop", _on_quit)


func _add_button(parent: VBoxContainer, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = BTN_MIN
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(callback)
	parent.add_child(btn)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if visible:
				_on_resume()
			else:
				_show_menu()
			get_viewport().set_input_as_handled()


func _show_menu() -> void:
	visible = true
	GameClock.set_paused(true)


func _on_resume() -> void:
	visible = false
	GameClock.set_paused(false)


func _on_save() -> void:
	SaveSystem.quicksave()
	visible = false
	GameClock.set_paused(false)


func _on_load() -> void:
	SaveSystem.quickload()
	visible = false
	GameClock.set_paused(false)


func _on_quit() -> void:
	get_tree().quit()
