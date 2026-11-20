class_name FcLetterhead
extends PanelContainer
## The Franchise header: a crest (the team's abbreviation on its colour, until logo art exists), the franchise name and a subtitle
## ("Season 3 - General manager"), over an accent rule. The crest colours are the team's branding (FcTeamBranding) hex strings.

var name_label := Label.new()
var subtitle_label := Label.new()
var _crest := PanelContainer.new()
var _crest_text := Label.new()


func _init() -> void:
	theme_type_variation = "LetterheadPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FcUiTokens.SPACE_3)
	add_child(row)
	_crest.custom_minimum_size = Vector2(52, 52)
	_crest_text.theme_type_variation = "DisplayLabel"
	_crest_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crest_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crest.add_child(_crest_text)
	row.add_child(_crest)
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


## `primary_hex` and `secondary_hex` are "#RRGGBB" (invalid values fall back to the steel and text colours).
func setup(franchise_name: String, subtitle: String, abbreviation: String, primary_hex: String, secondary_hex: String) -> void:
	name_label.text = franchise_name
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	var fill := Color(primary_hex) if FcChecks.is_hex_color(primary_hex) else FcUiTokens.STEEL
	var ink := Color(secondary_hex) if FcChecks.is_hex_color(secondary_hex) else FcUiTokens.TEXT
	# the crest text must stay readable on the crest colour whatever the branding says
	if FcUiContrast.ratio(ink, fill) < 4.5:
		ink = FcUiContrast.readable_on(fill)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(FcUiTokens.RADIUS_PANEL)
	box.set_border_width_all(2)
	box.border_color = ink
	_crest.add_theme_stylebox_override("panel", box)
	_crest_text.text = abbreviation.substr(0, 3).to_upper()
	_crest_text.add_theme_color_override("font_color", ink)
	_crest_text.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_H2))
