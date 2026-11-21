class_name FcLetterhead
extends PanelContainer
## The Franchise header: the team's crest (FcTeamCrest, the same one every other screen shows for that team), the franchise name and a
## subtitle ("Season 3 - General manager"), over an accent rule. Without a team subject it builds one from the abbreviation and colours
## it is given, so it works for any caller.

var name_label := Label.new()
var subtitle_label := Label.new()
var crest := FcTeamCrest.new()


func _init() -> void:
	theme_type_variation = "LetterheadPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	row.add_child(crest)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	name_label.theme_type_variation = "HeadingLabel"
	name_label.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_H1))
	column.add_child(name_label)
	subtitle_label.theme_type_variation = "MutedLabel"
	column.add_child(subtitle_label)


## `primary_hex` and `secondary_hex` are "#RRGGBB" (invalid values fall back to a palette colour and the text colour). `team_subject` (from
## FcTeamLook.subject_for_team) gives the crest the team's full identity; without it the crest is built from the values above.
func setup(franchise_name: String, subtitle: String, abbreviation: String, primary_hex: String, secondary_hex: String, team_subject: Dictionary = {}) -> void:
	name_label.text = franchise_name
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	var subject := team_subject
	if subject.is_empty():
		subject = FcTeamLook.subject("letterhead:%s" % franchise_name, franchise_name, abbreviation, primary_hex, secondary_hex)
	crest.setup(subject, 56)
