"""Modeling pass on the master hair and facial hair (D-076): softens the hair DENSITY (vertex colour) by averaging it over neighbouring vertices, so
fades, tapers, hairlines and beard edges blend instead of stepping; where the hair thins, the shell is pulled toward the scalp so there is no ledge.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/pass_hair.py -- --label <label> [--iterations 6] [--sink 0.006]
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def soften(obj, iterations, sink):
    me = obj.data
    if not me.color_attributes:
        return 0
    col = me.color_attributes[0]
    n = len(me.vertices)
    dens = [0.0] * n
    count = [0] * n
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.loops[li].vertex_index
            dens[v] += col.data[li].color[0]
            count[v] += 1
    dens = [dens[i] / count[i] if count[i] else 1.0 for i in range(n)]
    nbrs = [[] for _ in range(n)]
    for e in me.edges:
        a, b = e.vertices
        nbrs[a].append(b)
        nbrs[b].append(a)
    strand = "_strands" in obj.name   # never applied: strands are joined into the shell, recognised by full density below
    for _ in range(iterations):
        new = dens[:]
        for i in range(n):
            if nbrs[i] and 0.02 < dens[i] < 0.995 or any(0.02 < dens[j] < 0.995 for j in nbrs[i]):
                new[i] = (dens[i] + sum(dens[j] for j in nbrs[i])) / (1 + len(nbrs[i]))
        dens = new
    for poly in me.polygons:
        for li in poly.loop_indices:
            d = dens[me.loops[li].vertex_index]
            col.data[li].color = (d, d, d, 1.0)
    offsets = {}
    if sink > 0:
        for i, v in enumerate(me.vertices):
            if dens[i] < 0.98:
                offsets[i] = -v.normal * sink * (1.0 - dens[i])
        M.move_vertices(obj, offsets)
    return len(offsets)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    label = argv[argv.index("--label") + 1]
    iterations = int(argv[argv.index("--iterations") + 1]) if "--iterations" in argv else 6
    sink = float(argv[argv.index("--sink") + 1]) if "--sink" in argv else 0.006
    report = {}
    for obj in M.meshes_in(["FC_Hair", "FC_Facial"]):
        report[obj.name] = soften(obj, iterations, sink if obj.name.startswith("hair_") else 0.0)
    arm = bpy.data.objects["Armature"]
    history = list(arm.get("fc_master_passes", []))
    history.append("%s: hair density softened x%d, sink %.3f" % (label, iterations, sink))
    arm["fc_master_passes"] = history
    print("FC_PASS %s %s" % (label, report))
    M.save_master(label)


main()
