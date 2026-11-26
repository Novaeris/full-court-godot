"""Modeling pass on the master garments (D-076): smooths the texture coordinates of the jersey and shorts so the printed graphics, side panels and
piping follow straight, even lines instead of the irregular body-mesh layout they were cut from. The seam (back centre, u = 0/1) stays put.
    blender -b art_source/players/fc_master_player.blend --python tools/blender/master/pass_uv_smooth.py -- --label <label> [--iterations 12]
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import master_lib as M  # noqa: E402


def smooth_uv(obj, iterations):
    me = obj.data
    layer = me.uv_layers.active
    n = len(me.vertices)
    acc = [[0.0, 0.0, 0] for _ in range(n)]
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.loops[li].vertex_index
            u = layer.data[li].uv
            acc[v][0] += u.x % 1.0
            acc[v][1] += u.y
            acc[v][2] += 1
    uv = [(a[0] / a[2], a[1] / a[2]) if a[2] else (0.0, 0.0) for a in acc]
    nbrs = [[] for _ in range(n)]
    for e in me.edges:
        a, b = e.vertices
        nbrs[a].append(b)
        nbrs[b].append(a)
    border = {i for i in range(n) if len(nbrs[i]) < 4}
    for _ in range(iterations):
        new = list(uv)
        for i in range(n):
            if i in border or not nbrs[i] or uv[i][0] < 0.08 or uv[i][0] > 0.92:
                continue   # keep the edges and the seam region fixed
            su = sum(uv[j][0] for j in nbrs[i]) / len(nbrs[i])
            sv = sum(uv[j][1] for j in nbrs[i]) / len(nbrs[i])
            new[i] = (uv[i][0] * 0.5 + su * 0.5, uv[i][1] * 0.5 + sv * 0.5)
        uv = new
    for poly in me.polygons:
        coords = [list(uv[me.loops[li].vertex_index]) for li in poly.loop_indices]
        us = [c[0] for c in coords]
        if max(us) - min(us) > 0.5:
            for c in coords:
                if c[0] < 0.5:
                    c[0] += 1.0
        for li, c in zip(poly.loop_indices, coords):
            layer.data[li].uv = c


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    label = argv[argv.index("--label") + 1]
    iterations = int(argv[argv.index("--iterations") + 1]) if "--iterations" in argv else 12
    for name in ("jersey", "shorts"):
        smooth_uv(bpy.data.objects[name], iterations)
    arm = bpy.data.objects["Armature"]
    history = list(arm.get("fc_master_passes", []))
    history.append("%s: garment UV smoothed x%d" % (label, iterations))
    arm["fc_master_passes"] = history
    print("FC_PASS", label)
    M.save_master(label)


main()
