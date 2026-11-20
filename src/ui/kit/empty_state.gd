class_name FcEmptyState
extends VBoxContainer
## What to show instead of nothing: an icon, a short title, one sentence saying why and what to do, and optionally one action.
## Kinds: EMPTY (nothing here yet), ERROR (something went wrong), SUCCESS (all done). Every list, table and screen that can be
## empty uses this, so the player is never left looking at a blank area.

enum Kind { EMPTY, ERROR, SUCCESS }

const ICONS := {Kind.EMPTY: "layers", Kind.ERROR: "circle-alert", Kind.SUCCESS: "circle-check"}
const COLORS := {Kind.EMPTY: FcUiTokens.TEXT_MUTED, Kind.ERROR: FcUiTokens.DANGER, Kind.SUCCESS: FcUiTokens.SUCCESS}

var title_label: Label
var body_label: Label
var action_button: FcButton = null


func _init(title: String = "", body: String = "", state_kind: Kind = Kind.EMPTY, icon: String = "", action_text: String = "", on_action: Callable = Callable()) -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	var glyph := FcUiIcons.rect(icon if icon != "" else ICONS[state_kind], COLORS[state_kind], 40)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(glyph)
	title_label = FcUiTables.label(title, FcUiTokens.TYPE_H3, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	body_label = FcUiTables.label(body, FcUiTokens.TYPE_BODY)
	body_label.theme_type_variation = "MutedLabel"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.custom_minimum_size.x = 260
	body_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(body_label)
	if action_text != "":
		action_button = FcButton.make(action_text, FcButton.Variant.PRIMARY, on_action)
		action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(action_button)
