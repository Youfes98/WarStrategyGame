## EconomySystem.gd
## Autoload singleton — drives monthly economic simulation with full budget cycle.
## GDP → Tax Revenue → Treasury → Spending (Military / Infrastructure / Social / Research).
## Deficit drains treasury; empty treasury increases debt.
extends Node

# ── Tax profiles by government type keyword ──────────────────────────────────
# [base_rate%, min%, max%]  — matched against lowercase government_type
const TAX_PROFILES: Dictionary = {
	"federal presidential":   [22, 12, 35],
	"presidential":           [22, 12, 35],
	"semi-presidential":      [25, 12, 38],
	"federal parliamentary":  [28, 15, 40],
	"parliamentary monarchy": [27, 15, 38],
	"parliamentary":          [28, 15, 40],
	"constitutional monarchy":[27, 15, 38],
	"monarchy":               [20, 10, 40],
	"kingdom":                [20, 10, 40],
	"sultanate":              [15, 8, 35],
	"emirate":                [12, 5, 30],
	"socialist":              [38, 25, 50],
	"people's republic":      [35, 25, 50],
	"islamic republic":       [20, 10, 38],
	"islamic emirate":        [15, 8, 35],
	"federation":             [25, 12, 40],
	"federal republic":       [25, 12, 38],
	"republic":               [25, 12, 38],
	"transitional":           [20, 10, 35],
	"provisional":            [20, 10, 35],
}
const DEFAULT_PROFILE: Array = [25, 10, 45]

# Treasury seed: months of revenue by power tier
const TREASURY_MONTHS: Dictionary = {
	"S": 6, "A": 4, "B": 3, "C": 2, "D": 1,
}


var _budgets_initialized: bool = false


func _ready() -> void:
	GameClock.tick_month.connect(_on_month)
	GameState.player_country_set.connect(func(_iso: String) -> void:
		if not _budgets_initialized:
			init_budgets())


func _on_month(_date: Dictionary) -> void:
	if not _budgets_initialized:
		init_budgets()
	for iso: String in GameState.countries:
		_tick_country(iso)


## Call once per country after data is loaded to seed budget fields.
func init_budgets() -> void:
	if GameState.countries.is_empty():
		return
	for iso: String in GameState.countries:
		_init_budget(iso)
	_budgets_initialized = true


func _init_budget(iso: String) -> void:
	var data: Dictionary = GameState.countries[iso]

	# Skip if already initialised (save-load case)
	if data.has("treasury"):
		return

	var profile: Array = _get_tax_profile(data)
	var tax_rate: float = float(profile[0]) / 100.0
	data["tax_rate"] = tax_rate
	data["tax_min"] = float(profile[1]) / 100.0
	data["tax_max"] = float(profile[2]) / 100.0

	# Default budget allocation (% of discretionary, must sum to 100)
	data["budget_military"] = 20.0
	data["budget_infrastructure"] = 25.0
	data["budget_social"] = 30.0
	data["budget_research"] = 25.0

	# Seed treasury: N months of revenue based on power tier
	var gdp: float = float(data.get("gdp_raw_billions", 1.0))
	var monthly_rev: float = gdp * tax_rate / 12.0
	var tier: String = data.get("power_tier", "C")
	var months: int = TREASURY_MONTHS.get(tier, 2)
	data["treasury"] = monthly_rev * months


func _get_tax_profile(data: Dictionary) -> Array:
	var gov: String = data.get("government_type", "").to_lower()
	# Try longest match first (e.g., "federal presidential republic" → "federal presidential")
	for key: String in TAX_PROFILES:
		if gov.contains(key):
			return TAX_PROFILES[key]
	return DEFAULT_PROFILE


