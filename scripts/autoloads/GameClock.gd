## GameClock.gd
## Autoload singleton — drives the entire simulation.
## All systems subscribe to tick signals. Nothing polls time directly.
extends Node

signal tick_hour(date: Dictionary)
signal tick_day(date: Dictionary)
signal tick_week(date: Dictionary)
signal tick_month(date: Dictionary)
signal tick_year(date: Dictionary)
signal speed_changed(new_speed: int)
signal pause_changed(is_paused: bool)

# In-game hours emitted per real second at each speed level
const SPEED_TABLE: Array[float] = [0.0, 1.0, 3.0, 12.0, 48.0, 168.0]
const SPEED_LABELS: Array[String] = ["||", "1x", "2x", "3x", "4x", "5x"]

const HOURS_PER_DAY:   int = 24
const DAYS_PER_MONTH:  int = 30
const MONTHS_PER_YEAR: int = 12

var speed: int = 1 : set = set_speed
var paused: bool = false : set = set_paused

var date: Dictionary = {
	"year":  2026,
	"month": 1,
	"day":   1,
	"hour":  0
}

var _hour_accum: float = 0.0

# Auto-pause triggers — set by other systems
var _auto_pause_flags: Array[String] = []


func _process(delta: float) -> void:
	if paused or speed == 0:
		return
	# Cap delta to 100ms so a frame spike can't cause a runaway catch-up loop.
	_hour_accum += minf(delta, 0.1) * SPEED_TABLE[speed]
	while _hour_accum >= 1.0:
		_hour_accum -= 1.0
		_advance_hour()


func _advance_hour() -> void:
	emit_signal("tick_hour", date)
	date.hour += 1

	if date.hour >= HOURS_PER_DAY:
		date.hour = 0
		date.day += 1
		emit_signal("tick_day", date)

		if date.day % 7 == 0:
			emit_signal("tick_week", date)

		if date.day > DAYS_PER_MONTH:
			date.day = 1
			date.month += 1
			if date.month > MONTHS_PER_YEAR:
				date.month = 1
				date.year += 1
				emit_signal("tick_month", date)
				emit_signal("tick_year", date)
			else:
				emit_signal("tick_month", date)


func set_speed(value: int) -> void:
	speed = clampi(value, 0, SPEED_TABLE.size() - 1)
	emit_signal("speed_changed", speed)


func set_paused(value: bool) -> void:
	paused = value
	emit_signal("pause_changed", paused)


func toggle_pause() -> void:
	set_paused(!paused)


## Register an auto-pause reason. Game pauses and shows a toast.
func request_auto_pause(reason: String) -> void:
	if reason not in _auto_pause_flags:   # prevent stacking the same reason
		_auto_pause_flags.append(reason)
	set_paused(true)


## Release an auto-pause reason. Resumes if no others remain.
func release_auto_pause(reason: String) -> void:
	_auto_pause_flags.erase(reason)
	if _auto_pause_flags.is_empty():
		set_paused(false)


func get_date_string() -> String:
	const MONTHS: Array[String] = [
		"", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
	]
	return "%s %d, %d" % [MONTHS[date.month], date.day, date.year]


func get_speed_label() -> String:
	return SPEED_LABELS[speed]
