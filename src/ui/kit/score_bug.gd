class_name FcScoreBug
extends PanelContainer
## The broadcast scorebug: both teams' colour stripe, abbreviation and score with a status in the middle ("FINAL", "FINAL/OT",
## "Q3 4:12"). Used on result screens; reads the same everywhere a game score is shown. Colours are the teams' branding
## colours (FcTeamBranding) or any two colours passed in. The winner's score is bright, the loser's muted.

var _abbr_a := Label.new()
var _abbr_b := Label.new()
var _score_a := Label.new()
var _score_b := Label.new()
var _status := Label.new()
var _stripe_a := ColorRect.new()
var _stripe_b := ColorRect.new()


func _init() -> void:
	theme_type_variation = "ScorePanel"
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# on a phone (touch layout) the bug is compact: the full-size one needs about 340 px and a 360 px phone has 328 px of room
	var compact := FcUiTokens.touch_mode
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_1 if compact else FcUiTokens.SPACE_3)
	add_child(row)
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


## The text the bug currently shows (used by tests and screen readers later): "AAA 101 FINAL 99 BBB".
func summary() -> String:
	return "%s %s %s %s %s" % [_abbr_a.text, _score_a.text, _status.text, _score_b.text, _abbr_b.text]