func _tick_country(iso: String) -> void:
	var data: Dictionary = GameState.countries[iso]
	var gdp_raw: float = float(data.get("gdp_raw_billions", 1.0))
	var tax_rate: float = float(data.get("tax_rate", 0.25))
	var treasury: float = float(data.get("treasury", 0.0))
	var stability: float = float(data.get("stability", 50))
	var infra: float = float(data.get("infrastructure", 50))
	var debt_ratio: float = float(data.get("debt_to_gdp", 60))
	var credit: float = float(data.get("credit_rating", 50))

	# ── 1. GDP GROWTH ─────────────────────────────────────────────────────────
	var base_monthly: float = 0.00167   # ~2% annual

	# Stability modifier: -50% at 0, +0% at 50, +30% at 100
	var stab_mod: float = (stability - 50.0) / 50.0 * 0.5

	# Infrastructure modifier: -20% at 0, +20% at 100
	var infra_mod: float = (infra - 50.0) / 50.0 * 0.2

	# Debt drag: above 80% debt/GDP, growth suffers
	var debt_drag: float = 0.0
	if debt_ratio > 80.0:
		debt_drag = -(debt_ratio - 80.0) / 200.0

	# Tax drag: 20% is neutral, higher taxes slow growth, lower taxes boost it
	var tax_drag: float = -(tax_rate * 100.0 - 20.0) / 100.0 * base_monthly

	# Trade deal bonus (player only)
	var trade_bonus: float = 0.0
	if iso == GameState.player_iso:
		for other_iso: String in GameState.countries:
			if other_iso == iso:
				continue
			var rel: Dictionary = GameState.get_relation(iso, other_iso)
			if rel.get("trade_deal", false):
				trade_bonus += 0.5

	var growth: float = base_monthly + stab_mod * base_monthly \
						+ infra_mod * base_monthly + debt_drag + tax_drag
	gdp_raw = maxf(gdp_raw * (1.0 + growth) + trade_bonus, 0.01)
	data["gdp_raw_billions"] = gdp_raw
	data["gdp_normalized"] = _normalize_gdp(gdp_raw)

	# ── 2. BUDGET CYCLE ───────────────────────────────────────────────────────
	var revenue: float = gdp_raw * tax_rate / 12.0

	# Mandatory: debt service
	var interest_rate: float = _interest_rate(credit)
	var debt_service: float = gdp_raw * (debt_ratio / 100.0) * (interest_rate / 12.0)

	# Mandatory: military unit upkeep
	var upkeep: float = MilitarySystem.get_total_upkeep(iso)

	# Net balance
	var balance: float = revenue - debt_service - upkeep
	treasury += balance

	# Budget allocation effects suspended until building system is implemented.
	# Discretionary spending will auto-build via ministerial directives.

	# Deficit handling: if treasury goes negative, increase debt
	if treasury < 0.0:
		var shortfall: float = absf(treasury)
		if gdp_raw > 0.0:
			data["debt_to_gdp"] = clampf(debt_ratio + (shortfall / gdp_raw) * 100.0, 0.0, 500.0)
		treasury = 0.0
	else:
		# Surplus slightly reduces debt ratio (paying down debt)
		if balance > 0.0 and debt_ratio > 0.0 and gdp_raw > 0.0:
			var debt_paydown: float = minf(balance * 0.1, debt_ratio * gdp_raw / 100.0)
			data["debt_to_gdp"] = maxf(debt_ratio - (debt_paydown / gdp_raw) * 100.0, 0.0)

	data["treasury"] = treasury

	# Store computed values for UI
	data["_monthly_revenue"] = revenue
	data["_monthly_debt_service"] = debt_service
	data["_monthly_upkeep"] = upkeep
	data["_monthly_balance"] = balance

	# ── 3. STABILITY DRIFT ────────────────────────────────────────────────────
	var stab_target: float = 60.0 - maxf(0.0, (debt_ratio - 100.0) * 0.1)
	# Tax stability: 25% is neutral; higher taxes reduce stability target
	stab_target -= (tax_rate * 100.0 - 25.0) * 0.1

	stab_target = clampf(stab_target, 20.0, 80.0)
	var new_stab: float = lerpf(stability, stab_target, 0.01)

	if new_stab < 20.0 and randf() < 0.1:
		new_stab -= randf() * 5.0
		_fire_instability_event(iso, data)

	data["stability"] = clampf(new_stab, 0.0, 100.0)

	# ── 4. POPULATION GROWTH ──────────────────────────────────────────────────
	# Real-world annual growth rates vary: ~0.5% (developed) to ~3% (developing)
	# Modifiers: stability, GDP level, war
	var pop: float = float(data.get("population", 100000))
	var base_growth_annual: float = 0.01   # 1% base annual
	# Richer countries grow slower (demographic transition)
	var gdp_per_cap: float = gdp_raw * 1_000_000_000.0 / maxf(pop, 1.0)
	if gdp_per_cap > 30000:
		base_growth_annual = 0.003   # rich: 0.3%
	elif gdp_per_cap > 10000:
		base_growth_annual = 0.007   # middle: 0.7%
	# Low stability = population decline (emigration, conflict deaths)
	var stab_mod_pop: float = (new_stab - 40.0) / 100.0   # -0.4 to +0.6
	# War penalty
	var at_war: bool = false
	for other: String in GameState.countries:
		if GameState.is_at_war(iso, other):
			at_war = true
			break
	var war_mod: float = -0.005 if at_war else 0.0   # -0.5% annual during war

	var monthly_growth: float = (base_growth_annual + stab_mod_pop * 0.005 + war_mod) / 12.0
	var pop_change: float = pop * monthly_growth
	data["population"] = int(maxf(pop + pop_change, 1000))
	data["_pop_monthly_change"] = int(pop_change)

	# Only notify UI for player / selected country
	if iso == GameState.player_iso or iso == GameState.selected_iso:
		GameState.country_data_changed.emit(iso)


