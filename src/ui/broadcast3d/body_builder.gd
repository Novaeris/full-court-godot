class_name FcBodyBuilder
extends RefCounted
## Builds a 3D player (3D overhaul, M1): a real Skeleton3D and ONE skinned ArrayMesh made of smooth lofted shapes, from an FcBodyArchetype, the
## identity (skin, hair, facial hair, face proportions) and the uniform. No imported art: every vertex is computed here, from seeded-free pure
## maths, so the same player is the same mesh every time, offline, with nothing to license.
##
## How it is made (docs/plans/3D_FIDELITY_PLAN.md): a "loft" sweeps an elliptical ring along a path (a torso, a thigh, a neck); an "ellipsoid" is a
## loft of latitude rings (a head, a hair shell, an eye); a "tube" follows a polyline (a finger, a braid). Every ring carries bone weights, so
## the skin bends at the joints. Surfaces (skin, features, hair, jersey, shorts, socks, shoes, soles) each have their own material.
##
## Units are feet (1 unit = 1 ft), the body faces +z, x is the character's left (anatomical), y is up, the rest pose is a straight standing body
## with arms hanging. Bone rest transforms are pure translations, so a bone's pose rotation is exactly the euler angle FcBroadcastPose gives it.

## Bone names in creation order; the parent is the first entry of PARENTS at the same index.
const BONES := ["pelvis", "torso", "neck", "head", "l_shoulder", "l_elbow", "l_hand", "r_shoulder", "r_elbow", "r_hand", "l_hip", "l_knee", "l_foot", "r_hip", "r_knee", "r_foot"]
const PARENTS := ["", "pelvis", "torso", "neck", "torso", "l_shoulder", "l_elbow", "torso", "r_shoulder", "r_elbow", "pelvis", "l_hip", "l_knee", "pelvis", "r_hip", "r_knee"]
const SURFACES := ["skin", "features", "hair", "jersey", "shorts", "socks", "shoes", "sole"]

var archetype: Dictionary = {}
var identity: Dictionary = {}
var uniform: Dictionary = {}
var height_feet: float = 6.5

var _h: float = 6.5
var _rest: Dictionary = {}     # bone name -> Vector3, model-space rest origin
var _index: Dictionary = {}    # bone name -> index
var _surfaces: Dictionary = {} # surface name -> FcMeshSurface
var _skin: Color
var _hair: Color
var _primary: Color
var _short_color: Color   # the colour of shorts, or of the trousers of an official or a coach
var _attire: String = "playing"   # "playing" (the tank top, shorts and socks), "referee" or "suit" (a shirt or jacket with sleeves and long trousers)
var _secondary: Color
var _head: Dictionary = {}     # head frame: centre, rx, ry, rz, chin


func _init() -> void:
	for i in BONES.size():
		_index[BONES[i]] = i
	for name in SURFACES:
		var rough := 0.62
		match name:
			"hair": rough = 0.85
			"jersey", "shorts", "socks": rough = 0.78
			"shoes": rough = 0.5
			"sole": rough = 0.55
			"features": rough = 0.35
		_surfaces[name] = FcMeshSurface.new(name, rough)


# --- public ------------------------------------------------------------------------------------------------------------------

## Builds everything and returns {"skeleton": Skeleton3D, "mesh_instance": MeshInstance3D, "surfaces": Array[FcMeshSurface], "bones": {name: index}}.
## The mesh instance is already a child of the skeleton and skinned to it.
func build(body: Dictionary, visual_identity: Dictionary, visual_uniform: Dictionary) -> Dictionary:
	archetype = body
	identity = visual_identity
	uniform = visual_uniform
	height_feet = float(body["height_feet"])
	_h = height_feet
	_skin = identity["skin_color"]
	_hair = identity["hair_color"]
	_primary = uniform["primary"]
	_attire = str(uniform.get("attire", "playing"))
	_short_color = _primary if _attire == "playing" else _primary.darkened(0.3)
	_secondary = uniform["secondary"]
	_layout_skeleton()
	_build_body()
	_build_uniform()
	if _attire != "playing":
		_build_long_garments()
	_build_head()
	var skeleton := _make_skeleton()
	var mesh := ArrayMesh.new()
	var list: Array = []
	for name in SURFACES:
		var s: FcMeshSurface = _surfaces[name]
		if s.vertex_count() == 0:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s.arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, s.make_material())
		mesh.surface_set_name(mesh.get_surface_count() - 1, name)
		list.append(s)
	var instance := MeshInstance3D.new()
	instance.name = "Body"
	instance.mesh = mesh
	skeleton.add_child(instance)
	instance.skin = skeleton.create_skin_from_rest_transforms()
	instance.skeleton = NodePath("..")
	instance.custom_aabb = AABB(Vector3(-_h, -0.2, -_h), Vector3(_h * 2.0, _h * 1.3, _h * 2.0))   # a skinned mesh is culled by its rest box: keep it generous
	return {"skeleton": skeleton, "mesh_instance": instance, "surfaces": list, "bones": _index.duplicate()}


## A named colour from data/ui/character_palette.json (loaded once): the few fixed colours of the body kit, kept in data not in code.
static var _palette: Dictionary = {}


static func _pal(name: String) -> Color:
	if _palette.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/character_palette.json"))
		_palette = parsed if parsed is Dictionary else {"missing": "FFFFFF"}
	return Color.html(str(_palette[name])) if _palette.has(name) else Color.MAGENTA


func surface(name: String) -> FcMeshSurface:
	return _surfaces[name]


func part_count() -> int:
	var n := 0
	for name in SURFACES:
		n += (_surfaces[name] as FcMeshSurface).parts
	return n


func vertex_total() -> int:
	var n := 0
	for name in SURFACES:
		n += (_surfaces[name] as FcMeshSurface).vertex_count()
	return n


func triangle_total() -> int:
	var n := 0
	for name in SURFACES:
		n += (_surfaces[name] as FcMeshSurface).triangle_count()
	return n


## Where a bone's rest origin is (model space, feet).
func rest_origin(bone: String) -> Vector3:
	return _rest[bone]


