class_name FcNavigator
extends RefCounted
## Knows which screen is showing and where Back goes. Navigation is hierarchical (as on phones): every screen declares its parent
## when it is shown, so the Escape key, the Android back button and on-screen Back buttons all do the same thing, and no history
## stack can get out of step with the screens. A screen may also hand over a `rebuild` callable, so the shell can show it again
## when the window changes between desktop and mobile layouts.
## Screens that declare nothing (the main menu, most Owner and Career screens today) have no Back target.
##
## Full screens of a mode (the Game Center, the Calendar, a full-page profile, D-077) also use a ROUTE REGISTRY and a BACK STACK: a mode
## registers a builder per screen id (`register`), opens one with `open(id, args)` and leaves with `back_in_stack()`, which rebuilds the
## previous screen with the arguments it had. A stack screen hands `stack_back()` to `enter` as its Back action, so Escape, the Android back
## button and on-screen Back all pop the stack. `last_motion` tells the shell which way to animate ("push", "pop" or "replace").

signal entered(screen_id: String)

const TRAIL_LIMIT := 30
## The deepest the stack may grow; older entries are dropped from the bottom (a long walk through linked screens).
const STACK_LIMIT := 24

var current_id: String = ""
var _back: Callable = Callable()
var _rebuild: Callable = Callable()
var _trail: Array[String] = []
var _routes: Dictionary = {}
var _stack: Array[Dictionary] = []
## How the next screen should arrive: "push" (deeper, slides in from the right), "pop" (back, from the left) or "replace" (a fade).
var last_motion: String = "replace"


## A screen is now showing. Returns true when it is a different screen from the last one (the shell animates only then, so a
## screen that rebuilds itself after an action does not flash).
func enter(screen_id: String, back: Callable = Callable(), rebuild: Callable = Callable()) -> bool:
	var changed := screen_id != current_id
	current_id = screen_id
	_back = back
	_rebuild = rebuild
	if changed:
		_trail.append(screen_id)
		if _trail.size() > TRAIL_LIMIT:
			_trail.pop_front()
		entered.emit(screen_id)
	return changed


func can_go_back() -> bool:
	return _back.is_valid()


## Runs the current screen's Back action. Returns false when there is none.
func go_back() -> bool:
	if not _back.is_valid():
		return false
	_back.call()
	return true


func can_rebuild() -> bool:
	return _rebuild.is_valid()


## Shows the current screen again (after a layout change). Returns false when the screen did not offer a rebuild.
func rebuild() -> bool:
	if not _rebuild.is_valid():
		return false
	_rebuild.call()
	return true


## The screens shown so far, oldest first (the last TRAIL_LIMIT).
func trail() -> Array[String]:
	return _trail.duplicate()


# --- route registry and back stack ---------------------------------------------------------------------------------------

## Registers how to build a full screen: `builder` is Callable(args: Dictionary). Registering an id again replaces its builder.
func register(screen_id: String, builder: Callable) -> void:
	_routes[screen_id] = builder


func has_route(screen_id: String) -> bool:
	return _routes.has(screen_id)


## Starts a new stack at a root screen (the mode's home: the Owner dashboard, the Career hub). Builds nothing: the caller is already
## showing that screen.
func set_root(screen_id: String, args: Dictionary = {}) -> void:
	_stack.clear()
	_stack.append({"id": screen_id, "args": args.duplicate()})


## Opens a registered screen one level deeper. Returns false (and changes nothing) when the id has no route. Opening the screen that is
## already on top with the same arguments only rebuilds it.
func open(screen_id: String, args: Dictionary = {}) -> bool:
	if not _routes.has(screen_id):
		return false
	if not _stack.is_empty() and _stack[-1]["id"] == screen_id and _stack[-1]["args"] == args:
		last_motion = "replace"
	else:
		_stack.append({"id": screen_id, "args": args.duplicate()})
		if _stack.size() > STACK_LIMIT:
			_stack.pop_front()
		last_motion = "push"
	(_routes[screen_id] as Callable).call(args)
	return true


## Replaces the top screen of the stack with another of the same level. Returns false when the id has no route.
func replace(screen_id: String, args: Dictionary = {}) -> bool:
	if not _routes.has(screen_id):
		return false
	if not _stack.is_empty():
		_stack.pop_back()
	_stack.append({"id": screen_id, "args": args.duplicate()})
	last_motion = "replace"
	(_routes[screen_id] as Callable).call(args)
	return true


## Leaves the top screen and rebuilds the one below it with its own arguments. Returns false at the root (nothing to go back to).
func back_in_stack() -> bool:
	if _stack.size() < 2:
		return false
	_stack.pop_back()
	var top: Dictionary = _stack[-1]
	if not _routes.has(top["id"]):
		return false
	last_motion = "pop"
	(_routes[top["id"]] as Callable).call(top["args"])
	return true


## The Back action a stack screen gives `enter` (a Callable, so it fits the existing Back handling).
func stack_back() -> Callable:
	return func() -> void: back_in_stack()


func stack_depth() -> int:
	return _stack.size()


## The ids on the stack, root first (tests and breadcrumbs).
func stack_ids() -> Array[String]:
	var out: Array[String] = []
	for e in _stack:
		out.append(str(e["id"]))
	return out


## The arguments of the screen on top of the stack ({} when the stack is empty).
func top_args() -> Dictionary:
	return _stack[-1]["args"] if not _stack.is_empty() else {}


## Takes the motion for the screen being built and resets it to "replace", so a screen rebuilding itself after an action fades, never slides.
func take_motion() -> String:
	var m := last_motion
	last_motion = "replace"
	return m
