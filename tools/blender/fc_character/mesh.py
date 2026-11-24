"""Mesh building helpers: a Part (bmesh + per-vertex bone weights + optional vertex colours), lofts, ellipsoids, and conversion to a skinned Blender object."""
import math

import bmesh
import bpy
from mathutils import Vector

TAU = math.tau


def smoothstep(a: float, b: float, v: float) -> float:
    t = max(0.0, min(1.0, (v - a) / (b - a) if b != a else 1.0))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def gauss(d2: float, sigma: float) -> float:
    """A bump of height 1 at distance 0 falling to about 0 by 2.5 sigma (d2 is the squared distance)."""
    return math.exp(-d2 / (2.0 * sigma * sigma))


class Part:
    """One surface under construction: geometry, a weight list per vertex, optional vertex colours."""

    def __init__(self):
        self.bm = bmesh.new()
        self.weights = []
        self.colors = {}

    def vert(self, co, w, color=None):
        v = self.bm.verts.new(Vector(co))
        self.weights.append(w)
        if color is not None:
            self.colors[len(self.weights) - 1] = color
        return v

    def face(self, *verts):
        try:
            return self.bm.faces.new(verts)
        except ValueError:
            return None

    def count(self) -> int:
        return len(self.bm.verts)

    def merge(self, other: "Part"):
        """Append another Part geometry (verts, faces, weights, colours) to this one."""
        mapping = {}
        other.bm.verts.index_update()
        other.bm.verts.ensure_lookup_table()
        for i, v in enumerate(other.bm.verts):
            mapping[v.index] = self.vert(v.co, other.weights[i], other.colors.get(i))
        for f in other.bm.faces:
            self.face(*[mapping[v.index] for v in f.verts])
        other.bm.free()

    def loft(self, rings, segs=14, cap_start=False, cap_end=False, squareness=2.0, flip=False):
        """Sweep rings along their order. A ring is (centre, rx, ry, weights[(bone, w)]). rx is the width (X); ry the depth (Y; the front is -Y).
        squareness 2 is an ellipse, larger values give a rounded rectangle (jerseys, shoulders)."""
        first = len(self.weights)
        n = 2.0 / squareness
        for c, rx, ry, w in rings:
            for k in range(segs):
                th = TAU * k / segs
                s, co = math.sin(th), math.cos(th)
                x = rx * math.copysign(abs(s) ** n, s)
                y = -ry * math.copysign(abs(co) ** n, co)
                self.vert((c.x + x, c.y + y, c.z), w)
        self.bm.verts.ensure_lookup_table()
        for i in range(len(rings) - 1):
            for k in range(segs):
                a = first + i * segs + k
                b = first + i * segs + (k + 1) % segs
                c2 = first + (i + 1) * segs + (k + 1) % segs
                d = first + (i + 1) * segs + k
                quad = (self.bm.verts[a], self.bm.verts[b], self.bm.verts[c2], self.bm.verts[d])
                self.face(*(quad[::-1] if flip else quad))
        for index, cap in ((0, cap_start), (len(rings) - 1, cap_end)):
            if cap:
                ring = [self.bm.verts[first + index * segs + k] for k in range(segs)]
                self.face(*ring)
        return first

    def ellipsoid(self, centre, radii, bone, rings=8, segs=14, lat_min=-math.pi / 2, lat_max=math.pi / 2, color=None):
        first = len(self.weights)
        for i in range(rings + 1):
            phi = lat_min + (lat_max - lat_min) * i / rings
            r = max(math.cos(phi), 0.001)
            for k in range(segs):
                th = TAU * k / segs
                self.vert((centre[0] + radii[0] * r * math.sin(th), centre[1] - radii[1] * r * math.cos(th), centre[2] + radii[2] * math.sin(phi)), [(bone, 1.0)], color)
        self.bm.verts.ensure_lookup_table()
        for i in range(rings):
            for k in range(segs):
                a = first + i * segs + k
                b = first + i * segs + (k + 1) % segs
                c = first + (i + 1) * segs + (k + 1) % segs
                d = first + (i + 1) * segs + k
                self.face(self.bm.verts[a], self.bm.verts[b], self.bm.verts[c], self.bm.verts[d])
        return first

    def remove_faces(self, predicate):
        """Delete the faces whose centroid satisfies predicate(Vector) but keep every vertex, so the weight list stays aligned."""
        doomed = [f for f in self.bm.faces if predicate(f.calc_center_median())]
        bmesh.ops.delete(self.bm, geom=doomed, context="FACES_ONLY")
        return len(doomed)

    def boundary_loops(self):
        """Ordered vertex-index loops (or chains) around the open edges of the surface."""
        self.bm.verts.index_update()
        self.bm.verts.ensure_lookup_table()
        adj = {}
        for e in self.bm.edges:
            if len(e.link_faces) == 1:
                a, b = e.verts[0].index, e.verts[1].index
                adj.setdefault(a, []).append(b)
                adj.setdefault(b, []).append(a)
        seen, loops = set(), []
        for start in list(adj):
            if start in seen:
                continue
            loop, cur, prev = [start], start, None
            seen.add(start)
            while True:
                nxt = [n for n in adj[cur] if n != prev and n not in seen]
                if not nxt:
                    break
                prev, cur = cur, nxt[0]
                seen.add(cur)
                loop.append(cur)
            loops.append(loop)
        return loops

    def to_object(self, name, material, armature, smooth=True, uv=None):
        bm = self.bm
        bm.verts.index_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(name)
        if self.colors:
            layer = bm.loops.layers.color.new("Col")
            for f in bm.faces:
                for loop in f.loops:
                    col = self.colors.get(loop.vert.index)
                    if col is not None:
                        loop[layer] = col
        bm.to_mesh(mesh)
        bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = smooth
        if uv is not None:
            layer = mesh.uv_layers.new(name="UVMap")
            for poly in mesh.polygons:
                coords = [list(uv(mesh.vertices[mesh.loops[li].vertex_index].co)) for li in poly.loop_indices]
                us = [c[0] for c in coords]
                if max(us) - min(us) > 0.5:   # the face straddles the wrap seam: lift the small values by one so the texture does not shear across it
                    for c in coords:
                        if c[0] < 0.5:
                            c[0] += 1.0
                for li, c in zip(poly.loop_indices, coords):
                    layer.data[li].uv = (c[0], c[1])
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(material)
        groups = {}
        for i, pairs in enumerate(self.weights):
            total = sum(w for _, w in pairs if w > 0.0001)
            if total <= 0:
                continue
            for bone, w in pairs:
                if w <= 0.0001:
                    continue
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([i], w / total, "REPLACE")
        obj.parent = armature
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = armature
        return obj