func _apply_budget_effects(iso: String, data: Dictionary, discretionary: float) -> void:
	# Infrastructure growth from infrastructure spending
	var infra_pct: float = float(data.get("budget_infrastructure", 25))
	var infra_spend: float = discretionary * infra_pct / 100.0
	var infra: float = float(data.get("infrastructure", 50))
	if infra < 100.0 and infra_spend > 0.01:
		# $1B of infra spending ≈ +0.1 infrastructure per month
		var infra_gain: float = infra_spend * 0.1
		data["infrastructure"] = clampf(infra + infra_gain, 0.0, 100.0)

	# Social spending already affects stability through stab_target (above)
	# Research spending → future tech system placeholder
	# Military spending → available as recruitment pool (checked in MilitarySystem)


## ── Public helpers for UI ────────────────────────────────────────────────────

func get_monthly_revenue(iso: String) -> float:
	var data: Dictionary = GameState.countries.get(iso, {})
	var gdp: float = float(data.get("gdp_raw_billions", 1.0))
	var tax: float = float(data.get("tax_rate", 0.25))
	return gdp * tax / 12.0


func get_monthly_expenses(iso: String) -> float:
	var data: Dictionary = GameState.countries.get(iso, {})
	var gdp: float = float(data.get("gdp_raw_billions", 1.0))
	var debt_ratio: float = float(data.get("debt_to_gdp", 60))
	var credit: float = float(data.get("credit_rating", 50))
	var debt_service: float = gdp * (debt_ratio / 100.0) * (_interest_rate(credit) / 12.0)
	var upkeep: float = MilitarySystem.get_total_upkeep(iso)
	return debt_service + upkeep


func set_tax_rate(iso: String, rate: float) -> void:
	var data: Dictionary = GameState.countries.get(iso, {})
	var mn: float = float(data.get("tax_min", 0.10))
	var mx: float = float(data.get("tax_max", 0.45))
	data["tax_rate"] = clampf(rate, mn, mx)
	GameState.country_data_changed.emit(iso)


func set_budget(iso: String, military: float, infrastructure: float,
		social: float, research: float) -> void:
	var total: float = military + infrastructure + social + research
	if total < 0.01:
		return
	# Normalise to 100
	var data: Dictionary = GameState.countries.get(iso, {})
	data["budget_military"] = military / total * 100.0
	data["budget_infrastructure"] = infrastructure / total * 100.0
	data["budget_social"] = social / total * 100.0
	data["budget_research"] = research / total * 100.0
	GameState.country_data_changed.emit(iso)


## ── Private helpers ──────────────────────────────────────────────────────────

func _normalize_gdp(gdp_billions: float) -> int:
	var log_val: float = log(maxf(gdp_billions, 0.1)) / log(10.0)
	var normalized: float = (log_val + 1.3) / (4.4 + 1.3) * 1000.0
	return int(clampf(normalized, 1.0, 1000.0))


func _interest_rate(credit_rating: float) -> float:
	return lerpf(0.15, 0.01, credit_rating / 100.0)


func _fire_instability_event(iso: String, _data: Dictionary) -> void:
	if not GameState.is_player_country(iso):
		return
	UIManager.push_notification(
		"Political unrest is spreading. Stability is critically low.",
		"warning", "View", "governance"
	)
	GameClock.request_auto_pause("instability_%s" % iso)