# --- skeleton ----------------------------------------------------------------------------------------------------------------

func _layout_skeleton() -> void:
	var a := archetype
	var pelvis_y: float = 0.53 * float(a["leg_ratio"]) * _h
	var hip_y: float = pelvis_y - 0.03 * _h
	var ankle_y := 0.045 * _h
	var leg := hip_y - ankle_y
	var arm_total: float = (float(a["wingspan"]) - 2.0 * float(a["shoulder_x"])) * 0.5 * _h
	var chin_y: float = (0.995 - float(a["head_h"])) * _h
	_rest["pelvis"] = Vector3(0.0, pelvis_y, 0.0)
	_rest["torso"] = _rest["pelvis"]
	_rest["neck"] = Vector3(0.0, 0.832 * _h, 0.0)
	_rest["head"] = Vector3(0.0, chin_y, 0.0)
	for side in [1, -1]:
		var p := "l_" if side > 0 else "r_"
		var sx := float(side)
		_rest[p + "shoulder"] = Vector3(sx * float(a["shoulder_x"]) * _h, 0.805 * _h, 0.0)
		_rest[p + "elbow"] = _rest[p + "shoulder"] + Vector3(0.0, -arm_total * 0.43, 0.0)
		_rest[p + "hand"] = _rest[p + "elbow"] + Vector3(0.0, -arm_total * 0.36, 0.0)
		_rest[p + "hip"] = Vector3(sx * float(a["hip_rx"]) * 0.58 * _h, hip_y, 0.0)
		_rest[p + "knee"] = _rest[p + "hip"] + Vector3(0.0, -leg * 0.52, 0.0)
		_rest[p + "foot"] = Vector3(sx * float(a["hip_rx"]) * 0.58 * _h, ankle_y, 0.0)
	_head = {"chin": chin_y, "hh": float(a["head_h"]) * _h}


func _make_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	for i in BONES.size():
		skeleton.add_bone(BONES[i])
	for i in BONES.size():
		var parent := str(PARENTS[i])
		var local: Vector3 = _rest[BONES[i]]
		if parent != "":
			skeleton.set_bone_parent(i, _index[parent])
			local = _rest[BONES[i]] - _rest[parent]
		skeleton.set_bone_rest(i, Transform3D(Basis(), local))
		skeleton.set_bone_pose_position(i, local)
	return skeleton


# --- geometry helpers --------------------------------------------------------------------------------------------------------

func _bw(bone: String) -> Array:
	return [[_index[bone], 1.0]]


func _bw2(a: String, b: String, t: float) -> Array:
	var w := clampf(t, 0.0, 1.0)
	if w <= 0.001:
		return _bw(a)
	if w >= 0.999:
		return _bw(b)
	return [[_index[a], 1.0 - w], [_index[b], w]]


## A smooth step of v from a to b (0 below a, 1 above b), for blending bone weights along a limb.
func _sm(a: float, b: float, v: float) -> float:
	return smoothstep(a, b, v)


## Sweeps rings into a surface. Each ring: {c: centre, u: radius vector for sin(theta), v: radius vector for cos(theta), color, bw, e (superellipse
## exponent, 2 = ellipse), paint (optional Callable(position, sin, cos) -> Color), adjust (optional Callable(position, sin, cos) -> Vector3)}.
## The triangle winding is chosen so the faces point away from the ring centres, whatever order the rings are given in.
func _loft(s: FcMeshSurface, rings: Array, segs: int = 12, cap_start: bool = false, cap_end: bool = false, theta: Vector2 = Vector2(0.0, TAU)) -> void:
	var full := absf((theta.y - theta.x) - TAU) < 0.001
	var per := segs if full else segs + 1
	var base := s.vertex_count()
	for ring in rings:
		var e := float(ring.get("e", 2.0))
		for k in per:
			var th := theta.x + (theta.y - theta.x) * float(k) / float(segs)
			var sn := sin(th)
			var cs := cos(th)
			if e != 2.0:
				sn = signf(sn) * pow(absf(sn), 2.0 / e)
				cs = signf(cs) * pow(absf(cs), 2.0 / e)
			var p: Vector3 = (ring["c"] as Vector3) + (ring["u"] as Vector3) * sn + (ring["v"] as Vector3) * cs
			if ring.has("adjust"):
				p = (ring["adjust"] as Callable).call(p, sn, cs)
			var color: Color = (ring["paint"] as Callable).call(p, sn, cs) if ring.has("paint") else ring["color"]
			s.add_vertex(p, color, ring["bw"])
	var tris: Array = []
	var score := 0.0
	var quads := segs if full else segs
	for i in rings.size() - 1:
		for k in quads:
			var k2 := (k + 1) % per if full else k + 1
			var a := base + i * per + k
			var b := base + i * per + k2
			var c := base + (i + 1) * per + k2
			var d := base + (i + 1) * per + k
			tris.append([a, b, c])
			tris.append([a, c, d])
			var n := (s.vertices[b] - s.vertices[a]).cross(s.vertices[c] - s.vertices[a]) + (s.vertices[c] - s.vertices[a]).cross(s.vertices[d] - s.vertices[a])
			score += n.dot(s.vertices[a] - (rings[i]["c"] as Vector3))
	var flip := score < 0.0
	for t in tris:
		if flip:
			s.add_triangle(t[0], t[2], t[1])
		else:
			s.add_triangle(t[0], t[1], t[2])
	if full:
		if cap_start:
			_cap(s, rings[0], rings[1], base, per, false)
		if cap_end:
			_cap(s, rings[rings.size() - 1], rings[rings.size() - 2], base + (rings.size() - 1) * per, per, true)
	s.parts += 1


func _cap(s: FcMeshSurface, ring: Dictionary, next_ring: Dictionary, first: int, per: int, is_end: bool) -> void:
	var centre := s.add_vertex(ring["c"], ring["color"], ring["bw"])
	var outward: Vector3 = (ring["c"] as Vector3) - (next_ring["c"] as Vector3)
	var sample := (s.vertices[first + 1] - s.vertices[first]).cross(s.vertices[centre] - s.vertices[first])
	var flip := sample.dot(outward) < 0.0
	for k in per:
		var a := first + k
		var b := first + (k + 1) % per
		if flip:
			s.add_triangle(centre, b, a)
		else:
			s.add_triangle(centre, a, b)


