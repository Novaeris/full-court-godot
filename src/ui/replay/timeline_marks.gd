class_name FcTimelineMarks
extends Control
## Ticks under the scrubber (Broadcast pass 2, M4): where the plays worth seeing again are. Highlights are gold, key plays a muted tick and the
## person's bookmarks the info colour; the position is the event's share of the whole game, the same scale as the scrubber. It only draws what
## it is given (FcReplayCollections), never takes the mouse and holds no game state.

const HEIGHT := 14.0

var total: int = 1
var key_indices: Array = []
var highlight_indices: Array = []
var bookmark_indices: Array = []


func _init() -> void:
	name = "TimelineMarks"
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets what to draw: `event_count` is the number of events of the game; each list holds event indices.
func set_marks(event_count: int, keys: Array, highlights: Array, bookmarks: Array) -> void:
	total = maxi(1, event_count)
	key_indices = keys.duplicate()
	highlight_indices = highlights.duplicate()
	bookmark_indices = bookmarks.duplicate()
	queue_redraw()


## How many ticks of each kind are drawn (used by tests).
func mark_counts() -> Dictionary:
	return {"key": key_indices.size(), "highlight": highlight_indices.size(), "bookmark": bookmark_indices.size()}


## The x position (pixels) of event `index` for a bar `width` wide; the ends match a slider's usable range.
static func x_for(index: int, event_count: int, width: float) -> float:
	var span := float(maxi(1, event_count - 1))
	return clampf(float(index) / span, 0.0, 1.0) * width


func _draw() -> void:
	var w := size.x
	for i in key_indices:
		draw_line(Vector2(x_for(int(i), total, w), HEIGHT * 0.55), Vector2(x_for(int(i), total, w), HEIGHT), FcUiTokens.TEXT_DISABLED, 1.0)
	for i in highlight_indices:
		var x := x_for(int(i), total, w)
		draw_line(Vector2(x, 0.0), Vector2(x, HEIGHT), FcUiTokens.GOLD, 2.0)
	for i in bookmark_indices:
		var x := x_for(int(i), total, w)
		draw_circle(Vector2(x, HEIGHT * 0.5), 3.0, FcUiTokens.INFO)
