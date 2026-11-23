class_name FcPresentationEvent
extends RefCounted
## Provenance for everything the broadcast shows (Broadcast pass 2, M2): a record layered OVER the recorded events, never changing them.
## Each presentation event says where it came from, how far it can be trusted, how important it is and what the presentation may do with it.
##
##   source      SIM_RECORDED (a row the simulator wrote), DERIVED_FROM_RECORDED (counted or compared from rows: a run, a milestone, a lead
##               change), RECONSTRUCTED (positions and passes between events), PRESENTATION (a label chosen by the broadcast, such as clutch
##               time, D-069).
##   confidence  EXACT (read straight from a row), DERIVED (computed exactly from rows), APPROXIMATE (an estimate; see FcShotClockModel).
## The rule the tests enforce: only SIM_RECORDED and DERIVED_FROM_RECORDED data with confidence EXACT or DERIVED may be stated as fact in a
## statistic or in commentary (`may_state_as_fact`). Anything reconstructed, presentational or approximate may be drawn but must carry its label.

const SIM_RECORDED := "sim_recorded"
const DERIVED_FROM_RECORDED := "derived_from_recorded"
const RECONSTRUCTED := "reconstructed"
const PRESENTATION := "presentation"
const SOURCES := [SIM_RECORDED, DERIVED_FROM_RECORDED, RECONSTRUCTED, PRESENTATION]

const EXACT := "exact"
const DERIVED := "derived"
const APPROXIMATE := "approximate"
const CONFIDENCES := [EXACT, DERIVED, APPROXIMATE]

## What the presentation can do with an event.
const ACT_OVERLAY := "overlay"
const ACT_SPOTLIGHT := "spotlight"
const ACT_CAPTION := "caption"
const ACT_AUDIO := "audio"
const ACT_CAMERA := "camera"
const ACT_REPLAY := "replay"
const ACT_BOOKMARK := "bookmark"

const _SOURCE_BY_KIND := {
	FcBroadcastGraphics.SCORE: SIM_RECORDED, FcBroadcastGraphics.BLOCK: SIM_RECORDED, FcBroadcastGraphics.TURNOVER: SIM_RECORDED,
	FcBroadcastGraphics.FOUL: SIM_RECORDED, FcBroadcastGraphics.SUBSTITUTION: SIM_RECORDED, FcBroadcastGraphics.INJURY: SIM_RECORDED,
	FcBroadcastGraphics.PERIOD_START: SIM_RECORDED, FcBroadcastGraphics.PERIOD_END: SIM_RECORDED, FcBroadcastGraphics.HALFTIME: SIM_RECORDED,
	FcBroadcastGraphics.FINAL: SIM_RECORDED,
	FcBroadcastGraphics.MILESTONE: DERIVED_FROM_RECORDED, FcBroadcastGraphics.RUN: DERIVED_FROM_RECORDED,
	FcBroadcastGraphics.LEAD_CHANGE: DERIVED_FROM_RECORDED, FcBroadcastGraphics.TIED: DERIVED_FROM_RECORDED,
	FcBroadcastGraphics.BONUS: DERIVED_FROM_RECORDED,
	FcBroadcastGraphics.CLUTCH: PRESENTATION}


## A presentation event for one graphic item of event `index` (an item from FcBroadcastGraphics.items_at).
static func from_item(timeline: FcBroadcastTimeline, index: int, item: Dictionary) -> Dictionary:
	var kind := str(item["kind"])
	var source: String = _SOURCE_BY_KIND.get(kind, PRESENTATION)
	var actions: Array = [ACT_OVERLAY, ACT_CAPTION, ACT_CAMERA]
	if kind in [FcBroadcastGraphics.SCORE, FcBroadcastGraphics.MILESTONE, FcBroadcastGraphics.RUN, FcBroadcastGraphics.LEAD_CHANGE, FcBroadcastGraphics.BLOCK, FcBroadcastGraphics.FINAL]:
		actions.append_array([ACT_AUDIO, ACT_REPLAY, ACT_BOOKMARK])
	if kind in FcBroadcastStyle.spotlight_kinds():
		actions.append(ACT_SPOTLIGHT)
	return {"index": index, "kind": kind, "source": source, "seconds": timeline.seconds_at(index),
		"confidence": EXACT if source == SIM_RECORDED else DERIVED, "importance": int(item["priority"]), "actions": actions, "item": item}


## Every presentation event of event `index`, most important first (the same order as FcBroadcastGraphics.items_at).
static func for_event(timeline: FcBroadcastTimeline, index: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in FcBroadcastGraphics.items_at(timeline, index):
		out.append(from_item(timeline, index, item))
	return out


## Wraps an FcShotClockModel result: derived from the recorded game clock but with an inferred possession start, so approximate.
static func for_shot_clock(timeline: FcBroadcastTimeline, index: int, clock: Dictionary) -> Dictionary:
	return {"index": index, "kind": "shot_clock", "source": DERIVED_FROM_RECORDED, "seconds": timeline.seconds_at(index), "confidence": APPROXIMATE,
		"importance": 0, "actions": [ACT_OVERLAY], "item": clock}


## Whether an event's content may be stated as fact (a statistic, a commentary sentence). Never true for anything approximate or presentational.
static func may_state_as_fact(event: Dictionary) -> bool:
	return str(event.get("source", "")) in [SIM_RECORDED, DERIVED_FROM_RECORDED] and str(event.get("confidence", "")) in [EXACT, DERIVED]
