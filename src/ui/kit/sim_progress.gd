class_name FcSimProgress
extends PanelContainer
## The panel shown while the season clock runs several days (Fast speed): the target ("Simulating to 2027-01-15"), a progress bar with
## "Day 12 of 30" and the current date, a short ticker of the latest real results, and a Stop button. When the clock pauses on its own it
## shows why ("Your game against Dallas"). It only displays what the clock reports; `stop_requested` asks the clock to stop at the next day
## boundary (a day is never cut in half, D-077 B).

signal stop_requested

const TICKER_LINES := 4

var _title := Label.new()
var _bar := ProgressBar.new()
var _count := Label.new()
var _ticker := VBoxContainer.new()
var _reason := Label.new()
var _stop: FcButton
var _lines: Array[String] = []


func _init() -> void:
	theme_type_variation = "RaisedPanel"
	custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	add_child(box)
	_title.theme_type_variation = "HeadingLabel"
	box.add_child(_title)
	_bar.min_value = 0
	_bar.max_value = 1
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	box.add_child(_bar)
	_count.theme_type_variation = "NumericLabel"
	box.add_child(_count)
	_ticker.add_theme_constant_override("separation", 2)
	box.add_child(_ticker)
	_reason.theme_type_variation = "MutedLabel"
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.visible = false
	box.add_child(_reason)
	_stop = FcButton.make("Stop", FcButton.Variant.SECONDARY, func() -> void: stop_requested.emit())
	_stop.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_stop)


func start(title: String, total_days: int) -> void:
	_title.text = title
	_bar.max_value = maxi(1, total_days)
	_bar.value = 0
	_lines.clear()
	_refresh_ticker()
	_reason.visible = false
	_stop.disabled = false
	_count.text = "Starting"


## One processed day: how many are done, the date reached, and the day's headline results (real, from the clock's report).
func advance(done: int, date_iso: String, results: Array = []) -> void:
	_bar.value = done
	_count.text = "Day %d of %d   ·   %s" % [done, int(_bar.max_value), date_iso]
	for r in results:
		_lines.push_front(str(r))
	while _lines.size() > TICKER_LINES:
		_lines.pop_back()
	_refresh_ticker()


## The run is over: `reason` says why it stopped early ("" when it reached its target).
func finish(reason: String = "") -> void:
	_stop.disabled = true
	_reason.text = reason
	_reason.visible = reason != ""


func progress() -> float:
	return _bar.value / _bar.max_value


func count_text() -> String:
	return _count.text


func ticker() -> Array[String]:
	return _lines.duplicate()


func _refresh_ticker() -> void:
	for c in _ticker.get_children():
		_ticker.remove_child(c)
		c.queue_free()
	for line in _lines:
		var l := Label.new()
		l.text = line
		l.theme_type_variation = "CaptionLabel"
		l.clip_text = true
		_ticker.add_child(l)
