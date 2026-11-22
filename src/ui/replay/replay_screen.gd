class_name FcReplayScreen
extends VBoxContainer
## The game replay: a scoreboard, the court picture (FcCourtView), the sentence for the current event, a clickable play-by-play feed
## and the controls: play and pause, step back and forward, speed, a filter (all plays, key plays, scoring), a jump to each period and
## a scrubber. The same screen serves Owner, Career and Dynasty (they only differ in where the events come from, see FcReplay).
##
## All the decisions live in FcReplayModel; this class draws and plays. `advance(delta)` is what the frame callback calls, so a test can
## play a replay deterministically without waiting for real time. Playing never changes any game data: it only reads the model.

signal event_shown(index: int)

const SPEEDS := [["1", "1x"], ["2", "2x"], ["4", "4x"]]
const FILTERS := [[FcReplayModel.FILTER_ALL, "All plays"], [FcReplayModel.FILTER_KEY, "Key plays"], [FcReplayModel.FILTER_SCORING, "Scoring"]]

var model: FcReplayModel
var timeline: FcBroadcastTimeline   # the running state for the broadcast graphics (derived from the model, read-only)
var colors: Array = [FcUiTokens.INFO, FcUiTokens.PRIMARY]
var filter: String = FcReplayModel.FILTER_ALL
var speed: float = 1.0
var compact: bool = false

var bug: FcScoreBug
var overlay: FcBroadcastOverlay
var team_card: GridContainer   # the team comparison card: label, home, away (FcBroadcastGraphics.team_card_at)
var court: FcCourtView
var caption: Label
var feed: ItemList
var scrubber: HSlider
var play_button: FcButton
var filter_group: FcChoiceGroup
var speed_group: FcChoiceGroup
var period_group: FcChoiceGroup

var _index: int = 0
var _playing: bool = false
var _timer: float = 0.0
var _names: Dictionary = {}
var _feed_indices: Array[int] = []
var _roster_labels: Array = [[], []]   # per side: the five labels listing who is on court
var _roster_heads: Array = [null, null]
var _silent: bool = false


## Builds the screen for `replay_model`. `team_colors` are the home and away colours; `phone` picks the stacked layout.
func setup(replay_model: FcReplayModel, team_colors: Array = [], phone: bool = false) -> FcReplayScreen:
	model = replay_model
	compact = phone
	if team_colors.size() == 2:
		colors = team_colors
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	if model == null or model.is_empty():
		add_child(FcUiTables.label("No replay was kept for this game. Replays are recorded for the games of the team you follow, and only the most recent ones are stored.", FcUiTokens.TYPE_BODY))
		return self
	for p in model.box.players:
		_names[p.player_id] = FcPlayByPlay.short_name(p.name)
	timeline = FcBroadcastTimeline.build(model)
	_build()
	seek(model.start_index(), false)
	return self


func current_index() -> int:
	return _index


func is_playing() -> bool:
	return _playing


# --- building -----------------------------------------------------------------------------------------------------------------

