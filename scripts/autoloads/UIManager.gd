## UIManager.gd
extends Node

signal panel_unlocked(panel_name: String, state: PanelState)
signal notification_added(notif: Dictionary)

enum PanelState { HIDDEN, MINIMAL, FULL }

var panel_states: Dictionary = {
	"economy":    PanelState.HIDDEN,
	"diplomacy":  PanelState.HIDDEN,
	"research":   PanelState.HIDDEN,
	"military":   PanelState.HIDDEN,
	"governance": PanelState.HIDDEN,
	"cabinet":    PanelState.HIDDEN,
	"intel":      PanelState.HIDDEN,
	"resources":  PanelState.HIDDEN,
	"history":    PanelState.HIDDEN,
}

var notifications: Array[Dictionary] = []
var _panel_nodes: Dictionary = {}
var _first_month_done: bool = false


func _ready() -> void:
	GameClock.tick_month.connect(_on_first_month)
	GameState.country_selected.connect(_on_country_selected)


func register_panel(panel_name: String, node: Node) -> void:
	_panel_nodes[panel_name] = node


func unlock_panel(panel: String, state: PanelState = PanelState.MINIMAL) -> void:
	if not panel_states.has(panel):
		return
	if panel_states[panel] >= state:
		return
	panel_states[panel] = state
	emit_signal("panel_unlocked", panel, state)
	if _panel_nodes.has(panel):
		_panel_nodes[panel].set_panel_state(state)


func get_panel_state(panel: String) -> PanelState:
	return panel_states.get(panel, PanelState.HIDDEN)


func push_notification(text: String, type: String = "info",
		action_label: String = "", action_panel: String = "") -> void:
	var notif: Dictionary = {
		"text":         text,
		"type":         type,
		"action_label": action_label,
		"action_panel": action_panel,
		"timestamp":    GameClock.get_date_string(),
	}
	notifications.push_front(notif)
	if notifications.size() > 50:
		notifications.pop_back()
	emit_signal("notification_added", notif)


func _on_first_month(_date: Dictionary) -> void:
	if _first_month_done:
		return
	_first_month_done = true
	unlock_panel("economy", PanelState.MINIMAL)
	push_notification(
		"Your economy is now being tracked.",
		"info", "View", "economy"
	)


func _on_country_selected(iso: String) -> void:
	# Only unlock diplomacy once the player has confirmed their country
	# and is clicking on a *foreign* nation for the first time.
	if GameState.player_iso.is_empty() or iso == GameState.player_iso:
		return
	if get_panel_state("diplomacy") == PanelState.HIDDEN:
		unlock_panel("diplomacy", PanelState.MINIMAL)
		push_notification(
			"You can now conduct diplomacy with other nations.",
			"info", "View", "diplomacy"
		)
