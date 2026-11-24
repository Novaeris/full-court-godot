class_name FcBasketball
extends MeshInstance3D
## The 3D basketball (3D overhaul M3): a sphere of the real size (0.39 ft radius) with the pebbled-leather and channels shader (basketball.gdshader), and
## a spin that the view sets from FcBallMotion (backspin on a shot, a rolling dribble, none when held). Presentation only.

## Angular velocity in world space, radians per second.
var spin: Vector3 = Vector3.ZERO


func _init() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = FcBallMotion.RADIUS
	sphere.height = FcBallMotion.RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh = sphere
	var material := ShaderMaterial.new()
	material.shader = load("res://src/ui/broadcast3d/basketball.gdshader") as Shader
	material_override = material
	name = "Basketball"


## Turns the ball by its spin for `delta` seconds.
func advance(delta: float) -> void:
	var rate := spin.length()
	if rate > 0.0001:
		global_rotate(spin / rate, rate * delta)
