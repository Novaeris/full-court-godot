class_name FcPlayerIntroductions
extends RefCounted
## The player introductions before a game (Broadcast pass 2, M5; M7's pregame show builds on it): who is introduced, in what order, with which
## spotlight card and which camera shot. Pure and deterministic. It reads the recorded starters (the five on court at the tip-off, as the lineup
## card does) and the reconstruction's tip-off keyframe for where to point the camera, and invents no facts: the name, number and position are the
## lineup card's. Away starters come first, then the home starters, each in position order.
##
## A step is {side, player_id, name, number, position, spotlight (an FcPlayerSpotlight model with no stat line), shot (a camera shot like the
## director's: a critical closeup with an introduction reason), seconds}.

const SECONDS_PER_PLAYER := 2.4


## The introduction steps for a game ([] for an empty one). `keyframes` may be passed when the caller has already reconstructed the game.
static func plan(timeline: FcBroadcastTimeline, keyframes: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if timeline == null or timeline.is_empty():
		return out
	var model := timeline.model
	var card := FcBroadcastGraphics.lineup_card(timeline)
	if card.is_empty():
		return out
	if keyframes.is_empty():
		keyframes = FcReconstructor.build(timeline)["keyframes"]
	var tip: Dictionary = {}
	for f in keyframes:
		if int(f["event"]) == model.start_index():
			tip = f
			break
	var by_id := {}
	for p in model.box.players:
		by_id[p.player_id] = p
	var numbers := FcJerseyNumbers.for_box(model.box)
	var on_court: Array = model.state_at(model.start_index())["on_court"]
	for side in [1, 0]:   # visitors first
		var ids: Array = (on_court[side] as Array).duplicate()
		ids.sort_custom(func(a: int, b: int) -> bool:
			var pa: int = by_id[a].position if by_id.has(a) else 9
			var pb: int = by_id[b].position if by_id.has(b) else 9
			return pa < pb if pa != pb else a < b)
		for id in ids:
			if not by_id.has(id):
				continue
			var p = by_id[id]
			var number := int(numbers.get(id, 0))
			var at: Vector2 = (tip.get("players", {}) as Dictionary).get(id, Vector2(FcCourtLayout.COURT_LENGTH / 2.0, FcCourtLayout.COURT_WIDTH / 2.0))
			var name := FcPlayByPlay.short_name(p.name)
			var position := FcPosition.abbreviation(p.position)
			var shot := {"preset": FcCameraDirector.PRESET_CLOSEUP, "focus": at, "zoom": 1.8, "hold": SECONDS_PER_PLAYER, "priority": 100,
				"transition": FcCameraDirector.TRANSITION_EASE, "angle": FcCameraDirector.ANGLE_CLOSEUP, "side": 1, "critical": true, "reason": "introduction"}
			out.append({"side": side, "player_id": int(id), "name": name, "number": number, "position": position,
				"spotlight": {"player_id": int(id), "name": name, "number": number, "position": position, "side": side, "stats": [], "kind": "introduction"},
				"shot": shot, "seconds": SECONDS_PER_PLAYER})
	return out


## How long the whole introduction runs.
static func total_seconds(steps: Array) -> float:
	var total := 0.0
	for s in steps:
		total += float(s["seconds"])
	return total
