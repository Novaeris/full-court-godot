class_name FcBallMotion
extends RefCounted
## The pure maths of how the 3D ball moves (3D overhaul M3): a dribble that bounces between the hand and the floor in time with the arm, a pass or shot
## that flies in an arc, and the spin that goes with each. No nodes, so every rule is unit-tested without a window. Presentation only: where the ball
## is at an event comes from the reconstruction and never changes a game; this only decides how it travels between two known places.

const RADIUS := 0.39            # feet: a size 7 ball is 9.4 inches across
const GRAVITY := 32.2           # feet per second squared
const MAX_ARC := 9.0            # feet: no pass or shot is drawn with a higher arc than this


## Where in its bounce a dribbled ball is, from the character's loop phase: 0 is the ball on the floor, 0.5 at the hand. The ball reaches the hand at
## phases 0.125 and 0.625 of a dribble loop, when the arm of FcBroadcastPose's dribble is fully extended downwards, and bounces twice per loop.
static func dribble_u(loop_phase: float) -> float:
	return fposmod(loop_phase * 2.0 + 0.25, 1.0)


## The height of the CENTRE of a dribbled ball: on the floor at u = 0 (centre one radius up), at the hand at u = 0.5, along a parabola (gravity).
static func dribble_height(u: float, hand_height: float) -> float:
	var top := maxf(hand_height, RADIUS * 2.0)
	return RADIUS + (top - RADIUS) * 4.0 * u * (1.0 - u)


## The height gained by a flight over `distance` feet on top of the straight line (an arc): about a sixth of the distance, between a flat pass and a
## high shot, capped.
static func arc_height(distance: float, lob: bool = false) -> float:
	return minf(distance * (0.28 if lob else 0.12), MAX_ARC)


## The position `s` (0 to 1) of the way along a flight from `start` to `goal`: the straight line plus a parabola, so the ball is highest half way.
static func flight_position(start: Vector3, goal: Vector3, s: float, lob: bool = false) -> Vector3:
	var t := clampf(s, 0.0, 1.0)
	var p := start.lerp(goal, t)
	var height := arc_height(Vector2(goal.x - start.x, goal.z - start.z).length(), lob)
	return p + Vector3(0.0, height * 4.0 * t * (1.0 - t), 0.0)


## How long a flight takes at `speed` feet per second (never zero).
static func flight_seconds(start: Vector3, goal: Vector3, speed: float) -> float:
	return maxf(start.distance_to(goal) / maxf(speed, 0.1), 0.05)


## The spin of the ball as an angular velocity (radians per second), as a vector in world space: a flight spins about the horizontal axis at right
## angles to its direction (backspin on a shot, a rotating pass), a dribble rolls a little, a held ball does not spin.
static func spin_axis_rate(kind: String, direction: Vector3) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.001:
		return Vector3.ZERO
	var across := Vector3.UP.cross(flat.normalized())   # the horizontal axis at right angles to the direction of travel
	match kind:
		"shot":
			return across * -9.0     # backspin: the top of the ball turns back towards the shooter
		"pass":
			return across * -4.0 + Vector3.UP * 3.0
		"dribble":
			return across * -2.0
	return Vector3.ZERO
