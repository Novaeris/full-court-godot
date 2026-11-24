class_name FcLimbIK
extends RefCounted
## Analytic two-bone inverse kinematics (3D overhaul, M2), pure maths with no nodes: given where a limb starts (a shoulder), how long its two
## segments are, where the end (a wrist) should be and which way the elbow should point, it returns how the first segment must be turned and
## how far the joint bends. Used to put BOTH hands on the ball in a set shot, a rebound or a dunk, instead of hoping a canned arm pose happens to
## meet it. If the target is out of reach the limb stretches straight towards it (never a NaN, never a snapped elbow).
##
## Conventions (they match FcBodyBuilder's rest pose): a limb hangs along -Y; the first segment's local frame has +Y pointing from the end back to the
## start, and the joint bends the second segment towards the frame's +Z (elbow rotation about X by -bend). `solve` returns that frame as a Basis.

## Result: {"basis": Basis (the first joint's rotation relative to its parent), "bend": float (radians, 0 straight), "reach": float (distance the
## end really gets to), "reached": bool}.
static func solve(start: Vector3, upper: float, lower: float, target: Vector3, pole: Vector3) -> Dictionary:
	var to_target := target - start
	var distance := to_target.length()
	var max_reach := (upper + lower) * 0.9999
	var min_reach := absf(upper - lower) * 1.0001 + 0.0001
	var d := clampf(distance, min_reach, max_reach)
	var dir := to_target / distance if distance > 0.00001 else Vector3(0.0, -1.0, 0.0)
	# the direction the elbow sticks out: the pole, with the part along the limb's line removed
	var side := pole - dir * pole.dot(dir)
	if side.length() < 0.0001:
		side = Vector3.BACK - dir * Vector3.BACK.dot(dir)
		if side.length() < 0.0001:
			side = Vector3.RIGHT
	side = side.normalized()
	var cos_elbow := clampf((upper * upper + lower * lower - d * d) / (2.0 * upper * lower), -1.0, 1.0)
	var bend := PI - acos(cos_elbow)
	var cos_shoulder := clampf((upper * upper + d * d - lower * lower) / (2.0 * upper * d), -1.0, 1.0)
	var alpha := acos(cos_shoulder)
	var upper_dir := dir * cos(alpha) + side * sin(alpha)
	var y_axis := -upper_dir
	# the in-plane direction perpendicular to the first segment that points back towards the line to the target (computed directly: projecting
	# -side onto the plane flips its sign when the shoulder angle passes 90 degrees)
	var z_axis := (dir * sin(alpha) - side * cos(alpha)).normalized()
	var x_axis := y_axis.cross(z_axis)
	return {"basis": Basis(x_axis, y_axis, z_axis), "bend": bend, "reach": d, "reached": distance <= max_reach}


## Where the end of the limb ends up for a result of `solve` (for tests: it must equal the target when reachable).
static func end_point(start: Vector3, upper: float, lower: float, result: Dictionary) -> Vector3:
	var basis: Basis = result["basis"]
	var bend: float = result["bend"]
	var elbow := start + basis * Vector3(0.0, -upper, 0.0)
	var forearm := basis * (Basis.from_euler(Vector3(-bend, 0.0, 0.0)) * Vector3(0.0, -lower, 0.0))
	return elbow + forearm