## A ring of a body part running along Y: centre, half-widths along x and z.
func _ring_y(c: Vector3, rx: float, rz: float, color: Color, bw: Array, e: float = 2.0) -> Dictionary:
	return {"c": c, "u": Vector3(rx, 0.0, 0.0), "v": Vector3(0.0, 0.0, rz), "color": color, "bw": bw, "e": e}


## An ellipsoid (or a part of one: latitude and longitude limits in radians, longitude 0 at the front, +z), optionally rotated.
func _ellipsoid(s: FcMeshSurface, centre: Vector3, radii: Vector3, color: Color, bw: Array, lat: Vector2 = Vector2(-PI / 2.0, PI / 2.0), theta: Vector2 = Vector2(0.0, TAU), rings: int = 7, segs: int = 10, rot: Basis = Basis()) -> void:
	var list: Array = []
	for i in rings + 1:
		var phi := lat.x + (lat.y - lat.x) * float(i) / float(rings)
		var r := maxf(cos(phi), 0.0005)
		list.append({"c": centre + rot * Vector3(0.0, radii.y * sin(phi), 0.0), "u": rot * Vector3(radii.x * r, 0.0, 0.0), "v": rot * Vector3(0.0, 0.0, radii.z * r), "color": color, "bw": bw})
	_loft(s, list, segs, false, false, theta)


## A tube along a polyline with a radius per point (fingers, braids). Round ends are closed with a cap.
func _tube(s: FcMeshSurface, points: Array, radii: Array, color: Color, bw: Array, segs: int = 6) -> void:
	var list: Array = []
	for i in points.size():
		var t: Vector3 = ((points[mini(i + 1, points.size() - 1)] as Vector3) - (points[maxi(i - 1, 0)] as Vector3)).normalized()
		var ref := Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
		var u := t.cross(ref).normalized()
		var v := t.cross(u).normalized()
		var r := float(radii[i])
		list.append({"c": points[i], "u": u * r, "v": v * r, "color": color, "bw": bw})
	_loft(s, list, segs, true, true)


func _lerp_ring(a: float, b: float, t: float) -> float:
	return lerpf(a, b, t)


# --- body (skin) -------------------------------------------------------------------------------------------------------------

## The torso's cross-section (half widths) at the height fraction s of the way from the crotch to the shoulder line.
func _torso_section(t: float) -> Vector2:
	var a := archetype
	var hip := Vector2(float(a["hip_rx"]), float(a["hip_rz"]))
	var waist := Vector2(float(a["waist_rx"]), float(a["waist_rz"]))
	var chest := Vector2(float(a["chest_rx"]), float(a["chest_rz"]))
	if t < 0.17:
		return Vector2(lerpf(hip.x * 0.96, hip.x, t / 0.17), lerpf(hip.y * 0.95, hip.y, t / 0.17))
	if t < 0.40:
		var k := (t - 0.17) / 0.23
		return hip.lerp(waist, smoothstep(0.0, 1.0, k))
	if t < 0.82:
		var k := (t - 0.40) / 0.42
		return waist.lerp(chest, smoothstep(0.0, 1.0, k))
	var k := (t - 0.82) / 0.18
	return chest.lerp(chest * Vector2(0.66, 0.84), smoothstep(0.0, 1.0, k))


func _torso_y(t: float) -> float:
	var crotch := (_rest["pelvis"] as Vector3).y - 0.06 * _h
	return lerpf(crotch, 0.835 * _h, t)


## Weights of a torso-height ring: pelvis below the hips, the torso bone above the waist, a soft blend between.
func _torso_weights(y: float) -> Array:
	var py := (_rest["pelvis"] as Vector3).y
	return _bw2("pelvis", "torso", _sm(py - 0.01 * _h, py + 0.16 * _h, y))


func _build_body() -> void:
	var a := archetype
	var s: FcMeshSurface = _surfaces["skin"]
	var h := _h
	# torso and neck in one smooth loft (ends under the chin, inside the head)
	var rings: Array = []
	for t in [0.0, 0.08, 0.17, 0.28, 0.40, 0.55, 0.70, 0.82, 0.91, 0.97, 1.0]:
		var sec := _torso_section(t)
		var y := _torso_y(t)
		var zc: float = 0.0 if t < 0.5 else 0.004 * h * (t - 0.5)
		rings.append(_ring_y(Vector3(0.0, y, zc * 2.0), sec.x * h, sec.y * h, _skin, _torso_weights(y), 2.5 if t > 0.5 and t < 0.95 else 2.2))
	var neck_r := float(a["neck_r"]) * h
	for y_frac in [0.845, 0.865, 0.89]:
		var y: float = y_frac * h
		rings.append(_ring_y(Vector3(0.0, y, 0.006 * h), neck_r, neck_r * 0.92, _skin, _bw2("neck", "head", _sm(0.855 * h, 0.89 * h, y))))
	_loft(s, rings, 14, true, true)
	# arms and hands, legs
	for side in [1, -1]:
		var p := "l_" if side > 0 else "r_"
		_build_arm(s, p, float(side))
		_build_leg(s, p, float(side))


func _arm_weights(upper_to_forearm: float, bone_a: String, bone_b: String) -> Array:
	return _bw2(bone_a, bone_b, upper_to_forearm)