func _build() -> void:
	bug = FcScoreBug.new()
	add_child(bug)
	var body: BoxContainer = VBoxContainer.new() if compact else HBoxContainer.new()
	body.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	court = FcCourtView.new()
	court.colors = colors
	court.custom_minimum_size = Vector2(300 if compact else 520, 170 if compact else 280)
	left.add_child(court)
	overlay = FcBroadcastOverlay.new(colors)   # the broadcast graphic sits over the court's lower edge and never takes the mouse
	overlay.size_flags_horizontal = Control.SIZE_FILL
	court.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, FcUiTokens.SPACE_2)
	overlay.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption = FcUiTables.label("", FcUiTokens.TYPE_H3, true)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.custom_minimum_size.x = 120
	left.add_child(caption)
	left.add_child(_roster_strip())
	left.add_child(_team_card())
	body.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	right.custom_minimum_size = Vector2(0 if compact else 330, 180 if compact else 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filter_group = FcChoiceGroup.new()
	filter_group.set_options(FILTERS, filter)
	filter_group.selected.connect(set_filter)
	right.add_child(filter_group)
	feed = ItemList.new()
	feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed.custom_minimum_size.y = 180
	feed.item_selected.connect(_on_feed_selected)
	feed.resized.connect(func() -> void: feed.ensure_current_is_visible())   # a dialog is laid out over several frames: keep the current play in view
	right.add_child(feed)
	body.add_child(right)
	add_child(_controls())
	_fill_feed()


func _controls() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	row.add_child(FcButton.make("Start", FcButton.Variant.GHOST, func() -> void: seek(model.start_index(), true)))
	row.add_child(FcButton.make("Back", FcButton.Variant.SECONDARY, func() -> void: step(-1)))
	play_button = FcButton.make("Play", FcButton.Variant.PRIMARY, toggle_play)
	row.add_child(play_button)
	row.add_child(FcButton.make("Next", FcButton.Variant.SECONDARY, func() -> void: step(1)))
	row.add_child(FcButton.make("End", FcButton.Variant.GHOST, func() -> void: seek(model.final_index(), true)))
	speed_group = FcChoiceGroup.new()
	speed_group.set_options(SPEEDS, "1")
	speed_group.selected.connect(func(id: String) -> void: set_speed(float(id)))
	row.add_child(speed_group)
	box.add_child(row)
	var periods: Array = []
	for p in model.periods():
		periods.append([str(p), ("Q%d" % p) if p <= model.quarters else ("OT" if p == model.quarters + 1 else "OT%d" % (p - model.quarters))])
	period_group = FcChoiceGroup.new()
	period_group.set_options(periods, "1")
	period_group.selected.connect(func(id: String) -> void: seek(model.period_start_index(int(id)), true))
	box.add_child(period_group)
	scrubber = HSlider.new()
	scrubber.min_value = 0
	scrubber.max_value = maxi(1, model.size() - 1)
	scrubber.step = 1
	scrubber.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrubber.value_changed.connect(func(v: float) -> void:
		if not _silent:
			seek(int(v), false))
	box.add_child(scrubber)
	return box


func _team_card() -> Control:
	var panel := FcPanel.new("Team comparison", FcPanel.Variant.FLAT)
	team_card = GridContainer.new()
	team_card.name = "TeamCard"
	team_card.columns = 3
	team_card.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	team_card.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
	team_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.body.add_child(team_card)
	return panel


func _update_team_card(index: int) -> void:
	var card := FcBroadcastGraphics.team_card_at(timeline, index)
	if card.is_empty():
		return
	for child in team_card.get_children():
		team_card.remove_child(child)
		child.queue_free()
	var cells: Array = [["", str(card["abbreviations"][0]), str(card["abbreviations"][1])]]
	cells.append_array(card["rows"])
	for row in cells:
		for col in 3:
			var l := FcUiTables.label(str(row[col]), FcUiTokens.TYPE_SMALL, row == cells[0])
			l.theme_type_variation = "CaptionLabel" if col == 0 else "NumericLabel"
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if col == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			team_card.add_child(l)


func _roster_strip() -> Control:
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", FcUiTokens.SPACE_4)
	for side in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var head := FcUiTables.label(model.box.abbreviations[side], FcUiTokens.TYPE_SMALL, true)   # plain text colour: a dark team colour is unreadable on this background
		var head_row := HBoxContainer.new()
		head_row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		var swatch := ColorRect.new()   # the team's colour, as drawn on the court
		swatch.color = colors[side]
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head_row.add_child(swatch)
		head_row.add_child(head)
		col.add_child(head_row)
		_roster_heads[side] = head
		for i in 5:
			var l := FcUiTables.label("", FcUiTokens.TYPE_SMALL)
			l.theme_type_variation = "CaptionLabel"
			col.add_child(l)
			_roster_labels[side].append(l)
		grid.add_child(col)
	return grid


func _fill_feed() -> void:
	feed.clear()
	_feed_indices = model.indices_for(filter)
	for i in _feed_indices:
		var e: Dictionary = model.entries[i]
		var text := "%s %s  %s" % [e["clock_text"], str(e["abbr"]), e["text"]]
		if e["points"] > 0:
			text += "  (%d-%d)" % [e["home"], e["away"]]
		feed.add_item(text)


# --- playing ------------------------------------------------------------------------------------------------------------------

## Shows event `i`. `animate` glides the players; stepping and scrubbing pass false for a clean jump when asked.
func seek(i: int, animate: bool = true) -> void:
	if model == null or model.is_empty():
		return
	_index = clampi(i, 0, model.size() - 1)
	_timer = 0.0
	var st := model.state_at(_index)
	court.show_state(st, _names, animate)
	bug.setup(model.box.abbreviations[0], st["home"], model.box.abbreviations[1], st["away"], model.status_at(_index), colors[0], colors[1])
	bug.show_broadcast(timeline.snapshot(_index), model.box.abbreviations[0], model.box.abbreviations[1])
	overlay.show_item(FcBroadcastGraphics.top_item_at(timeline, _index))
	_update_team_card(_index)
	caption.text = "%s  %s" % [st["clock_text"], st["text"]] if st["text"] != "" else st["clock_text"]
	_update_rosters(st)
	_silent = true
	scrubber.value = _index
	period_group.select(str(st["period"]))
	_silent = false
	_select_in_feed()
	event_shown.emit(_index)


func step(direction: int) -> void:
	seek(model.step(_index, direction, filter), true)


func toggle_play() -> void:
	if model == null or model.is_empty():
		return
	if not _playing and _index >= model.final_index():
		seek(model.start_index(), false)   # play again from the tip-off
	_playing = not _playing
	play_button.text = "Pause" if _playing else "Play"
	set_process(_playing)


func set_speed(value: float) -> void:
	speed = clampf(value, 0.5, 8.0)


func set_filter(id: String) -> void:
	filter = id
	filter_group.select(id)
	_fill_feed()
	_select_in_feed()


## One frame of playback: after the current event has been up for its dwell time (shorter at higher speeds) the next one is shown.
## At the end the replay pauses. Called every frame while playing, and directly by tests.
func advance(delta: float) -> void:
	if not _playing or model == null:
		return
	_timer += delta * speed
	if _timer < model.dwell(_index):
		return
	var nxt := model.step(_index, 1, filter)
	if nxt == _index:
		_playing = false
		play_button.text = "Play"
		set_process(false)
		return
	seek(nxt, true)


func _process(delta: float) -> void:
	advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if model == null or model.is_empty() or not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			toggle_play()
		KEY_RIGHT:
			step(1)
		KEY_LEFT:
			step(-1)
		_:
			return
	get_viewport().set_input_as_handled()


func _on_feed_selected(item: int) -> void:
	if item >= 0 and item < _feed_indices.size():
		seek(_feed_indices[item], true)


func _select_in_feed() -> void:
	if feed == null or _feed_indices.is_empty():
		return
	var at := 0
	for k in _feed_indices.size():
		if _feed_indices[k] <= _index:
			at = k
		else:
			break
	feed.deselect_all()
	feed.select(at, false)
	if is_inside_tree():   # after the next frame's layout, or a list that has not been sized yet will not scroll
		get_tree().process_frame.connect(func() -> void:
			if is_instance_valid(feed):
				feed.ensure_current_is_visible(), CONNECT_ONE_SHOT)


func _update_rosters(st: Dictionary) -> void:
	for side in 2:
		var ids: Array = FcCourtLayout.order_by_position(st["on_court"][side], st["positions"])
		for i in 5:
			var label: Label = _roster_labels[side][i]
			if i < ids.size():
				var id: int = ids[i]
				label.text = "%s  %d pts  %d PF" % [_names.get(id, "?"), int(st["points"].get(id, 0)), int(st["fouls"].get(id, 0))]
			else:
				label.text = ""
		(_roster_heads[side] as Label).text = "%s  (team fouls %d)" % [model.box.abbreviations[side], int(st["team_fouls"][side])]
