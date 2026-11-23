class_name FcScoreBug
extends PanelContainer
## The broadcast scorebug: both teams' colour stripe, abbreviation and score with a status in the middle ("FINAL", "FINAL/OT",
## "Q3 4:12"). Used on result screens; reads the same everywhere a game score is shown. Colours are the teams' branding
## colours (FcTeamBranding) or any two colours passed in. The winner's score is bright, the loser's muted.
##
## Broadcast mode (master plan B2b): `show_broadcast(snapshot, abbr_a, abbr_b)` adds a second line from an FcBroadcastTimeline snapshot: who has
## the ball, each team's fouls in the period and "in the bonus" for the team that shoots free throws on a foul. `setup` and `summary` are
## unchanged, so every existing screen reads the same.

var _abbr_a := Label.new()
var _abbr_b := Label.new()
var _score_a := Label.new()
var _score_b := Label.new()
var _status := Label.new()
var _stripe_a := ColorRect.new()
var _stripe_b := ColorRect.new()
var _detail := Label.new()
var _crest_a: FcTeamCrest
var _crest_b: FcTeamCrest
var _row: HBoxContainer
var _clock := Label.new()   # the estimated shot clock (FcShotClockModel), shown only when it is worth showing


func _init() -> void:
	theme_type_variation = "ScorePanel"
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# on a phone (touch layout) the bug is compact: the full-size one needs about 340 px and a 360 px phone has 328 px of room
	var compact := FcUiTokens.touch_mode
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", FcUiTokens.SPACE_1)
	add_child(root)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_1 if compact else FcUiTokens.SPACE_3)
	root.add_child(row)
	_row = row
	_detail.name = "BroadcastDetail"
	_detail.theme_type_variation = "CaptionLabel"
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.x = 120
	_detail.visible = false
	root.add_child(_detail)
	_clock.name = "ShotClock"
	_clock.theme_type_variation = "CaptionLabel"
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.visible = false
	root.add_child(_clock)
	_stripe_a.custom_minimum_size = Vector2(6, 0)
	_stripe_b.custom_minimum_size = Vector2(6, 0)
	for l in [_abbr_a, _abbr_b]:
		l.theme_type_variation = "HeadingLabel"
		l.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_BODY if compact else FcUiTokens.TYPE_H2))
	for l in [_score_a, _score_b]:
		l.theme_type_variation = "DisplayLabel"
		l.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_H1 if compact else FcUiTokens.TYPE_DISPLAY))
		l.custom_minimum_size.x = 40 if compact else 56
	_score_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.theme_type_variation = "CaptionLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.x = 48 if compact else 80
	for node in [_stripe_a, _abbr_a, _score_a, _status, _score_b, _abbr_b, _stripe_b]:
		row.add_child(node)


## Sets both sides. `status` is shown between the scores.
func setup(abbr_a: String, score_a: int, abbr_b: String, score_b: int, status: String, color_a: Color = FcUiTokens.INFO, color_b: Color = FcUiTokens.PRIMARY) -> void:
	_abbr_a.text = abbr_a
	_abbr_b.text = abbr_b
	_score_a.text = str(score_a)
	_score_b.text = str(score_b)
	_status.text = status.to_upper()
	_stripe_a.color = color_a
	_stripe_b.color = color_b
	_score_a.add_theme_color_override("font_color", FcUiTokens.TEXT if score_a >= score_b else FcUiTokens.TEXT_MUTED)
	_score_b.add_theme_color_override("font_color", FcUiTokens.TEXT if score_b >= score_a else FcUiTokens.TEXT_MUTED)


## The second line of a broadcast bug from a timeline snapshot: "● AAA  fouls 3  in the bonus   ·   BBB  fouls 2". The dot marks the
## team with the ball; "in the bonus" marks the team that shoots free throws on its opponent's next foul.
func show_broadcast(snapshot: Dictionary, abbr_a: String, abbr_b: String) -> void:
	if snapshot.is_empty():
		_detail.visible = false
		return
	var parts: Array = []
	for side in 2:
		var abbr := abbr_a if side == 0 else abbr_b
		var text := "%s%s  fouls %d" % ["● " if int(snapshot["offense_side"]) == side else "", abbr, int((snapshot["team_fouls"] as Array)[side])]
		if bool((snapshot["bonus_for"] as Array)[side]):
			text += "  in the bonus"
		parts.append(text)
	_detail.text = "   ·   ".join(parts)
	_detail.visible = true


## Puts each team's crest beside its abbreviation (the broadcast scoreboard). `subjects` are FcTeamLook subjects for [home, away]; an empty array
## or a phone layout leaves the bug as it was. Calling it again replaces the crests.
func set_crests(subjects: Array, pixels: int = 28) -> void:
	for c in [_crest_a, _crest_b]:
		if c != null:
			c.queue_free()
	_crest_a = null
	_crest_b = null
	if subjects.size() != 2 or FcUiTokens.touch_mode:
		return
	_crest_a = FcTeamCrest.new().setup(subjects[0], pixels, false)
	_crest_b = FcTeamCrest.new().setup(subjects[1], pixels, false)
	_crest_a.name = "CrestHome"
	_crest_b.name = "CrestAway"
	_row.add_child(_crest_a)
	_row.move_child(_crest_a, _abbr_a.get_index())
	_row.add_child(_crest_b)
	_row.move_child(_crest_b, _abbr_b.get_index() + 1)


func has_crests() -> bool:
	return _crest_a != null and _crest_b != null


## The estimated shot clock line from an FcShotClockModel result: "SHOT CLOCK ≈ 14", hidden when the model says it would mislead. The tooltip
## says it is an estimate, because the game does not enforce a shot clock.
func show_shot_clock(info: Dictionary) -> void:
	if info.is_empty() or not bool(info.get("visible", false)):
		_clock.visible = false
		_clock.text = ""
		return
	_clock.text = "%s %d" % [str(info["label"]), int(info["seconds"])]
	_clock.tooltip_text = FcBroadcastStyle.scoreboard_text("shot_clock_tooltip")
	_clock.visible = true


## The clock line when play is stopped (FcStoppageModel): "PLAY STOPPED · Foul". It takes the shot clock's place, so a hidden estimate
## always has a reason on screen. `info` is an FcStoppageModel result.
func show_stoppage(info: Dictionary) -> void:
	if _clock.visible or info.is_empty() or not bool(info.get("active", false)):
		return
	_clock.text = "PLAY STOPPED · %s" % str(info["text"])
	_clock.tooltip_text = ""
	_clock.visible = true


## The shot clock line as text ("" when hidden), for tests and screen readers.
func shot_clock_text() -> String:
	return _clock.text if _clock.visible else ""


## The text the bug currently shows (used by tests and screen readers later): "AAA 101 FINAL 99 BBB".
func summary() -> String:
	return "%s %s %s %s %s" % [_abbr_a.text, _score_a.text, _status.text, _score_b.text, _abbr_b.text]
