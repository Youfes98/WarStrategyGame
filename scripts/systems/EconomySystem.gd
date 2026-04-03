## EconomySystem.gd
## Autoload singleton — drives monthly economic simulation.
## Reads/writes country data in GameState.countries.
## Subscribes to GameClock.tick_month.
extends Node


func _ready() -> void:
	GameClock.tick_month.connect(_on_month)


func _on_month(_date: Dictionary) -> void:
	for iso: String in GameState.countries:
		_tick_country(iso)


func _tick_country(iso: String) -> void:
	var data: Dictionary = GameState.countries[iso]

	# --- GDP Growth ---
	# Base rate: 2% per year → ~0.167% per month
	# Modifiers pull from stability, infrastructure, credit rating.
	var base_monthly: float = 0.00167

	var stability: float    = float(data.get("stability", 50))
	var infra: float        = float(data.get("infrastructure", 50))
	var credit: float       = float(data.get("credit_rating", 50))
	var debt_ratio: float   = float(data.get("debt_to_gdp", 60))

	# Stability modifier: -50% at stab=0, +0% at stab=50, +30% at stab=100
	var stab_mod: float = (stability - 50.0) / 50.0 * 0.5

	# Infrastructure modifier: -20% at infra=0, +20% at infra=100
	var infra_mod: float = (infra - 50.0) / 50.0 * 0.2

	# Debt drag: above 80% debt/GDP, growth starts suffering
	var debt_drag: float = 0.0
	if debt_ratio > 80.0:
		debt_drag = -(debt_ratio - 80.0) / 200.0  # max -1% monthly at 280% debt

	var growth: float = base_monthly + stab_mod * base_monthly + infra_mod * base_monthly + debt_drag

	# Trade deal bonus: each active deal with the player adds +$0.5B/mo
	var trade_bonus: float = 0.0
	if iso == GameState.player_iso:
		for other_iso: String in GameState.countries:
			if other_iso == iso:
				continue
			var rel: Dictionary = GameState.get_relation(iso, other_iso)
			if rel.get("trade_deal", false):
				trade_bonus += 0.5

	# Apply GDP growth to raw value
	var gdp_raw: float = float(data.get("gdp_raw_billions", 1.0))
	gdp_raw = maxf(gdp_raw * (1.0 + growth) + trade_bonus, 0.01)
	data["gdp_raw_billions"] = gdp_raw

	# Re-normalize GDP to 1–1000 log scale
	data["gdp_normalized"] = _normalize_gdp(gdp_raw)

	# --- Stability drift ---
	# Naturally drifts toward a baseline of 60.
	# High debt drags it down.
	var stab_target: float = 60.0 - maxf(0.0, (debt_ratio - 100.0) * 0.1)
	stab_target = clampf(stab_target, 20.0, 75.0)
	var new_stab: float = lerpf(stability, stab_target, 0.01)

	# Collapse risk: below 20 stability → chance of instability event
	if new_stab < 20.0 and randf() < 0.1:
		new_stab -= randf() * 5.0
		_fire_instability_event(iso, data)

	data["stability"] = clampf(new_stab, 0.0, 100.0)

	# --- Debt accumulates from interest ---
	var interest_rate: float = _interest_rate(credit)
	var monthly_interest: float = gdp_raw * (debt_ratio / 100.0) * (interest_rate / 12.0)
	# Simplified: interest increases debt_to_gdp ratio slightly
	var gdp_next: float = float(data.get("gdp_raw_billions", gdp_raw))
	if gdp_next > 0.0:
		data["debt_to_gdp"] = clampf(debt_ratio + (monthly_interest / gdp_next) * 100.0, 0.0, 500.0)

	# Only notify UI for countries it actually displays — emitting for all 195 every month
	# creates a signal storm that can spike frame time and cause catch-up spirals in GameClock.
	if iso == GameState.player_iso or iso == GameState.selected_iso:
		GameState.country_data_changed.emit(iso)


func _normalize_gdp(gdp_billions: float) -> int:
	# Log10 scale: Tuvalu $0.05B → ~1, USA $28,000B → ~1000
	var log_val: float = log(maxf(gdp_billions, 0.1)) / log(10.0)
	var normalized: float = (log_val + 1.3) / (4.4 + 1.3) * 1000.0
	return int(clampf(normalized, 1.0, 1000.0))


func _interest_rate(credit_rating: float) -> float:
	# credit 0–100 → interest 15% – 1%
	return lerpf(0.15, 0.01, credit_rating / 100.0)


func _fire_instability_event(iso: String, _data: Dictionary) -> void:
	if not GameState.is_player_country(iso):
		return
	UIManager.push_notification(
		"Political unrest is spreading. Stability is critically low.",
		"warning", "View", "governance"
	)
	GameClock.request_auto_pause("instability_%s" % iso)
