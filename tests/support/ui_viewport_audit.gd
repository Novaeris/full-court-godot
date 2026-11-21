class_name FcUiViewportAudit
extends RefCounted
## Looks at a screen that is really laid out inside a viewport of a given size and reports what a player would run into:
##   - a control that cannot be reached because it sits outside the window (and is not inside something that scrolls to it),
##   - a control that is too small to tap (touch layouts only),
##   - a scroll area that is wider than the window or hides content sideways where scrolling sideways is switched off,
##   - an open dialog that does not fit the window,
##   - a control the keyboard cannot focus (an enabled button with no focus mode).
## It distinguishes the three things the release plan separates: "builds" (the caller built the screen), "fits" (no clipped control, no
## sideways overflow) and "usable" (also: touch size, a focus style, dialogs inside the window). What a person must still judge (does it look
## right, is it comfortable) is listed in docs/RELEASE_READINESS.md.

const TOLERANCE := 1.5


## Problems found under `root` for a viewport of `view` pixels. Each entry is a plain sentence naming the control.
## `touch` adds the minimum tap size rule. Empty list = the screen fits and is usable by this audit's definition.
static func audit(root: Node, view: Vector2, touch: bool) -> Array[String]:
	var out: Array[String] = []
	var bounds := Rect2(Vector2.ZERO, view)
	_walk(root, bounds, touch, out)
	return out


static func _walk(node: Node, bounds: Rect2, touch: bool, out: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Window and node != node.get_tree().root and (node as Window).visible:
		var wr := Rect2((node as Window).position, (node as Window).size)
		if wr.size.x > bounds.size.x + TOLERANCE or wr.size.y > bounds.size.y + TOLERANCE:
			out.append("dialog %s (%d x %d) is larger than the window" % [node.name, wr.size.x, wr.size.y])
	if node is Control:
		var c := node as Control
		if _interactive(c):
			_check_control(c, bounds, touch, out)
		if c is ScrollContainer:
			_check_scroll(c as ScrollContainer, bounds, out)
	for child in node.get_children():
		_walk(child, bounds, touch, out)


static func _interactive(c: Control) -> bool:
	if not c.is_visible_in_tree() or c.size.x < 1.0 or c.size.y < 1.0:
		return false
	if c is BaseButton:
		return true
	return c is LineEdit or c is TextEdit or c is Range


static func _label_of(c: Control) -> String:
	var text := ""
	if c is Button:
		text = (c as Button).text
	elif c is LineEdit:
		text = (c as LineEdit).placeholder_text
	return "%s '%s'" % [c.get_class(), text if text != "" else str(c.name)]


static func _check_control(c: Control, bounds: Rect2, touch: bool, out: Array[String]) -> void:
	var rect := c.get_global_rect()
	var clipped_by_scroll := _scroll_ancestor(c)
	if clipped_by_scroll == null:
		if rect.position.x < bounds.position.x - TOLERANCE or rect.end.x > bounds.end.x + TOLERANCE \
				or rect.position.y < bounds.position.y - TOLERANCE or rect.end.y > bounds.end.y + TOLERANCE:
			out.append("%s is outside the window (%s in %s)" % [_label_of(c), _fmt(rect), _fmt(bounds)])
	else:
		# inside a scroll area it may be scrolled to, but never sideways when the area cannot scroll sideways
		if clipped_by_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			var area := clipped_by_scroll.get_global_rect()
			if rect.position.x < area.position.x - TOLERANCE or rect.end.x > area.end.x + TOLERANCE:
				out.append("%s sticks out sideways from a scroll area that cannot scroll sideways (%s in %s)" % [_label_of(c), _fmt(rect), _fmt(area)])
	if touch and c is BaseButton and not (c as BaseButton).disabled and c.get_parent() is not ScrollBar:
		var smallest := minf(c.size.x, c.size.y)
		if smallest < FcUiTokens.TOUCH_TARGET - TOLERANCE:
			out.append("%s is %d px tall or wide; a finger needs at least %d (%s)" % [_label_of(c), roundi(smallest), FcUiTokens.TOUCH_TARGET, _fmt(rect)])
	if c is BaseButton and not (c as BaseButton).disabled and c.focus_mode == Control.FOCUS_NONE and not c.has_meta("not_focusable"):
		out.append("%s cannot be reached with the keyboard (focus mode none)" % _label_of(c))


static func _check_scroll(s: ScrollContainer, bounds: Rect2, out: Array[String]) -> void:
	if not s.is_visible_in_tree():
		return
	var rect := s.get_global_rect()
	if rect.end.x > bounds.end.x + TOLERANCE or rect.position.x < bounds.position.x - TOLERANCE:
		out.append("scroll area %s is wider than the window (%s in %s)" % [s.name, _fmt(rect), _fmt(bounds)])


static func _scroll_ancestor(c: Control) -> ScrollContainer:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p as ScrollContainer
		p = p.get_parent()
	return null


static func _fmt(r: Rect2) -> String:
	return "x %d..%d, y %d..%d" % [roundi(r.position.x), roundi(r.end.x), roundi(r.position.y), roundi(r.end.y)]


## True when the theme gives the control types a visible keyboard-focus indicator (a focus style that is not empty).
static func focus_styles_missing(theme: Theme) -> Array[String]:
	var out: Array[String] = []
	for type_name in ["Button", "CheckBox", "OptionButton", "LineEdit", "SpinBox"]:
		var style_name := "focus"
		if not theme.has_stylebox(style_name, type_name):
			out.append("%s has no focus style" % type_name)
		elif theme.get_stylebox(style_name, type_name) is StyleBoxEmpty:
			out.append("%s has an empty focus style (the focus would be invisible)" % type_name)
	return out
