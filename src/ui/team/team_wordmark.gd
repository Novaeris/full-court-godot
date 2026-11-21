class_name FcTeamWordmark
extends VBoxContainer
## A team's name as a lockup: the city in small spaced capitals over the nickname in the big condensed display face, with a short rule in
## the team's trim colour. Horizontal use puts the crest beside it (see crest_and_name). The text colours are the UI's own (readable
## on every surface); the team colour appears only in the rule and the crest, so a dark team colour can never make the name unreadable.

var city_label := Label.new()
var nickname_label := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", 0)
	city_label.theme_type_variation = "CaptionLabel"
	nickname_label.theme_type_variation = "DisplayLabel"
	add_child(city_label)
	add_child(nickname_label)


## `team_look` from FcTeamLook.resolve; `nickname_px` is a design size (it follows the player's text-size setting).
func setup(team_look: Dictionary, nickname_px: int = FcUiTokens.TYPE_H1) -> FcTeamWordmark:
	var city := str(team_look.get("city", "")).to_upper()
	city_label.text = city
	city_label.visible = city != ""
	city_label.add_theme_font_size_override("font_size", FcUiTokens.fs(maxi(FcUiTokens.TYPE_MICRO, roundi(nickname_px * 0.42))))
	nickname_label.text = str(team_look.get("nickname", team_look.get("abbreviation", "")))
	nickname_label.add_theme_font_size_override("font_size", FcUiTokens.fs(nickname_px))
	var rule := ColorRect.new()
	rule.color = team_look["trim"]
	rule.custom_minimum_size = Vector2(36, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)
	return self


## A crest with the wordmark beside it, as a row.
static func crest_and_name(team_look: Dictionary, crest_px: int = 48, nickname_px: int = FcUiTokens.TYPE_H2) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	row.add_child(FcTeamCrest.new().setup(team_look, crest_px))
	var mark := FcTeamWordmark.new().setup(team_look, nickname_px)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	return row
