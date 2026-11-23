class_name FcReplayCollections
extends RefCounted
## The collections of replay references for a game (Broadcast pass 2, M4): the automatic highlight package, the key plays and the person's own
## bookmarks. Pure: it reads the timeline and a list of bookmarked event indices, and returns FcReplayReference dictionaries. It stores nothing
## (FcBookmarkStore keeps the bookmarks) and invents nothing: every label is the graphic text of the recorded event.

const PACKAGE_COUNT := 6
## The most key plays marked on the timeline (the importance model's top scorers, spaced apart).
const KEY_COUNT := 16
const KEY_GAP := 4


## The automatic highlight package: the best plays in game order as references, and the reel's length at normal speed.
## {"refs": [...], "seconds": float (replay time the reel takes at 1x)}
static func package(timeline: FcBroadcastTimeline, count: int = PACKAGE_COUNT) -> Dictionary:
	var refs: Array[Dictionary] = []
	for h in FcHighlights.select(timeline, count):
		refs.append(FcReplayReference.around(timeline, int(h["index"]), FcReplayReference.AUTO_HIGHLIGHT, str(h["title"]), int(h["importance"])))
	return {"refs": refs, "seconds": reel_seconds(timeline, refs)}


## Key plays: every play the importance model marks, best first within a gap, in game order.
static func key_plays(timeline: FcBroadcastTimeline) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	if timeline == null or timeline.is_empty():
		return refs
	for entry in FcImportanceModel.top(FcImportanceModel.scored(timeline), KEY_COUNT, KEY_GAP):
		refs.append(FcReplayReference.around(timeline, int(entry["index"]), FcReplayReference.KEY_PLAY, str(entry["title"]), int(entry["importance"])))
	return refs


## The person's bookmarks (event indices) as references, in game order. An index outside the game is ignored.
static func bookmarks(timeline: FcBroadcastTimeline, indices: Array) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	if timeline == null or timeline.is_empty():
		return refs
	var sorted: Array = indices.duplicate()
	sorted.sort()
	for i in sorted:
		var index := int(i)
		if index < 0 or index >= timeline.size():
			continue
		var top := FcBroadcastGraphics.top_item_at(timeline, index)
		var label := str(top["title"]) if not top.is_empty() else str(timeline.model.entries[index]["text"])
		refs.append(FcReplayReference.around(timeline, index, FcReplayReference.USER_BOOKMARK, label, int(FcImportanceModel.at(timeline, index).get("importance", 0))))
	return refs


## How long a reel of `refs` runs at normal speed: the replay time of each window.
static func reel_seconds(timeline: FcBroadcastTimeline, refs: Array) -> float:
	var total := 0.0
	for ref in refs:
		for i in range(int(ref["start"]), int(ref["end"]) + 1):
			total += timeline.model.dwell(i)
	return total