func _build_arm(s: FcMeshSurface, p: String, side: float) -> void:
	var a := archetype
	var h := _h
	var sh: Vector3 = _rest[p + "shoulder"]
	var el: Vector3 = _rest[p + "elbow"]
	var wr: Vector3 = _rest[p + "hand"]
	var ra := float(a["arm_r"]) * h
	var rf := float(a["forearm_r"]) * h
	var rings: Array = []
	# upper arm: a deltoid bulge near the shoulder, tapering to the elbow
	var upper := [[-0.045, 0.9, 0.62], [0.0, 1.12, 0.0], [0.18, 1.1, 0.0], [0.5, 1.0, 0.0], [0.85, 0.82, 0.0], [1.0, 0.8, 0.5]]
	for entry in upper:
		var t: float = entry[0]
		var c := sh.lerp(el, t) + Vector3(0.0, 0.0, 0.0)
		var r: float = ra * float(entry[1])
		var bw: Array
		if t < 0.0:
			bw = [[_index["torso"], 0.55], [_index[p + "shoulder"], 0.45]]
		elif t < 0.15:
			bw = _bw2("torso", p + "shoulder", 0.4 + t * 4.0)
		elif t > 0.9:
			bw = _bw2(p + "shoulder", p + "elbow", 0.35 + (t - 0.9) * 6.0)
		else:
			bw = _bw(p + "shoulder")
		rings.append(_ring_y(c, r, r * 0.95, _skin, bw))
	# forearm: thickest just below the elbow, narrow at the wrist
	var fore := [[0.0, 0.98, 0.5], [0.15, 1.0, 0.0], [0.35, 0.92, 0.0], [0.7, 0.72, 0.0], [1.0, 0.62, 0.35]]
	for entry in fore:
		var t: float = entry[0]
		var c := el.lerp(wr, t)
		var r: float = rf * float(entry[1])
		var bw: Array = _bw2(p + "elbow", p + "hand", float(entry[2]) * t if t > 0.9 else 0.0)
		if t == 0.0:
			bw = _bw2(p + "shoulder", p + "elbow", 0.65)
		rings.append(_ring_y(c, r * 1.05, r * 0.9, _skin, bw))
	_loft(s, rings, 10, true, false)
	_build_hand(s, p, side, wr)


func _build_hand(s: FcMeshSurface, p: String, side: float, wr: Vector3) -> void:
	var h := _h
	var hs: float = float(archetype["hand"])
	var bone := p + "hand"
	var palm_len := 0.052 * h * hs
	var width := 0.0185 * h * hs
	var thick := 0.0085 * h * hs
	var rings := [
		_ring_y(wr + Vector3(0.0, 0.004 * h, 0.0), thick * 1.0, width * 0.62, _skin, _bw(bone)),
		_ring_y(wr + Vector3(0.0, -palm_len * 0.35, 0.0), thick * 1.1, width * 0.95, _skin, _bw(bone)),
		_ring_y(wr + Vector3(0.0, -palm_len, 0.0), thick * 0.9, width, _skin, _bw(bone)),
	]
	_loft(s, rings, 8, true, true)
	# four fingers, a little spread, slightly curled; the thumb out to the front
	var lengths := [0.040, 0.046, 0.044, 0.034]
	for f in 4:
		var z := (float(f) - 1.5) * 0.0105 * h * hs
		var base := wr + Vector3(0.0, -palm_len, z)
		var len := float(lengths[f]) * h * hs
		var spread := (float(f) - 1.5) * 0.12
		var pts: Array = []
		var radii: Array = []
		for k in 4:
			var t := float(k) / 3.0
			pts.append(base + Vector3(-side * 0.0, -len * t * cos(spread), len * t * sin(spread) + len * 0.06 * sin(t * PI)))
			radii.append(0.0058 * h * hs * (1.0 - 0.28 * t))
		_tube(s, pts, radii, _skin, _bw(bone), 5)
	var tb := wr + Vector3(0.0, -palm_len * 0.28, width * 0.7)
	var tpts: Array = []
	var trad: Array = []
	for k in 3:
		var t := float(k) / 2.0
		tpts.append(tb + Vector3(0.0, -0.026 * h * hs * t, 0.020 * h * hs * t))
		trad.append(0.0068 * h * hs * (1.0 - 0.25 * t))
	_tube(s, tpts, trad, _skin, _bw(bone), 5)


func _build_leg(s: FcMeshSurface, p: String, side: float) -> void:
	var a := archetype
	var h := _h
	var hip: Vector3 = _rest[p + "hip"]
	var kn: Vector3 = _rest[p + "knee"]
	var an: Vector3 = _rest[p + "foot"]
	var rt := float(a["thigh_r"]) * h
	var rc := float(a["calf_r"]) * h
	var rings: Array = []
	var thigh := [[-0.18, 1.04, 0.0], [0.0, 1.0, 0.0], [0.35, 0.9, 0.0], [0.72, 0.72, 0.0], [1.0, 0.66, 0.35]]
	for entry in thigh:
		var t: float = entry[0]
		var c := hip.lerp(kn, t)
		var r: float = rt * float(entry[1])
		var bw: Array = _bw2("pelvis", p + "hip", 0.7 + (t + 0.18) * 1.5) if t < 0.0 else (_bw2(p + "hip", p + "knee", float(entry[2])) if t > 0.9 else _bw(p + "hip"))
		rings.append(_ring_y(c, r, r * 1.02, _skin, bw))
	# shin: the calf bulges at about a third of the way down, then narrows to the ankle
	var shin := [[0.04, 0.82, 0.55], [0.14, 1.0, 0.0], [0.3, 1.04, 0.0], [0.6, 0.8, 0.0], [0.9, 0.58, 0.0], [1.0, 0.54, 0.0]]
	for entry in shin:
		var t: float = entry[0]
		var c := kn.lerp(an, t)
		var r: float = rc * float(entry[1])
		var bw: Array = _bw2(p + "hip", p + "knee", 0.65) if t < 0.05 else (_bw2(p + "knee", p + "foot", _sm(0.82, 1.0, t) * 0.5) if t > 0.8 else _bw(p + "knee"))
		rings.append(_ring_y(c + Vector3(0.0, 0.0, -0.1 * rc * sin(t * PI)), r, r * 1.1, _skin, bw))
	_loft(s, rings, 10, true, true)


# --- uniform -----------------------------------------------------------------------------------------------------------------

