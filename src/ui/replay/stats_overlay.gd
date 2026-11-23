class_name FcStatsOverlay
extends PanelContainer
## The statistics overlay (Broadcast pass 2, M2): a compact team-comparison card drawn over the stage on request. The rows are exactly
## FcBroadcastGraphics.team_card_at (counted from the same events as the box score), limited to the rows named in the identity file. It
## displays; it never takes the mouse and owns no game state.

var _grid := GridContainer.new()
var _title := Label.new()
var _rows: Array = []


func _init() -> void:
	name = "StatsOverlay"
	theme_type_variation = "ScorePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.theme_type_variation = "HeadingLabel"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title)
	_grid.columns = 3
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	_grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
	box.add_child(_grid)
	add_child(box)


## Fills the card from FcBroadcastGraphics.team_card_at(timeline, index). Empty input hides it.
func show_card(card: Dictionary, on: bool) -> void:
	if card.is_empty() or not on:
		visible = false
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_title.text = str(card["title"])
	var wanted := FcBroadcastStyle.stats_rows()
	_rows = []
	var header: Array = ["", str(card["abbreviations"][0]), str(card["abbreviations"][1])]
	_add_row(header, true)
	for row in card["rows"]:
		if wanted.is_empty() or str(row[0]) in wanted:
			_rows.append(row)
			_add_row(row, false)
	visible = true


func _add_row(row: Array, head: bool) -> void:
	for col in 3:
		var l := Label.new()
		l.text = str(row[col])
		l.theme_type_variation = "HeadingLabel" if head else ("CaptionLabel" if col == 0 else "NumericLabel")
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(l)


## The rows shown, as [label, home, away] (used by tests to compare with the box score).
func rows() -> Array:
	return _rows.duplicate()
