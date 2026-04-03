## WorldMemoryDB.gd
extends Node

signal memory_added(memory: Dictionary)
signal reputation_changed(iso: String)

var memories: Array[Dictionary] = []
var reputations: Dictionary = {}

const PERMANENT_EVENTS: Array[String] = [
	"used_nuclear_weapon",
	"committed_mass_atrocity",
	"triggered_nuclear_war",
]

const DECAY_RATES: Dictionary = {
	"used_nuclear_weapon":       0.0,
	"committed_mass_atrocity":   0.0,
	"betrayed_alliance_at_war":  0.05,
	"destroyed_nation":          0.05,
	"broke_peace_treaty_early":  0.05,
	"sanctioned_ally":           0.15,
	"broke_trade_deal":          0.15,
	"denied_proven_gray_zone":   0.15,
	"aided_disaster":            0.1,
	"supported_ally_in_war":     0.1,
	"kept_major_treaty":         0.1,
	"diplomatic_insult":         0.3,
	"refused_trade_deal":        0.3,
	"recalled_ambassador":       0.3,
}

const REPUTATION_IMPACT: Dictionary = {
	"betrayed_alliance_at_war":  { "treaty_reliability": -30, "consistency": -15 },
	"broke_peace_treaty_early":  { "treaty_reliability": -20 },
	"sanctioned_ally":           { "treaty_reliability": -10, "aggression": 5 },
	"used_nuclear_weapon":       { "nuclear_posture": -80, "military_restraint": -50, "aggression": 40 },
	"destroyed_nation":          { "aggression": 30, "military_restraint": -20 },
	"committed_mass_atrocity":   { "military_restraint": -60, "generosity": -20 },
	"aided_disaster":            { "generosity": 20, "consistency": 5 },
	"supported_ally_in_war":     { "treaty_reliability": 15, "consistency": 10 },
	"kept_major_treaty":         { "treaty_reliability": 10, "consistency": 8 },
}


func _ready() -> void:
	GameClock.tick_year.connect(_on_year)


func record(event_type: String, actor_iso: String, target_iso: String,
		witnesses: Array = [], weight: float = 1.0) -> void:
	var decay: float = DECAY_RATES.get(event_type, 0.2)
	var memory: Dictionary = {
		"event_type":       event_type,
		"actor_iso":        actor_iso,
		"target_iso":       target_iso,
		"witnesses":        witnesses,
		"weight":           weight,
		"decay_rate":       decay,
		"current_strength": weight,
		"date":             GameClock.date.duplicate(),
	}
	memories.append(memory)
	emit_signal("memory_added", memory)
	_apply_reputation_impact(actor_iso, event_type, weight)


func get_memories_for(iso: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for m: Dictionary in memories:
		if m.actor_iso == iso or m.target_iso == iso:
			result.append(m)
	return result


func get_reputation(iso: String) -> Dictionary:
	if not reputations.has(iso):
		reputations[iso] = _default_reputation()
	return reputations[iso]


func _default_reputation() -> Dictionary:
	return {
		"treaty_reliability":  0.0,
		"aggression":          0.0,
		"generosity":          0.0,
		"military_restraint":  0.0,
		"consistency":         0.0,
		"nuclear_posture":     0.0,
	}


func _apply_reputation_impact(iso: String, event_type: String, weight: float) -> void:
	if not REPUTATION_IMPACT.has(event_type):
		return
	var rep: Dictionary = get_reputation(iso)
	var impact: Dictionary = REPUTATION_IMPACT[event_type]
	for axis: String in impact:
		rep[axis] = clampf(rep[axis] + float(impact[axis]) * weight, -100.0, 100.0)
	emit_signal("reputation_changed", iso)


func _on_year(_date: Dictionary) -> void:
	for memory: Dictionary in memories:
		if memory.decay_rate == 0.0:
			continue
		memory.current_strength = maxf(
			0.0, memory.current_strength - memory.weight * float(memory.decay_rate)
		)
	_rebuild_all_reputations()


func _rebuild_all_reputations() -> void:
	reputations.clear()
	for memory: Dictionary in memories:
		if float(memory.current_strength) <= 0.01:
			continue
		_apply_reputation_impact(
			memory.actor_iso, memory.event_type,
			float(memory.current_strength) / float(memory.weight)
		)