func _build_uniform() -> void:
	var h := _h
	var a := archetype
	var js: FcMeshSurface = _surfaces["jersey"]
	var trim := _secondary
	# --- the tank-top jersey: the torso's shape, a little bigger, closed at the hem, narrowing to the straps; the neckline is cut by moving the front
	var rings: Array = []
	var neck_scoop := 0.050 * h
	for t in [0.30, 0.38, 0.50, 0.62, 0.74, 0.86, 0.91, 0.95, 0.985, 1.0]:
		var sec := _torso_section(minf(t, 0.88)) + Vector2(0.008, 0.007)
		var y := _torso_y(t)
		var rx := sec.x
		if t > 0.88:   # above the armpit the jersey becomes two straps: narrow, so the shoulders show skin
			rx = lerpf(sec.x, float(a["chest_rx"]) * 0.52, smoothstep(0.88, 1.0, t))
		var top: bool = t >= 0.94
		var is_hem: bool = t <= 0.31
		var paint := func(p: Vector3, sn: float, cs: float) -> Color:
			var c := _primary
			if is_hem or (top and false):
				c = trim
			elif absf(sn) > 0.93 and t < 0.9:   # a side panel in the trim colour
				c = trim.lerp(_primary, 0.15)
			return c
		var adjust := func(p: Vector3, sn: float, cs: float) -> Vector3:
			if top:
				var d := maxf(0.0, 1.0 - pow(absf(sn) / 0.62, 2.0))
				if cs > 0.0:
					return p + Vector3(0.0, -neck_scoop * d * cs, 0.0)
				return p + Vector3(0.0, -neck_scoop * 0.35 * d * -cs, 0.0)
			return p
		var ring := _ring_y(Vector3(0.0, y, 0.0), rx * h, sec.y * h, _primary, _torso_weights(y), 2.5)
		ring["paint"] = paint
		ring["adjust"] = adjust
		rings.append(ring)
	_loft(js, rings, 28, false, false)
	# trim edge of the neckline / armholes: a thin ring of trim colour is painted by the straps' top ring above (kept simple at broadcast distance)
	# --- the shorts: a hip block and two baggy legs
	var ss: FcMeshSurface = _surfaces["shorts"]
	var py: float = (_rest["pelvis"] as Vector3).y
	var waist_y := py + 0.095 * h
	var block: Array = []
	var block_defs := [[waist_y, 0.0, true], [waist_y - 0.012 * h, 0.0, true], [waist_y - 0.05 * h, 0.012, false], [py - 0.05 * h, 0.018, false], [py - 0.095 * h, 0.014, false]]
	for d in block_defs:
		var y: float = d[0]
		var rx := (float(a["hip_rx"]) + 0.012 + float(d[1])) * h
		var rz := (float(a["hip_rz"]) + 0.012 + float(d[1])) * h
		var band: bool = d[2]
		var ring := _ring_y(Vector3(0.0, y, 0.0), rx, rz, trim if band else _short_color, _bw("pelvis"), 2.5)
		block.append(ring)
	_loft(ss, block, 16, true, false)
	for side in [1, -1]:
		var p := "l_" if side > 0 else "r_"
		var hip: Vector3 = _rest[p + "hip"]
		var knee: Vector3 = _rest[p + "knee"]
		var hem_y := lerpf(hip.y, knee.y, 0.6)
		var legs: Array = []
		var rt := float(a["thigh_r"]) * h
		for k in 5:
			var t := float(k) / 4.0
			var y := lerpf(py - 0.08 * h, hem_y, t)
			var r := rt * lerpf(1.14, 1.2 + 0.05 * float(archetype["bulk"]), t) + 0.008 * h
			var is_hem: bool = k == 4
			var paint := func(p2: Vector3, sn: float, cs: float) -> Color:
				if is_hem:
					return trim
				if side * sn > 0.9 or (absf(sn) > 0.95):   # the side stripe, on the outside of the leg
					return trim.lerp(_short_color, 0.1)
				return _short_color
			var ring := _ring_y(Vector3(hip.x, y, 0.0), r, r * 1.04, _short_color, _bw2("pelvis", p + "hip", _sm(py - 0.08 * h, hip.y, y) * 0.9 + (0.1 if k > 1 else 0.0)), 2.3)
			ring["paint"] = paint
			legs.append(ring)
		_loft(ss, legs, 12, false, true)
		# --- socks (secondary colour, to the calf) and shoes
		var sks: FcMeshSurface = _surfaces["socks"]
		if _attire != "playing":
			_build_shoe(p, _rest[p + "foot"])
			continue
		var knee_pos: Vector3 = _rest[p + "knee"]
		var ankle: Vector3 = _rest[p + "foot"]
		var rc := float(a["calf_r"]) * h
		var sock: Array = []
		for k in 4:
			var t := 0.3 + 0.7 * float(k) / 3.0   # from a third of the way down to the ankle
			var c := knee_pos.lerp(ankle, t)
			var prof: float = [1.04, 0.84, 0.62, 0.56][3 - k]
			var col := trim if k == 0 else Color.WHITE.lerp(trim, 0.15)
			sock.append(_ring_y(c + Vector3(0.0, 0.0, -0.1 * rc * sin(t * PI)), rc * (float(prof) + 0.06) , rc * (float(prof) + 0.06) * 1.1, col, _bw2(p + "knee", p + "foot", _sm(0.82, 1.0, t) * 0.5) if t > 0.8 else _bw(p + "knee")))
		_loft(sks, sock, 10, false, false)
		_build_shoe(p, ankle)


