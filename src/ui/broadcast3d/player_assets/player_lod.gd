class_name FcPlayerLod
extends RefCounted
## Levels of detail of a V2 player (D-075, M9). Three tiers, without separate authored meshes:
##   HIGH (close-ups, presentation, portraits): everything, full density.
##   MEDIUM (normal gameplay cameras): the big meshes switch to coarser versions by screen size, through Godot's mesh LOD (chains generated here, once
##   per player, from the baked mesh by meshoptimizer); the smallest details (lashes, laces) stop drawing beyond MEDIUM_FROM metres.
##   LOW (distant and background players): coarser still, and fine parts (brows, wristbands, sleeves edges, trim) stop beyond LOW_FROM metres.
## Close-up quality is never reduced: the full mesh is always the first level.

const MEDIUM_FROM := 9.0
const LOW_FROM := 26.0
## Meshes that get a generated LOD chain (the big ones: the rest are too small to matter).
const CHAINED := ["skin", "jersey", "shorts", "shoes", "sole", "socks", "hair_", "facial_beard"]
## Parts that stop drawing beyond a distance: name prefix -> metres.
const RANGES := {"lashes": MEDIUM_FROM, "equip_laces": MEDIUM_FROM, "brow_": LOW_FROM, "equip_wristband": LOW_FROM, "trim": LOW_FROM * 1.5}


static func _chained(mesh_name: String) -> bool:
	for c in CHAINED:
		if mesh_name == c or (str(c).ends_with("_") and mesh_name.begins_with(c)) or mesh_name.begins_with(c):
			return true
	return false


static var _cache: Dictionary = {}   # "player key|mesh|weights" -> mesh with LODs (a player seen again is not rebuilt)
static var _order: Array[String] = []
const CACHE_LIMIT := 400


## The cached LOD mesh for `key`, or the result of with_lods (stored).
static func cached(key: String, mesh: ArrayMesh, mesh_name: String) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var out := with_lods(mesh, mesh_name)
	_cache[key] = out
	_order.append(key)
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())
	return out


static func has_cached(key: String) -> bool:
	return _cache.has(key)


static func cached_mesh(key: String) -> Mesh:
	return _cache[key]


## Bakes the morphs and builds the LOD chains of every pending mesh of `characters` NOW (on this thread: both need the engine main thread). Returns the
## number of meshes. Tests and tools use it; the replay uses bake_progressively so the screen never freezes.
static func bake_characters(characters: Array) -> int:
	var jobs := _take_jobs(characters)
	for job in jobs:
		_run(job)
	return jobs.size()


## Bakes the pending meshes of `characters` a little each frame (about budget_ms per frame) under `host`. Until a mesh is baked the player shows its
## morphs live (correct, only a little more costly), so the replay starts at once. Returns the baker node (it frees itself when done).
static func bake_progressively(characters: Array, host: Node, budget_ms: float = 6.0) -> Node:
	var jobs := _take_jobs(characters)
	if jobs.is_empty():
		return null
	var baker := FcPlayerBaker.new()
	baker.jobs = jobs
	baker.budget_ms = budget_ms
	host.add_child(baker)
	return baker


static func _take_jobs(characters: Array) -> Array:
	var jobs: Array = []
	for c in characters:
		if c is FcBroadcastCharacter:
			jobs.append_array((c as FcBroadcastCharacter).pending_bake)
			(c as FcBroadcastCharacter).pending_bake = []
	return jobs


## One job: [MeshInstance3D, cache key, mesh name].
static func _run(job: Array) -> void:
	var mi: MeshInstance3D = job[0]
	if not is_instance_valid(mi):
		return
	var baked := mi.bake_mesh_from_current_blend_shape_mix()
	if baked == null:
		return
	var out: Mesh = with_lods(baked, str(job[2])) if FcBroadcastCharacter.v2_lods else baked
	mi.mesh = out
	_cache[str(job[1])] = out
	_order.append(str(job[1]))
	while _order.size() > CACHE_LIMIT:
		_cache.erase(_order.pop_front())


static func clear_cache() -> void:
	_cache.clear()
	_order.clear()


## The baked mesh with a generated LOD chain (same surfaces, materials and skinning); the mesh itself when LODs cannot be made.
static func with_lods(mesh: ArrayMesh, mesh_name: String) -> Mesh:
	if not _chained(mesh_name) or mesh.get_surface_count() == 0:
		return mesh
	var im := ImporterMesh.new()
	for sidx in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(sidx), mesh.surface_get_arrays(sidx), [], {}, mesh.surface_get_material(sidx), mesh.surface_get_name(sidx), mesh.surface_get_format(sidx))
	im.generate_lods(25.0, 60.0, [])
	var out := im.get_mesh()
	if out == null or out.get_surface_count() != mesh.get_surface_count():
		return mesh
	out.set_meta("fc_lod_levels", 1 + im.get_surface_lod_count(0))
	return out


## Distance cut-offs for small parts (they are a few pixels wide beyond these distances).
static func apply_ranges(mi: MeshInstance3D, mesh_name: String) -> void:
	for prefix in RANGES:
		if mesh_name.begins_with(prefix):
			mi.visibility_range_end = float(RANGES[prefix])
			mi.visibility_range_end_margin = 1.0
			return


## How many LOD levels a mesh carries (tests and the budget guard).
static func level_count(mesh: Mesh) -> int:
	return int(mesh.get_meta("fc_lod_levels", 1)) if mesh != null else 1
