## NotificationItem.gd
## A single dismissable notification in the feed.
class_name NotificationItem
extends PanelContainer

@onready var _label:      Label  = $HBox/Label
@onready var _action_btn: Button = $HBox/ActionButton
@onready var _close_btn:  Button = $HBox/CloseButton

var _action_panel: String = ""


func setup(notif: Dictionary) -> void:
	_label.text = notif.get("text", "")
	_action_panel = notif.get("action_panel", "")
	var action_label: String = notif.get("action_label", "")

	if action_label.is_empty() or _action_panel.is_empty():
		_action_btn.visible = false
	else:
		_action_btn.text = action_label
		_action_btn.visible = true

	_action_btn.pressed.connect(_on_action)
	_close_btn.pressed.connect(queue_free)


func _on_action() -> void:
	UIManager.unlock_panel(_action_panel, UIManager.PanelState.FULL)
	queue_free()