## Long sleeves and long trousers for an official (a short-sleeved shirt) or a coach (a jacket): tubes round the arms and legs, a little wider than the
## skin, weighted to the same bones, drawn in the jersey and shorts surfaces.
func _build_long_garments() -> void:
	var h := _h
	var js: FcMeshSurface = _surfaces["jersey"]
	var ss: FcMeshSurface = _surfaces["shorts"]
	var long_sleeves := _attire == "suit"
	for side in [1, -1]:
		var p := "l_" if side > 0 else "r_"
		var sh: Vector3 = _rest[p + "shoulder"]
		var el: Vector3 = _rest[p + "elbow"]
		var wr: Vector3 = _rest[p + "hand"]
		var ra := float(archetype["arm_r"]) * h * 1.28 + 0.006 * h
		var rf := float(archetype["forearm_r"]) * h * 1.2 + 0.006 * h
		var rings: Array = []
		for t in [-0.045, 0.0, 0.2, 0.55, 0.9, 1.0]:
			var bw: Array = _bw2("torso", p + "shoulder", 0.4 + t * 4.0) if t < 0.15 else (_bw2(p + "shoulder", p + "elbow", 0.35 + (t - 0.9) * 6.0) if t > 0.9 else _bw(p + "shoulder"))
			if t < 0.0:
				bw = [[_index["torso"], 0.55], [_index[p + "shoulder"], 0.45]]
			var r := ra * (1.0 if t > 0.0 else 0.92)
			rings.append(_ring_y(sh.lerp(el, t), r, r * 0.95, _primary, bw))
		if long_sleeves:
			for t in [0.12, 0.45, 0.85]:
				var r := rf * lerpf(1.0, 0.74, t)
				rings.append(_ring_y(el.lerp(wr, t), r, r * 0.92, _primary, _bw(p + "elbow")))
		_loft(js, rings, 10, false, false)
		var hip: Vector3 = _rest[p + "hip"]
		var kn: Vector3 = _rest[p + "knee"]
		var an: Vector3 = _rest[p + "foot"]
		var rt := float(archetype["thigh_r"]) * h * 1.16 + 0.006 * h
		var rc := float(archetype["calf_r"]) * h * 1.16 + 0.006 * h
		var legs: Array = []
		for entry in [[-0.05, 1.04], [0.35, 0.9], [0.72, 0.74], [1.0, 0.68]]:
			var t: float = entry[0]
			var bw: Array = _bw2("pelvis", p + "hip", 0.8) if t < 0.0 else (_bw2(p + "hip", p + "knee", 0.4) if t > 0.9 else _bw(p + "hip"))
			legs.append(_ring_y(hip.lerp(kn, t), rt * float(entry[1]), rt * float(entry[1]) * 1.02, _short_color, bw))
		for entry in [[0.06, 0.9, 0.55], [0.3, 1.0, 0.0], [0.65, 0.82, 0.0], [0.95, 0.66, 0.25]]:
			var t: float = entry[0]
			var bw: Array = _bw2(p + "hip", p + "knee", 0.65) if t < 0.1 else (_bw2(p + "knee", p + "foot", float(entry[2])) if t > 0.9 else _bw(p + "knee"))
			legs.append(_ring_y(kn.lerp(an, t) + Vector3(0.0, 0.0, -0.1 * rc * sin(t * PI)), rc * float(entry[1]), rc * float(entry[1]) * 1.1, _short_color, bw))
		_loft(ss, legs, 10, false, false)


func _build_shoe(p: String, ankle: Vector3) -> void:
	var h := _h
	var fs := float(archetype["foot"])
	var shoes: FcMeshSurface = _surfaces["shoes"]
	var sole: FcMeshSurface = _surfaces["sole"]
	var bone := p + "foot"
	var base_color: Color
	match int(archetype["shoe"]):
		0: base_color = _pal("shoe_white")
		1: base_color = _pal("shoe_black")
		2: base_color = _secondary
		_: base_color = _primary.lightened(0.25)
	var accent := _primary if int(archetype["shoe"]) == 2 else _secondary
	var sole_y := ankle.y - 0.045 * h
	# x half-width, top height above the sole, at each z (heel to toe, feet relative to the ankle)
	var defs := [[-0.040, 0.020, 0.062], [-0.028, 0.030, 0.075], [-0.006, 0.034, 0.078], [0.030, 0.036, 0.056], [0.068, 0.040, 0.038], [0.104, 0.038, 0.027], [0.128, 0.028, 0.017], [0.138, 0.012, 0.008]]
	var upper: Array = []
	var slab: Array = []
	for d in defs:
		var z: float = float(d[0]) * h * fs
		var hw: float = float(d[1]) * h * fs
		var top: float = float(d[2]) * h * fs
		var c := Vector3(ankle.x, sole_y + 0.012 * h + (top - 0.012 * h) * 0.5, ankle.z + z)
		var col := accent if (float(d[0]) > 0.02 and float(d[0]) < 0.07) else base_color
		upper.append({"c": c, "u": Vector3(hw, 0.0, 0.0), "v": Vector3(0.0, (top - 0.012 * h) * 0.5, 0.0), "color": col, "bw": _bw(bone)})
		slab.append({"c": Vector3(ankle.x, sole_y + 0.006 * h, ankle.z + z), "u": Vector3(hw * 1.07, 0.0, 0.0), "v": Vector3(0.0, 0.006 * h, 0.0), "color": _pal("sole_white") if int(archetype["shoe"]) != 1 else _pal("sole_black"), "bw": _bw(bone)})
	_loft(shoes, upper, 10, true, true)
	_loft(sole, slab, 10, true, true)


# --- head, face and hair -----------------------------------------------------------------------------------------------------

## The head's cross-section at u in [-1 (chin), 1 (crown)]: {y, rx, rz, zc, e}.
func _head_ring(u: float) -> Dictionary:
	var a := archetype
	var hh: float = _head["hh"]
	var chin: float = _head["chin"]
	var rx0 := hh * 0.34 * float(a["face_w"])
	var rz0 := hh * 0.425
	var base := sqrt(maxf(1.0 - u * u, 0.0005))
	var wf := 1.0
	var e := 2.0
	match int(a["jaw"]):
		1:   # square jaw: wide and boxy low down
			wf = 1.0 + 0.16 * (1.0 - smoothstep(-0.8, -0.15, u))
			e = lerpf(2.8, 2.0, smoothstep(-0.8, 0.1, u))
		2:   # pointed: narrows quickly to the chin
			wf = 1.0 - 0.24 * (1.0 - smoothstep(-1.0, -0.05, u))
	var zc := rz0 * (0.07 * maxf(0.0, -u) - 0.05 * maxf(0.0, u))
	return {"y": chin + hh * 0.5 * (u + 1.0), "rx": rx0 * base * wf, "rz": rz0 * base * (0.92 + 0.08 * wf), "zc": zc, "e": e, "rx0": rx0, "rz0": rz0}


