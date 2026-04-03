## NotificationFeed.gd
## Right-side notification panel — the game's primary teacher.
extends VBoxContainer

const MAX_VISIBLE := 6
const NOTIF_SCENE: PackedScene = preload("res://scenes/UI/NotificationItem.tscn")


func _ready() -> void:
	UIManager.notification_added.connect(_on_notification)


func _on_notification(notif: Dictionary) -> void:
	var item: NotificationItem = NOTIF_SCENE.instantiate() as NotificationItem
	add_child(item)
	item.setup(notif)
	move_child(item, 0)

	# remove_child is synchronous — get_child_count() drops immediately.
	# queue_free() alone does NOT update get_child_count() until end-of-frame,
	# causing an infinite loop when multiple notifications fire in one frame.
	while get_child_count() > MAX_VISIBLE:
		var old: Node = get_child(get_child_count() - 1)
		remove_child(old)
		old.queue_free()
