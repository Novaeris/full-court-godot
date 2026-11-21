class_name FcTableRow
extends Control
## One line of an FcTable: it draws its own background (zebra, hover, selected, header) and holds the cell controls that the table
## positions. Rows are pooled and rebound as the table scrolls, so a table of 1,000 rows only ever builds about 20 of these.
## It ignores the mouse: the table body reads clicks and hovering, so a row never swallows a wheel or touch scroll.

var cells: Array = []
var display_index: int = -1
var is_header: bool = false
var is_alt: bool = false
var is_selected: bool = false
var is_hovered: bool = false
## True on the selected row while the table has keyboard focus: the row shows a focus outline.
var show_focus: bool = false


func _init(header: bool = false) -> void:
	is_header = header
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not header else Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if is_header:
		draw_rect(r, FcUiTokens.SURFACE_RAISED)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), FcUiTokens.BORDER)
		return
	if is_alt:
		draw_rect(r, Color(1, 1, 1, 0.025))
	if is_hovered:
		draw_rect(r, FcUiTokens.SURFACE_HIGH)
	if is_selected:
		var accent := FcUiTheme.accent
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.16))
		draw_rect(Rect2(0, 0, 3, size.y), accent)
		if show_focus:
			draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), accent, false, 2.0)
	draw_rect(Rect2(0, size.y - 1, size.x, 1), Color(FcUiTokens.BORDER.r, FcUiTokens.BORDER.g, FcUiTokens.BORDER.b, 0.45))


## Sets the three look flags and redraws only when something changed.
func set_look(alt: bool, selected: bool, hovered: bool, focus: bool) -> void:
	if alt == is_alt and selected == is_selected and hovered == is_hovered and focus == show_focus:
		return
	is_alt = alt
	is_selected = selected
	is_hovered = hovered
	show_focus = focus
	queue_redraw()
