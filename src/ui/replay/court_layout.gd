class_name FcCourtLayout
extends RefCounted
## Where things are drawn on the replay court. The simulation has NO spatial model, so these are illustrative spots, not tracked
## positions: a made three is drawn from beyond the arc, a rim finish near the basket, and so on. Every spot comes from the event
## kind plus a hash of the event (never the random generator), so the same replay always draws the same picture.
##
## Units are feet on a 94 x 50 foot court, x along the length, y across. Pure maths: no nodes, so it can be tested without a window.

const COURT_LENGTH := 94.0
const COURT_WIDTH := 50.0
const BASKET_FROM_BASELINE := 5.25
const THREE_POINT_DISTANCE := 23.75
const CORNER_THREE_DISTANCE := 22.0

## Offense spots as [distance from the basket in feet, angle in radians from the line to centre court], in position order
## (point guard, shooting guard, small forward, power forward, center).
const OFFENSE_SLOTS := [[26.0, 0.0], [24.5, 0.75], [24.5, -0.75], [14.0, 0.5], [6.5, -0.45]]


## The basket a team attacks, in feet.
static func basket(attacks_right: bool) -> Vector2:
	return Vector2(COURT_LENGTH - BASKET_FROM_BASELINE if attacks_right else BASKET_FROM_BASELINE, COURT_WIDTH / 2.0)


## Which way the offense shoots. The home team attacks the right basket in the first half; ends switch for the third and fourth quarter.
static func attacks_right(offense_side: int, period: int) -> bool:
	var right := offense_side == 0
	if period == 3 or period == 4:
		right = not right
	return right


## A steady number from 0 to 1 for (key, salt): the stand-in for randomness in a picture.
static func unit(key: int, salt: int) -> float:
	return float(absi(hash("%d:%d" % [key, salt])) % 10000) / 10000.0


## Where a shot of `kind` (FcGameEventLog.SHOT_*) is taken from, for the basket the offense attacks.
static func shot_spot(kind: int, key: int, attacks_right_flag: bool) -> Vector2:
	var angle := lerpf(-1.1, 1.1, unit(key, 1))
	var spread := unit(key, 2)
	var distance: float
	match kind:
		FcGameEventLog.SHOT_THREE:
			distance = THREE_POINT_DISTANCE + 0.8 + 2.5 * spread
		FcGameEventLog.SHOT_MID:
			distance = 11.0 + 8.0 * spread
		_:
			distance = 1.5 + 2.5 * spread
	return _from_basket(attacks_right_flag, distance, angle)


## The five offensive spots (position order) and the five defenders, each between his man and the basket.
static func formation(attacks_right_flag: bool) -> Dictionary:
	var offense: Array[Vector2] = []
	var defense: Array[Vector2] = []
	var hoop := basket(attacks_right_flag)
	for slot in OFFENSE_SLOTS:
		var spot := _from_basket(attacks_right_flag, float(slot[0]), float(slot[1]))
		offense.append(spot)
		defense.append(spot.lerp(hoop, 0.32) + Vector2(0.0, 1.2))
	return {"offense": offense, "defense": defense}


## Players of one side in slot order: by position (PG first, C last), ties by id so the order never changes during a replay.
static func order_by_position(ids: Array, positions: Dictionary) -> Array:
	var list: Array = ids.duplicate()
	list.sort_custom(func(a, b) -> bool:
		var pa := int(positions.get(a, 3))
		var pb := int(positions.get(b, 3))
		return pa < pb if pa != pb else int(a) < int(b))
	return list


static func inside_court(spot: Vector2, margin: float = 0.0) -> bool:
	return spot.x >= margin and spot.x <= COURT_LENGTH - margin and spot.y >= margin and spot.y <= COURT_WIDTH - margin


static func _from_basket(attacks_right_flag: bool, distance: float, angle: float) -> Vector2:
	var hoop := basket(attacks_right_flag)
	var axis := Vector2(-1.0 if attacks_right_flag else 1.0, 0.0)
	var spot := hoop + axis.rotated(angle) * distance
	return Vector2(clampf(spot.x, 1.0, COURT_LENGTH - 1.0), clampf(spot.y, 1.5, COURT_WIDTH - 1.5))
