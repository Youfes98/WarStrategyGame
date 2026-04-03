## AISystem.gd
## Autoload — basic AI decision loop.
## Each AI country picks ONE action per month from a weighted list.
## Makes the world feel alive even before sophisticated AI exists.
extends Node

const ACTION_WEIGHTS: Dictionary = {
	"idle":              40,
	"build_military":    15,
	"invest_infra":      15,
	"diplomatic_drift":  10,
	"stability_focus":   10,
	"aggressive_posture": 5,
	"trade_outreach":     5,
}


func _ready() -> void:
	GameClock.tick_month.connect(_on_month)


func _on_month(_date: Dictionary) -> void:
	var player: String = GameState.player_iso
	if player.is_empty():
		return
	for iso: String in GameState.countries:
		if iso == player:
			continue
		_ai_turn(iso)


func _ai_turn(iso: String) -> void:
	var data: Dictionary = GameState.countries[iso]
	var action: String = _pick_action(iso, data)

	match action:
		"build_military":
			_do_build_military(iso, data)
		"invest_infra":
			_do_invest_infra(iso, data)
		"stability_focus":
			_do_stability_focus(iso, data)
		"diplomatic_drift":
			_do_diplomatic_drift(iso)
		"aggressive_posture":
			_do_aggressive_posture(iso, data)
		"trade_outreach":
			_do_trade_outreach(iso)
		_:
			pass   # idle — do nothing


func _pick_action(iso: String, data: Dictionary) -> String:
	var weights: Dictionary = ACTION_WEIGHTS.duplicate()
	var stability: float = float(data.get("stability", 50))
	var treasury: float = float(data.get("treasury", 0.0))
	var tier: String = data.get("power_tier", "C")

	# Adjust weights based on situation
	if stability < 30:
		weights["stability_focus"] += 30
		weights["aggressive_posture"] = 0
	if stability > 70:
		weights["invest_infra"] += 10
	if tier in ["S", "A"]:
		weights["aggressive_posture"] += 10
		weights["diplomatic_drift"] += 10
	if treasury < 1.0:
		weights["invest_infra"] += 15
		weights["build_military"] -= 10

	# Check if at war — prioritize military
	for other_iso: String in GameState.countries:
		if GameState.is_at_war(iso, other_iso):
			weights["build_military"] += 40
			weights["idle"] = 5
			break

	# Weighted random pick
	var total: int = 0
	for w: int in weights.values():
		total += maxi(0, w)
	if total <= 0:
		return "idle"

	var roll: int = randi() % total
	var cumulative: int = 0
	for act: String in weights:
		cumulative += maxi(0, weights[act])
		if roll < cumulative:
			return act
	return "idle"


# ── Actions ───────────────────────────────────────────────────────────────────

func _do_build_military(iso: String, data: Dictionary) -> void:
	var treasury: float = float(data.get("treasury", 0.0))
	# Pick unit type based on tier and budget
	var type: String = "infantry"
	var tier: String = data.get("power_tier", "D")
	if tier in ["S", "A"] and treasury >= 3.0 and randf() < 0.3:
		type = "armor"
	elif tier in ["S", "A", "B"] and treasury >= 1.2 and randf() < 0.2:
		type = "artillery"
	var cost: float = float(MilitarySystem.UNIT_TYPES[type].get("cost", 0.5))
	if treasury >= cost:
		data["treasury"] = treasury - cost
		var home: String = ProvinceDB.get_main_province(iso)
		MilitarySystem.spawn_unit(type, iso, home)


func _do_invest_infra(_iso: String, data: Dictionary) -> void:
	var infra: int = int(data.get("infrastructure", 30))
	var treasury: float = float(data.get("treasury", 0.0))
	var invest_cost: float = 0.5   # $0.5B infrastructure investment
	if treasury >= invest_cost and infra < 95:
		data["infrastructure"] = mini(95, infra + randi_range(1, 3))
		data["treasury"] = treasury - invest_cost


func _do_stability_focus(_iso: String, data: Dictionary) -> void:
	var stab: float = float(data.get("stability", 50))
	data["stability"] = minf(95.0, stab + randf_range(1.0, 4.0))


func _do_diplomatic_drift(iso: String) -> void:
	# Slightly improve relations with a random neighbour
	var neighbors: Array = ProvinceDB.adjacencies.get(iso, [])
	if neighbors.is_empty():
		return
	var target: String = neighbors[randi() % neighbors.size()]
	var rel: Dictionary = GameState.get_relation(iso, target)
	rel["diplomatic_score"] = int(rel.get("diplomatic_score", 0)) + randi_range(1, 5)


func _do_aggressive_posture(iso: String, data: Dictionary) -> void:
	# If strong enough and a weak neighbor exists, may declare war
	var tier: String = data.get("power_tier", "D")
	if tier in ["D", "C"]:
		return   # Weak countries don't start wars
	var neighbors: Array = ProvinceDB.adjacencies.get(iso, [])
	for nb: String in neighbors:
		if nb == GameState.player_iso:
			continue   # Don't auto-declare on player (for now)
		if GameState.is_at_war(iso, nb):
			continue
		var nb_data: Dictionary = GameState.get_country(nb)
		var nb_tier: String = nb_data.get("power_tier", "C")
		# Only bully weaker countries
		if _tier_rank(tier) >= _tier_rank(nb_tier) + 2:
			if randf() < 0.15:   # 15% chance per eligible neighbor
				GameState.set_war(iso, nb, true)
				return


func _do_trade_outreach(iso: String) -> void:
	var neighbors: Array = ProvinceDB.adjacencies.get(iso, [])
	if neighbors.is_empty():
		return
	var target: String = neighbors[randi() % neighbors.size()]
	var rel: Dictionary = GameState.get_relation(iso, target)
	rel["trade_volume"] = float(rel.get("trade_volume", 0.0)) + randf_range(0.5, 3.0)
	rel["diplomatic_score"] = int(rel.get("diplomatic_score", 0)) + 1


func _tier_rank(tier: String) -> int:
	match tier:
		"S": return 5
		"A": return 4
		"B": return 3
		"C": return 2
		_:   return 1
