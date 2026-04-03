## DiplomacyPanel.gd
## Shows diplomatic status and actions when the player selects a foreign country.
## All children created programmatically.
extends PanelContainer

var _title_lbl:  Label = null
var _status_lbl: Label = null
var _score_lbl:  Label = null
var _trade_lbl:  Label = null
var _budget_lbl: Label = null
var _action_btns: Dictionary = {}   # action_key → Button

const ACTIONS: Array = [
	["improve_relations", "Improve Relations  ($2B)"],
	["offer_trade",       "Offer Trade Deal   ($1B/mo)"],
	["sanction",          "Impose Sanctions"],
]


func _ready() -> void:
	custom_minimum_size = Vector2(260, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	add_child(vbox)

	# Header
	var hdr := Label.new()
	hdr.text = "DIPLOMACY"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	vbox.add_child(hdr)

	vbox.add_child(HSeparator.new())

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_title_lbl)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_status_lbl)

	_score_lbl = Label.new()
	_score_lbl.add_theme_font_size_override("font_size", 10)
	_score_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(_score_lbl)

	_trade_lbl = Label.new()
	_trade_lbl.add_theme_font_size_override("font_size", 10)
	_trade_lbl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	_trade_lbl.visible = false
	vbox.add_child(_trade_lbl)

	vbox.add_child(HSeparator.new())

	# Treasury display inside the panel
	var budget_hdr := Label.new()
	budget_hdr.text = "YOUR TREASURY"
	budget_hdr.add_theme_font_size_override("font_size", 9)
	budget_hdr.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(budget_hdr)

	_budget_lbl = Label.new()
	_budget_lbl.add_theme_font_size_override("font_size", 12)
	_budget_lbl.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	vbox.add_child(_budget_lbl)

	vbox.add_child(HSeparator.new())

	# Action buttons
	for entry in ACTIONS:
		var btn := Button.new()
		btn.text = entry[1]
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 26)
		var key: String = entry[0]
		btn.pressed.connect(func() -> void: _on_action(key))
		vbox.add_child(btn)
		_action_btns[key] = btn

	GameState.country_selected.connect(_on_selected)
	GameState.country_deselected.connect(_on_deselected)
	GameState.country_data_changed.connect(_on_data_changed)
	UIManager.panel_unlocked.connect(_on_panel_unlocked)
	visible = false


func _on_panel_unlocked(panel_name: String, _state: UIManager.PanelState) -> void:
	if panel_name != "diplomacy":
		return
	if not GameState.selected_iso.is_empty():
		_on_selected(GameState.selected_iso)


func _on_selected(iso: String) -> void:
	if UIManager.get_panel_state("diplomacy") == UIManager.PanelState.HIDDEN:
		visible = false
		return
	if GameState.player_iso.is_empty() or iso == GameState.player_iso:
		visible = false
		return
	visible = true
	_refresh(iso)


func _on_deselected() -> void:
	visible = false


func _on_data_changed(iso: String) -> void:
	if iso == GameState.selected_iso and visible:
		_refresh(iso)


func _refresh(iso: String) -> void:
	var data:   Dictionary = GameState.get_country(iso)
	var player: String     = GameState.player_iso

	_title_lbl.text = "%s %s" % [data.get("flag_emoji", ""), data.get("name", iso)]

	var rel:     Dictionary = GameState.get_relation(player, iso)
	var score:   float      = float(rel.get("diplomatic_score", 0.0))
	var at_war:  bool       = rel.get("at_war", false)
	var allied:  bool       = rel.get("alliance", false)
	var trading: bool       = rel.get("trade_deal", false)

	var sign: String = "+" if score >= 0 else ""
	_score_lbl.text = "Relations: %s%d / 100" % [sign, int(score)]

	var status: String
	var col:    Color
	if at_war:
		status = "★  AT WAR"
		col    = Color(0.95, 0.25, 0.25)
	elif allied:
		status = "★  ALLIED"
		col    = Color(0.30, 0.90, 0.50)
	elif score >= 50:
		status = "Friendly"
		col    = Color(0.50, 0.90, 0.50)
	elif score >= 15:
		status = "Warm"
		col    = Color(0.70, 0.90, 0.40)
	elif score >= -15:
		status = "Neutral"
		col    = Color(0.75, 0.75, 0.75)
	elif score >= -50:
		status = "Cold"
		col    = Color(0.55, 0.55, 0.90)
	else:
		status = "Hostile"
		col    = Color(0.95, 0.40, 0.30)

	_status_lbl.text = status
	_status_lbl.add_theme_color_override("font_color", col)

	_trade_lbl.visible = trading
	if trading:
		_trade_lbl.text = "✦ Trade Deal Active (+GDP)"

	# Treasury + button states
	var pdata: Dictionary = GameState.get_country(player)
	var treasury: float   = float(pdata.get("treasury", 0.0))
	if _budget_lbl:
		_budget_lbl.text = _fmt_gdp(treasury)
		var budget_col: Color = Color(0.8, 1.0, 0.8) if treasury >= 2.0 else Color(0.95, 0.45, 0.35)
		_budget_lbl.add_theme_color_override("font_color", budget_col)
	_action_btns["improve_relations"].disabled = treasury < 2.0 or at_war
	_action_btns["offer_trade"].disabled       = treasury < 1.0 or trading or at_war
	_action_btns["sanction"].disabled          = at_war


func _fmt_gdp(billions: float) -> String:
	if billions >= 1000.0:
		return "$%.2fT" % (billions / 1000.0)
	return "$%.1fB" % billions


func _on_action(action: String) -> void:
	var iso:    String     = GameState.selected_iso
	var player: String     = GameState.player_iso
	if iso.is_empty() or player.is_empty() or iso == player:
		return

	var pdata:  Dictionary = GameState.get_country(player)
	var treasury: float   = float(pdata.get("treasury", 0.0))
	var rel:    Dictionary = GameState.get_relation(player, iso)
	var oname:  String     = GameState.get_country(iso).get("name", iso)

	match action:
		"improve_relations":
			if treasury < 2.0:
				UIManager.push_notification("Insufficient treasury for diplomatic mission.", "warning")
				return
			pdata["treasury"] = treasury - 2.0
			rel["diplomatic_score"] = clampf(rel.get("diplomatic_score", 0.0) + 15.0, -100.0, 100.0)
			GameState.country_data_changed.emit(player)
			UIManager.push_notification(
				"Diplomatic mission to %s improved relations (+15)." % oname, "info")

		"offer_trade":
			if treasury < 1.0:
				UIManager.push_notification("Insufficient treasury to establish trade deal.", "warning")
				return
			if rel.get("trade_deal", false):
				UIManager.push_notification("Trade deal with %s already active." % oname, "info")
				return
			pdata["treasury"] = treasury - 1.0
			rel["diplomatic_score"] = clampf(rel.get("diplomatic_score", 0.0) + 10.0, -100.0, 100.0)
			rel["trade_deal"] = true
			GameState.country_data_changed.emit(player)
			UIManager.push_notification(
				"Trade deal signed with %s. Monthly GDP bonus active." % oname, "info")

		"sanction":
			if rel.get("at_war", false):
				UIManager.push_notification("Already at war with %s." % oname, "warning")
				return
			rel["diplomatic_score"] = clampf(rel.get("diplomatic_score", 0.0) - 30.0, -100.0, 100.0)
			UIManager.push_notification(
				"Sanctions imposed on %s. Relations deteriorated (−30)." % oname, "warning")

	_refresh(iso)
