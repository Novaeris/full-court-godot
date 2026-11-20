class_name FcMotion
extends RefCounted
## Animation helpers with one rule built in: reduced motion. When `reduced` is true every movement and scale jumps straight to its
## end state, and fades last at most FcUiTokens.DUR_REDUCED_FADE. Components animate only through here, so one setting
## (the player's "Reduce motion", FcPreferences.reduce_motion) controls every animation in the game.
## Animation is presentation only: callbacks given to these helpers must never change game state.
## A tween needs the node to be in the scene tree; a node outside it simply receives the end state at once.

## Set by FcApp from the preference (and by tests).
static var reduced: bool = false


## How long an animation of `base` seconds lasts: its own length, 0 when reduced, or for fades (`fade` true) at most 80 ms.
static func duration(base: float, fade: bool = false) -> float:
	if not reduced:
		return base
	return minf(base, FcUiTokens.DUR_REDUCED_FADE) if fade else 0.0


## Fades a node in from transparent. Returns the Tween (null when nothing was animated).
static func fade_in(node: CanvasItem, seconds: float = FcUiTokens.DUR_BASE) -> Tween:
	node.modulate.a = 0.0
	return _tween_to(node, "modulate:a", 1.0, duration(seconds, true))


## Fades a node out, then optionally frees it.
static func fade_out(node: CanvasItem, seconds: float = FcUiTokens.DUR_BASE, free_after: bool = false) -> Tween:
	var tw := _tween_to(node, "modulate:a", 0.0, duration(seconds, true))
	if tw != null:
		if free_after:
			tw.finished.connect(node.queue_free)
	elif free_after:
		node.queue_free()
	return tw


## Scales a control up from 85% while fading in (a card, a modal panel, a toast).
static func pop_in(node: Control, seconds: float = FcUiTokens.DUR_BASE) -> Tween:
	node.pivot_offset = node.size / 2.0
	node.modulate.a = 0.0
	var d := duration(seconds)
	if d <= 0.0 or not node.is_inside_tree():
		node.scale = Vector2.ONE
		return _tween_to(node, "modulate:a", 1.0, duration(seconds, true))
	node.scale = Vector2(0.85, 0.85)
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, d)
	return tw


## Slides a freely positioned control (an overlay, not a container child) from an offset to where it is, fading in.
static func slide_in(node: Control, from_offset: Vector2, seconds: float = FcUiTokens.DUR_BASE) -> Tween:
	var target := node.position
	node.modulate.a = 0.0
	var d := duration(seconds)
	if d <= 0.0 or not node.is_inside_tree():
		return _tween_to(node, "modulate:a", 1.0, duration(seconds, true))
	node.position = target + from_offset
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(node, "position", target, d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, d)
	return tw


## The press feedback of a button: shrinks to 97% and springs back.
static func press(node: Control) -> Tween:
	node.pivot_offset = node.size / 2.0
	if duration(1.0) <= 0.0 or not node.is_inside_tree():
		node.scale = Vector2.ONE
		return null
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(0.97, 0.97), FcUiTokens.DUR_FAST * 0.6)
	tw.tween_property(node, "scale", Vector2.ONE, FcUiTokens.DUR_FAST)
	return tw


## Animates any property to a value (jumps there when reduced).
static func tween_property(node: Node, property: String, to: Variant, seconds: float = FcUiTokens.DUR_BASE) -> Tween:
	return _tween_to(node, property, to, duration(seconds))


## Counts a number up in a label (rewards, scores). `format` turns the integer into text; the default is plain digits.
static func count_to(label: Label, from: int, to: int, seconds: float = 0.6, format: Callable = Callable()) -> Tween:
	var show := func(v: float) -> void:
		var n := roundi(v)
		label.text = format.call(n) if format.is_valid() else str(n)
	var d := duration(seconds)
	if d <= 0.0 or not label.is_inside_tree():
		show.call(float(to))
		return null
	var tw := label.create_tween()
	tw.tween_method(show, float(from), float(to), d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


static func _tween_to(node: Node, property: String, to: Variant, seconds: float) -> Tween:
	if seconds <= 0.0 or not node.is_inside_tree():
		node.set_indexed(property, to)
		return null
	var tw := node.create_tween()
	tw.tween_property(node, property, to, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw
