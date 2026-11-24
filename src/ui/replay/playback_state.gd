class_name FcPlaybackState
extends RefCounted
## The ONE owner of "where are we in the game and how is it playing" for the replay screen (Broadcast pass 2, M1).
##
## Why it exists: the screen has three presentation modes (FcPresentationMode: Broadcast, Replay, Analysis). Each mode shows a different
## set of panels, but all of them watch the same game, so the position, play/pause, speed, instant replay and camera/view choice live here
## and are only ever READ by a mode's layout. Switching mode never touches this object, which is how "a mode switch never changes the
## replay position" is guaranteed (and tested). Mode-specific UI state (collapsed panels, HUD level) lives in the screen, not here.
## Pure data: no nodes, no randomness, nothing saved.

## The event being shown (an index into FcReplayModel.entries).
var index: int = 0
var playing: bool = false
## Seconds the current event has been up; the screen compares it with FcReplayModel.dwell.
var timer: float = 0.0
var speed: float = 1.0
## An instant replay in progress: {start, end, return_index, speed, was_playing}; {} when live.
var instant: Dictionary = {}
## Which replay angle the next instant replay starts from (0 main, 1 baseline, 2 overhead, then around); it advances each time one starts.
var replay_variant: int = 0
## The highlight reel in progress: {windows [{start, end}], at, return_index, speed, was_playing}; {} when none.
var reel: Dictionary = {}
## The player introductions in progress: {steps, at, timer, return_index, speed, was_playing}; {} when none.
var intro: Dictionary = {}
## A production show in progress (pregame, halftime, postgame, championship): {id, return_index, speed, was_playing}; {} when none.
var show: Dictionary = {}
## The replay angle the person chose: -1 automatic (cycles), or 0 main, 1 baseline, 2 overhead.
var replay_angle: int = -1
## "auto", "hybrid" or "manual" (the camera rig's mode, kept here so a mode switch can restore it).
var camera_mode: String = "hybrid"
## "broadcast3d", "broadcast" or "flat".
var view_id: String = "broadcast"


func is_instant() -> bool:
	return not instant.is_empty()


func is_reel() -> bool:
	return not reel.is_empty()


func is_intro() -> bool:
	return not intro.is_empty()


func is_show() -> bool:
	return not show.is_empty()


## A plain copy of everything, for tests that compare state before and after a mode switch.
func snapshot() -> Array:
	return [index, playing, speed, instant.duplicate(), camera_mode, view_id, replay_variant, reel.duplicate(true), replay_angle, intro.duplicate(true), show.duplicate(true)]
