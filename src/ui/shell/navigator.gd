class_name FcNavigator
extends RefCounted
## Knows which screen is showing and where Back goes. Navigation is hierarchical (as on phones): every screen declares its parent
## when it is shown, so the Escape key, the Android back button and on-screen Back buttons all do the same thing, and no history
## stack can get out of step with the screens. A screen may also hand over a `rebuild` callable, so the shell can show it again
## when the window changes between desktop and mobile layouts.
## Screens that declare nothing (the main menu, most Owner and Career screens today) have no Back target.

signal entered(screen_id: String)

const TRAIL_LIMIT := 30

var current_id: String = ""
var _back: Callable = Callable()
var _rebuild: Callable = Callable()
var _trail: Array[String] = []


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
