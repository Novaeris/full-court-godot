"""Materials by name. The game recolours a material by its NAME (skin, jersey, ...), so every mesh gets a material called like its surface."""
import bpy


def material(name: str, rgb, roughness=0.6, metallic=0.0, vertex_color=False):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if vertex_color:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        attr = nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat
