class_name FcStatusChip
extends PanelContainer
## A small pill that states a status ("Injured", "Contract ends", "Ready", "New"). Tones: NEUTRAL, INFO, SUCCESS, WARNING, DANGER.
## The text and outline use the tone colour on a faint fill of the same colour; the words carry the meaning, never colour alone.

enum Tone { NEUTRAL, INFO, SUCCESS, WARNING, DANGER }

const COLORS := {Tone.NEUTRAL: FcUiTokens.TEXT_MUTED, Tone.INFO: FcUiTokens.INFO, Tone.SUCCESS: FcUiTokens.SUCCESS, Tone.WARNING: FcUiTokens.WARNING, Tone.DANGER: FcUiTokens.DANGER}

var tone: Tone = Tone.NEUTRAL
var label_node := Label.new()


func _init(text: String = "", chip_tone: Tone = Tone.NEUTRAL) -> void:
	label_node.text = text
	label_node.theme_type_variation = "CaptionLabel"
	label_node.add_theme_font_size_override("font_size", FcUiTokens.fs(FcUiTokens.TYPE_SMALL - 1))
	add_child(label_node)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	set_tone(chip_tone)


## Changes the tone (and so the colours) of an existing chip; table cells reuse one chip for different results.
func set_tone(chip_tone: Tone) -> void:
	tone = chip_tone
	var color: Color = COLORS[tone]
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.r, color.g, color.b, 0.15)
	box.border_color = color
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	add_theme_stylebox_override("panel", box)
	label_node.add_theme_color_override("font_color", color)


static func make(text: String, chip_tone: Tone = Tone.NEUTRAL) -> FcStatusChip:
	return FcStatusChip.new(text, chip_tone)