## The point on the front of the face at sideways offset x and height u (for placing eyes, nose, mouth).
func _face_point(x: float, u: float, inset: float = 0.0) -> Vector3:
	var r := _head_ring(u)
	var q := clampf(x / maxf(float(r["rx"]), 0.0001), -0.98, 0.98)
	return Vector3(x, float(r["y"]), float(r["zc"]) + float(r["rz"]) * sqrt(1.0 - q * q) - inset)


func _build_head() -> void:
	var a := archetype
	var s: FcMeshSurface = _surfaces["skin"]
	var f: FcMeshSurface = _surfaces["features"]
	var hair: FcMeshSurface = _surfaces["hair"]
	var hh: float = _head["hh"]
	var bone := "head"
	var rings: Array = []
	var n := 16
	for i in n + 1:
		var u := -cos(PI * float(i) / float(n))
		var r := _head_ring(u)
		rings.append({"c": Vector3(0.0, r["y"], r["zc"]), "u": Vector3(r["rx"], 0.0, 0.0), "v": Vector3(0.0, 0.0, r["rz"]), "color": _skin, "bw": _bw(bone), "e": r["e"]})
	_loft(s, rings, 18, false, false)
	var rx0: float = _head_ring(0.0)["rx0"]
	var rz0: float = _head_ring(0.0)["rz0"]
	var centre_y: float = float(_head["chin"]) + hh * 0.5
	var darker := _skin.darkened(0.12)
	# ears
	for side in [1, -1]:
		_ellipsoid(s, Vector3(float(side) * rx0 * 0.97, centre_y - hh * 0.02, -rz0 * 0.05), Vector3(0.012 * _h, hh * 0.11, hh * 0.075), _skin.darkened(0.05), _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 5, 8)
	# nose: bridge and tip, sized by the nose style
	var nose_k := float(a["nose"])
	var tip := _face_point(0.0, -0.2, 0.0)
	_ellipsoid(s, tip + Vector3(0.0, 0.0, hh * 0.015), Vector3(hh * (0.058 + 0.012 * nose_k), hh * 0.07, hh * (0.055 + 0.012 * nose_k)), _skin.darkened(0.03), _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 5, 8)
	_ellipsoid(s, _face_point(0.0, 0.05, hh * 0.01), Vector3(hh * 0.03, hh * 0.1, hh * 0.04), _skin, _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 6)
	# brow ridge
	for side in [1, -1]:
		var ex := float(side) * rx0 * 0.36 * float(a["eye_gap"])
		_ellipsoid(s, _face_point(ex, 0.24, hh * 0.015), Vector3(hh * 0.12, hh * 0.032, hh * 0.04), _skin.darkened(0.04), _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 8)
	# eyes: white, iris, and a brow of hair colour
	var eye_size := float(a["eye_size"])
	var brow_color := _hair.darkened(0.15) if str(identity["hair"]) != "bald" else _skin.darkened(0.55)
	for side in [1, -1]:
		var ex := float(side) * rx0 * 0.36 * float(a["eye_gap"])
		var eye := _face_point(ex, 0.08, hh * 0.02)
		_ellipsoid(f, eye, Vector3(hh * 0.062 * eye_size, hh * 0.034 * eye_size, hh * 0.03), _pal("eye_white"), _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 5, 8)
		_ellipsoid(f, eye + Vector3(0.0, 0.0, hh * 0.016), Vector3(hh * 0.03, hh * 0.03, hh * 0.02), _pal("iris"), _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 8)
		var thick := 0.014 + 0.007 * float(a["brow"])
		_ellipsoid(f, _face_point(ex, 0.3, hh * 0.012), Vector3(hh * 0.095, hh * thick, hh * 0.022), brow_color, _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 8, Basis(Vector3(0, 0, 1), float(side) * -0.12))
	# mouth: a smile, a neutral line or a smirk
	var tilt := 0.0
	match int(a["mouth"]):
		0: tilt = 0.0
		2: tilt = 0.18
	var mouth_u := -0.52
	var lip := _skin.lerp(_pal("lip"), 0.55)
	_ellipsoid(f, _face_point(0.0, mouth_u, hh * 0.012), Vector3(hh * (0.10 if int(a["mouth"]) == 0 else 0.085), hh * 0.016, hh * 0.02), lip, _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 10, Basis(Vector3(0, 0, 1), tilt))
	_ellipsoid(f, _face_point(0.0, mouth_u - 0.1, hh * 0.012), Vector3(hh * 0.065, hh * 0.016, hh * 0.016), lip.lightened(0.05), _bw(bone), Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 8)
	_build_hair(hair, rx0, rz0, centre_y, hh)
	_build_facial_hair(hair, rx0, rz0, centre_y, hh)
	if bool(a["headband"]):
		var js: FcMeshSurface = _surfaces["jersey"]
		var band: Array = []
		for u in [0.42, 0.5, 0.58]:
			var r := _head_ring(float(u))
			band.append({"c": Vector3(0.0, r["y"], float(r["zc"]) * 1.0), "u": Vector3(float(r["rx"]) * 1.1, 0.0, 0.0), "v": Vector3(0.0, 0.0, float(r["rz"]) * 1.1), "color": _secondary, "bw": _bw(bone)})
		_loft(js, band, 18, false, false)


