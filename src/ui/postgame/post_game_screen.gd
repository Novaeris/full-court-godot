class_name FcPostGameScreen
extends VBoxContainer
## The one post-game screen for every mode (Broadcast personality): results first. The final score and who won, the quarter-by-quarter
## line score, the player of the game (a labelled display pick), the top performers, a team comparison, what the game means for the
## season, anything earned, and the full player lines of both teams in tabs. It shows an FcPostGameModel view-model and nothing else,
## so it cannot change a game, a save or a player. Callers add their own button (Continue, Play again) under it.

signal team_tab_changed(side: int)

var vm: Dictionary = {}
var bug: FcScoreBug
var bars: Array[FcStatBar] = []
var tabs := FcTabBar.new()
var _tables := VBoxContainer.new()
var _colors: Array = [FcUiTokens.INFO, FcUiTokens.PRIMARY]


## `team_colors` are the two sides' colours (side 0 then side 1); by default the neutral info and primary colours.
func setup(view_model: Dictionary, team_colors: Array = []) -> FcPostGameScreen:
	vm = view_model
	if team_colors.size() == 2:
		_colors = team_colors
	add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(_hero())
	add_child(_line_score())
	if not (vm["pog"] as Dictionary).is_empty():
		add_child(_player_of_the_game())
	if not (vm["implications"] as Array).is_empty() or not (vm["rewards"] as Array).is_empty():
		add_child(_after_game())
	if not (vm["performers"] as Array).is_empty():
		add_child(_performers())
	add_child(_comparison())
	add_child(_player_tabs())
	return self


func _ready() -> void:
	for b in bars:
		b.animate_in()
	if str(vm["result"]) == "win":
		FcAudio.cue("game_win")
	elif str(vm["result"]) == "loss":
		FcAudio.cue("game_loss")


# --- the result ----------------------------------------------------------------------------------------------------------------

func _hero() -> Control:
	var panel := FcPanel.new("", FcPanel.Variant.RAISED)
	var result := str(vm["result"])
	var accent := FcUiTokens.SUCCESS if result == "win" else (FcUiTokens.DANGER if result == "loss" else FcUiTokens.INFO)
	panel.set_accent(accent)
	var sides: Array = vm["sides"]
	bug = FcScoreBug.new()
	bug.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bug.setup(str(sides[0]["abbr"]), int(sides[0]["score"]), str(sides[1]["abbr"]), int(sides[1]["score"]), str(vm["status"]), _colors[0], _colors[1])
	panel.body.add_child(bug)
	var head := FcUiTables.label(str(vm["headline"]), FcUiTokens.TYPE_H2, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_color_override("font_color", accent)
	panel.body.add_child(head)
	return panel


func _line_score() -> Control:
	var line: Dictionary = vm["line_score"]
	var columns: Array = line["columns"]
	var grid := GridContainer.new()
	grid.columns = columns.size()
	grid.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	grid.add_theme_constant_override("v_separation", FcUiTokens.SPACE_1)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for c in columns:
		grid.add_child(_cell(str(c), true, false))
	for row in line["rows"]:
		for i in (row as Array).size():
			grid.add_child(_cell(str(row[i]), false, i == 0 or i == (row as Array).size() - 1))
	var panel := FcPanel.new("Line score", FcPanel.Variant.FLAT)
	panel.body.add_child(grid)
	return panel


func _cell(text: String, caption: bool, strong: bool) -> Label:
	var l := FcUiTables.label(text, FcUiTokens.TYPE_SMALL if caption else FcUiTokens.TYPE_BODY, strong)
	l.theme_type_variation = "CaptionLabel" if caption else "NumericLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 36
	return l


# --- people --------------------------------------------------------------------------------------------------------------------

func _player_of_the_game() -> Control:
	var pog: Dictionary = vm["pog"]
	var panel := FcPanel.new(str(pog["label"]), FcPanel.Variant.RAISED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	var portrait := FcPlayerPortrait.new().setup(pog["subject"], 72)
	row.add_child(portrait)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(_wrapped(str(pog["name"]), FcUiTokens.TYPE_H2, true))
	words.add_child(_wrapped(str(pog["line"])))   # a long stat line wraps instead of making the panel wider than a 360 px phone
	var note := FcUiTables.label(str(pog["note"]), FcUiTokens.TYPE_SMALL)
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 120
	words.add_child(note)
	row.add_child(words)
	panel.body.add_child(row)
	return panel


func _performers() -> Control:
	var panel := FcPanel.new("Top performers", FcPanel.Variant.SURFACE)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
	flow.add_theme_constant_override("v_separation", FcUiTokens.SPACE_2)
	for e in vm["performers"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		row.add_child(FcPlayerPortrait.new().setup(e["subject"], 44))
		var words := VBoxContainer.new()
		words.add_child(_wrapped(str(e["name"]), FcUiTokens.TYPE_BODY, true))
		var line := _wrapped("%s  (%s)" % [e["line"], vm["sides"][int(e["side"])]["abbr"]], FcUiTokens.TYPE_SMALL)
		line.theme_type_variation = "MutedLabel"
		words.add_child(line)
		row.add_child(words)
		flow.add_child(row)
	panel.body.add_child(flow)
	return panel


# --- the rest ------------------------------------------------------------------------------------------------------------------

func _after_game() -> Control:
	var panel := FcPanel.new("After the game", FcPanel.Variant.SURFACE)
	for text in vm["implications"]:
		panel.body.add_child(_wrapped(str(text)))
	for text in vm["rewards"]:
		var earned := _wrapped("Earned: %s" % str(text))
		earned.add_theme_color_override("font_color", FcUiTokens.SUCCESS)
		panel.body.add_child(earned)
	return panel


func _wrapped(text: String, type_size: int = FcUiTokens.TYPE_BODY, bold: bool = false) -> Label:
	var l := FcUiTables.label(text, type_size, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


func _comparison() -> Control:
	var sides: Array = vm["sides"]
	var panel := FcPanel.new("%s vs %s" % [sides[0]["abbr"], sides[1]["abbr"]], FcPanel.Variant.SURFACE)
	for row in vm["comparison"]:
		var bar := FcStatBar.new(str(row["label"]), float(row["left"]), float(row["right"]), str(row["left_text"]), str(row["right_text"]), bool(row["lower_is_better"]))
		bar.left_color = _colors[0]
		bar.right_color = _colors[1]
		bars.append(bar)
		panel.body.add_child(bar)
	return panel


func _player_tabs() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var list: Array = []
	for t in vm["tables"]:
		list.append([str(int(t["side"])), str(t["abbr"])])
	tabs.set_tabs(list)
	tabs.tab_selected.connect(show_team)
	box.add_child(tabs)
	_tables.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	box.add_child(_tables)
	show_team(maxi(0, int(vm["user_side"])))
	return box


## Shows one team's full player lines (side 0 is the home team).
func show_team(side: Variant) -> void:
	var index := int(side)
	for c in _tables.get_children():
		_tables.remove_child(c)
		c.queue_free()
	tabs.select(str(index))
	var t: Dictionary = vm["tables"][index]
	_tables.add_child(FcUiTables.label(str(t["name"]), FcUiTokens.TYPE_H3, true))
	_tables.add_child(FcDataTable.build(t["columns"], t["rows"], [0, 44, 56, 44, 44, 44, 44, 44, 44, 56, 56, 56, 48], {"min_height": 200}))
	team_tab_changed.emit(index)
