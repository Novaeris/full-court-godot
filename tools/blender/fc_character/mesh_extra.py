"""More mesh helpers: tubes along a path (lips, brows, braids, cords) and plain geometry utilities."""
import math

from mathutils import Vector

from .mesh import Part, TAU


def tube(part: Part, points, radii, weights, segs=8, cap_start=True, cap_end=True, color=None, up=Vector((0, 0, 1))):
    """A tube with an elliptical cross-section along a polyline.
    points: list of Vector; radii: list of (r_normal, r_binormal); weights: one weight list (or a list per point)."""
    n = len(points)
    first = len(part.weights)
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, n - 1)]
        t = (b - a).normalized()
        nrm = t.cross(up)
        if nrm.length < 1e-4:
            nrm = t.cross(Vector((0, 1, 0)))
        nrm.normalize()
        bn = t.cross(nrm).normalized()
        rn, rb = radii[i]
        w = weights[i] if isinstance(weights[0], list) else weights
        for k in range(segs):
            th = TAU * k / segs
            part.vert(p + nrm * (rn * math.cos(th)) + bn * (rb * math.sin(th)), w, color)
    part.bm.verts.ensure_lookup_table()
    for i in range(n - 1):
        for k in range(segs):
            a = first + i * segs + k
            b = first + i * segs + (k + 1) % segs
            c = first + (i + 1) * segs + (k + 1) % segs
            d = first + (i + 1) * segs + k
            part.face(part.bm.verts[a], part.bm.verts[b], part.bm.verts[c], part.bm.verts[d])
    for index, cap in ((0, cap_start), (n - 1, cap_end)):
        if cap:
            ring = [part.bm.verts[first + index * segs + k] for k in range(segs)]
            part.face(*(ring if index == 0 else ring[::-1]))
    return first