func _build_hair(s: FcMeshSurface, rx0: float, rz0: float, centre_y: float, hh: float) -> void:
	var style := str(identity["hair"])
	var bone := "head"
	var bw := _bw(bone)
	var c := _hair
	var ry := hh * 0.5
	var head_c := Vector3(0.0, centre_y, 0.0)
	var cut := asin(0.26)   # the hairline: a little above the middle of the head
	match style:
		"bald":
			return
		"short", "fade":
			var k := 1.05 if style == "short" else 1.025
			var col := c if style == "short" else c.lerp(_skin, 0.25)
			_ellipsoid(s, head_c + Vector3(0.0, 0.0, -rz0 * 0.04), Vector3(rx0 * k, ry * k, rz0 * k), col, bw, Vector2(cut, PI / 2.0), Vector2(0.0, TAU), 7, 14)
			_ellipsoid(s, head_c + Vector3(0.0, 0.0, -rz0 * 0.06), Vector3(rx0 * (k + 0.01), ry * (k + 0.01), rz0 * (k + 0.01)), col.lerp(_skin, 0.4 if style == "fade" else 0.0), bw, Vector2(-0.1, cut + 0.2), Vector2(PI - 1.9, PI + 1.9), 4, 12)
		"afro":
			# a big rounded mass raised and set back so the face stays clear: the top half all round, and a lower part behind the ears only
			_ellipsoid(s, head_c + Vector3(0.0, ry * 0.3, -rz0 * 0.3), Vector3(rx0 * 1.5, ry * 1.36, rz0 * 1.35), c, bw, Vector2(0.08, PI / 2.0), Vector2(0.0, TAU), 8, 18)
			_ellipsoid(s, head_c + Vector3(0.0, ry * 0.3, -rz0 * 0.3), Vector3(rx0 * 1.5, ry * 1.36, rz0 * 1.35), c, bw, Vector2(-0.55, 0.12), Vector2(PI - 2.0, PI + 2.0), 4, 14)
		"braids", "locs":
			_ellipsoid(s, head_c + Vector3(0.0, 0.0, -rz0 * 0.04), Vector3(rx0 * 1.05, ry * 1.05, rz0 * 1.05), c, bw, Vector2(cut, PI / 2.0), Vector2(0.0, TAU), 6, 14)
			var count := 9
			var length := (0.12 if style == "braids" else 0.17) * _h
			for k in count:
				var ang := PI * 0.5 + TAU * float(k) / float(count) + 0.3
				var x := cos(ang) * rx0 * 0.95
				var z := -sin(ang) * rz0 * 0.9 - rz0 * 0.1
				if z > rz0 * 0.2:
					continue   # none across the face
				var pts: Array = []
				var radii: Array = []
				for j in 6:
					var t := float(j) / 5.0
					pts.append(Vector3(x * (1.0 + 0.1 * t), centre_y + ry * 0.12 - length * t, z * (1.0 + 0.12 * t) - 0.01 * _h * t))
					radii.append(0.0075 * _h * (1.0 - 0.15 * t) * (1.4 if style == "locs" else 1.0))
				_tube(s, pts, radii, c.lightened(0.04 * float(k % 3)), bw, 5)
		"curly":
			_ellipsoid(s, head_c + Vector3(0.0, ry * 0.05, -rz0 * 0.06), Vector3(rx0 * 1.08, ry * 1.08, rz0 * 1.08), c, bw, Vector2(cut, PI / 2.0), Vector2(0.0, TAU), 6, 14)
			for k in 18:
				var ang := TAU * float(k) / 18.0
				var ring_r := 0.8 if k % 2 == 0 else 0.45
				var up := 0.78 if k % 2 == 0 else 1.0
				_ellipsoid(s, head_c + Vector3(cos(ang) * rx0 * ring_r, ry * up * 0.95, sin(ang) * rz0 * ring_r - rz0 * 0.1), Vector3(rx0 * 0.28, rx0 * 0.28, rx0 * 0.28), c.lightened(0.03 * float(k % 3)), bw, Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 3, 6)
		"long":
			_ellipsoid(s, head_c + Vector3(0.0, 0.0, -rz0 * 0.04), Vector3(rx0 * 1.06, ry * 1.06, rz0 * 1.06), c, bw, Vector2(cut, PI / 2.0), Vector2(0.0, TAU), 6, 14)
			var curtain: Array = []
			for k in 7:
				var t := float(k) / 6.0
				var y := centre_y + ry * 0.55 - t * (hh * 1.25)
				var spread := rx0 * (1.1 - 0.15 * t)
				curtain.append({"c": Vector3(0.0, y, -rz0 * (0.45 - 0.08 * t)), "u": Vector3(spread, 0.0, 0.0), "v": Vector3(0.0, 0.0, rz0 * (0.62 - 0.1 * t)), "color": c, "bw": bw})
			_loft(s, curtain, 12, false, false, Vector2(PI - 1.75, PI + 1.75))


func _build_facial_hair(s: FcMeshSurface, rx0: float, rz0: float, centre_y: float, hh: float) -> void:
	var style := str(identity["facial_hair"])
	var bw := _bw("head")
	var col := _hair.darkened(0.08)
	var head_c := Vector3(0.0, centre_y, 0.0)
	var ry := hh * 0.5
	match style:
		"stubble":
			_ellipsoid(s, head_c + Vector3(0.0, 0.0, 0.0), Vector3(rx0 * 1.018, ry * 1.012, rz0 * 1.02), _skin.darkened(0.3), bw, Vector2(-PI / 2.0, -0.05), Vector2(-1.75, 1.75), 5, 12)
		"goatee":
			_ellipsoid(s, _face_point(0.0, -0.8, -hh * 0.005), Vector3(hh * 0.1, hh * 0.1, hh * 0.07), col, bw, Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 4, 8)
			_ellipsoid(s, _face_point(0.0, -0.4, hh * 0.002), Vector3(hh * 0.12, hh * 0.022, hh * 0.026), col, bw, Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 3, 8)
		"beard":
			_ellipsoid(s, head_c + Vector3(0.0, -ry * 0.03, 0.0), Vector3(rx0 * 1.07, ry * 1.04, rz0 * 1.07), col, bw, Vector2(-PI / 2.0, -0.12), Vector2(-1.95, 1.95), 6, 14)
			_ellipsoid(s, _face_point(0.0, -0.38, 0.0), Vector3(hh * 0.13, hh * 0.026, hh * 0.03), col, bw, Vector2(-PI / 2.0, PI / 2.0), Vector2(0.0, TAU), 3, 8)
