class_name FcReplayTools
extends VBoxContainer
## The replay-review tools of the Replay mode (Broadcast pass 2, M4): the replay-time readout, a bookmark button with previous and next mark,
## the highlight reel and the replay-angle picker. It builds controls and emits signals; FcReplayScreen owns the playback state and does the
## work. Everything here is about FcReplayReference: a replay is the reconstruction re-run over recorded events, never recorded video.

signal bookmark_pressed
signal mark_jump(direction: int)
signal reel_pressed
signal intro_pressed
signal angle_chosen(id: String)

const ANGLES := [["auto", "Auto"], ["0", "Main"], ["1", "Baseline"], ["2", "Overhead"]]

var time_label: Label
var bookmark_button: Button
var prev_mark: Button
var next_mark: Button
var reel_button: Button
var intro_button: Button
var reel_note: Label
var angle_group: FcChoiceGroup
var wording: Label


func _init() -> void:
	name = "ReplayTools"
	add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	time_label = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	time_label.name = "ReplayTime"
	time_label.theme_type_variation = "MutedLabel"
	add_child(time_label)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	bookmark_button = FcButton.make("Bookmark this play", FcButton.Variant.SECONDARY, func() -> void: bookmark_pressed.emit())
	bookmark_button.name = "BookmarkButton"
	prev_mark = FcButton.make("Previous mark", FcButton.Variant.GHOST, func() -> void: mark_jump.emit(-1))
	next_mark = FcButton.make("Next mark", FcButton.Variant.GHOST, func() -> void: mark_jump.emit(1))
	reel_button = FcButton.make("Highlight reel", FcButton.Variant.PRIMARY, func() -> void: reel_pressed.emit())
	reel_button.name = "ReelButton"
	intro_button = FcButton.make("Player introductions", FcButton.Variant.SECONDARY, func() -> void: intro_pressed.emit())
	intro_button.name = "IntroButton"
	for b in [bookmark_button, prev_mark, next_mark, reel_button, intro_button]:
		row.add_child(b)
	add_child(row)
	reel_note = FcUiTables.label("", FcUiTokens.TYPE_SMALL)
	reel_note.theme_type_variation = "MutedLabel"
	reel_note.name = "ReelNote"
	reel_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reel_note.custom_minimum_size.x = 120
	add_child(reel_note)
	var angles := HFlowContainer.new()
	angles.add_theme_constant_override("h_separation", FcUiTokens.SPACE_2)
	var label := FcUiTables.label("Replay angle:", FcUiTokens.TYPE_SMALL)
	label.theme_type_variation = "MutedLabel"
	angles.add_child(label)
	angle_group = FcChoiceGroup.new()
	angle_group.set_options(ANGLES, "auto")
	angle_group.selected.connect(func(id: String) -> void: angle_chosen.emit(id))
	angles.add_child(angle_group)
	add_child(angles)
	wording = FcUiTables.label(FcReplayReference.REPLAY_WORDING, FcUiTokens.TYPE_MICRO)
	wording.theme_type_variation = "MutedLabel"
	wording.name = "ReplayWording"
	wording.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wording.custom_minimum_size.x = 120
	add_child(wording)


## "Replay time 1:23 of 12:10": the time the replay has been showing at normal speed (the replay's own axis, not the game clock).
func show_time(seconds: float, total_seconds: float) -> void:
	time_label.text = "Replay time %s of %s" % [clock(seconds), clock(total_seconds)]


## "m:ss" for a number of seconds.
static func clock(seconds: float) -> String:
	var s := maxi(0, int(round(seconds)))
	return "%d:%02d" % [floori(s / 60.0), s % 60]
