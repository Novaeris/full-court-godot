class_name FcTeamChip
extends HBoxContainer
## A team in a row or a line of text: its crest and its name (or nickname, or letters). The crest comes from FcTeamLook, so it is the same crest
## as in every header, score bug and table. `you` marks the user's own team with a small tag, so it never depends on colour.

var crest: FcTeamCrest
var name_label: Label
var _tag: FcStatusChip


## `team_look` from FcTeamLook.resolve. `text` is what to show beside the crest. Calling it again updates the chip in place (table rows are rebound).
func setup(team_look: Dictionary, text: String, crest_px: int = 24, you: bool = false, clip: bool = true) -> FcTeamChip:
	if crest == null:
		add_theme_constant_override("separation", FcUiTokens.SPACE_2)
		crest = FcTeamCrest.new()
		crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(crest)
		name_label = FcUiTables.label("", FcUiTokens.TYPE_BODY)
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(name_label)
		_tag = FcStatusChip.make("You", FcStatusChip.Tone.INFO)
		_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_tag)
	crest.setup(team_look, crest_px, false)
	# in a table cell the name is clipped to its column; standing alone it keeps its full width
	name_label.clip_text = clip
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if clip else TextServer.OVERRUN_NO_TRIMMING
	name_label.text = text
	_tag.visible = you
	tooltip_text = text
	return self
