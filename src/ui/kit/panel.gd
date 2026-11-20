class_name FcPanel
extends PanelContainer
## A surface that groups content. Variants: SURFACE (default), RAISED (lifted, with a soft shadow), FLAT (no border, for nesting),
## MODAL (the dialog surface). It always holds one VBox, `body`: add children there. An optional title becomes a heading row.

enum Variant { SURFACE, RAISED, FLAT, MODAL }

const VARIATIONS := {Variant.SURFACE: "", Variant.RAISED: "RaisedPanel", Variant.FLAT: "FlatPanel", Variant.MODAL: "ModalPanel"}

var body: VBoxContainer
var _title: Label


func _init(title_text: String = "", panel_variant: Variant = Variant.SURFACE) -> void:
	theme_type_variation = VARIATIONS[panel_variant]
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", FcUiTokens.SPACE_2)
	add_child(body)
	if title_text != "":
		set_title(title_text)


func set_title(title_text: String) -> void:
	if _title == null:
		_title = FcUiTables.label(title_text, FcUiTokens.TYPE_H3, true)
		body.add_child(_title)
		body.move_child(_title, 0)
	_title.text = title_text


## Adds a child to the body and returns it (so it can be chained).
func add(child: Control) -> Control:
	body.add_child(child)
	return child
