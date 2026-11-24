class_name FcMeshSurface
extends RefCounted
## One surface of a generated, SKINNED mesh (3D overhaul, M1): vertices with a colour and up to four bone weights, triangles, and normals computed
## here (area-weighted, smooth across shared vertices) so a lofted limb is round, not faceted. One surface has one material, so skin, cloth, shoes
## and hair are separate surfaces. Pure data: no nodes, so the geometry is unit-testable without a window.

var surface_name: String = ""
var roughness: float = 0.6
var metallic: float = 0.0
var vertices := PackedVector3Array()
var colors := PackedColorArray()
var bones := PackedInt32Array()      # 4 per vertex
var weights := PackedFloat32Array()  # 4 per vertex
var indices := PackedInt32Array()
var parts: int = 0                   # how many pieces (lofts, ellipsoids, tubes) were added: a rough measure of how detailed a body is


func _init(name: String = "", rough: float = 0.6, metal: float = 0.0) -> void:
	surface_name = name
	roughness = rough
	metallic = metal


func vertex_count() -> int:
	return vertices.size()


func triangle_count() -> int:
	return indices.size() / 3


## Adds a vertex. `bw` is [[bone, weight], ...] (at most four; they are normalised to sum to 1). Returns its index.
func add_vertex(position: Vector3, color: Color, bw: Array) -> int:
	vertices.append(position)
	colors.append(color)
	var total := 0.0
	for pair in bw:
		total += float(pair[1])
	for k in 4:
		if k < bw.size() and total > 0.0:
			bones.append(int(bw[k][0]))
			weights.append(float(bw[k][1]) / total)
		else:
			bones.append(0)
			weights.append(0.0)
	return vertices.size() - 1


## Adds a triangle given COUNTER-CLOCKWISE as seen from outside (the natural way to write a loft). Godot's front face is CLOCKWISE, so the order
## is reversed when it is stored: a surface drawn from outside is lit and not culled.
func add_triangle(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(c)
	indices.append(b)


## Smooth vertex normals from the triangles (area weighted).
func compute_normals() -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 2]   # stored clockwise: read back counter-clockwise so the normal points out
		var c := indices[t + 1]
		var n := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-14 else Vector3.UP
	return normals


## The arrays for ArrayMesh.add_surface_from_arrays.
func arrays() -> Array:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = compute_normals()
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	out[Mesh.ARRAY_INDEX] = indices
	return out


## A material that shows the vertex colours (the colour of every garment, the skin shading) with this surface's roughness.
func make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.metallic = metallic
	return m


## True when every index points at a vertex, every weight set sums to about 1 and nothing is NaN: the validity test the unit tests use.
func is_valid() -> bool:
	for i in indices:
		if i < 0 or i >= vertices.size():
			return false
	for v in vertices:
		if not v.is_finite():
			return false
	for i in vertices.size():
		var s := weights[i * 4] + weights[i * 4 + 1] + weights[i * 4 + 2] + weights[i * 4 + 3]
		if absf(s - 1.0) > 0.001:
			return false
	return true
