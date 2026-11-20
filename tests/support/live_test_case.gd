class_name FcLiveTestCase
extends FcTestCase
## Base class for live tests (tests/live, run by tests/run_live_tests.gd). Every test gets `host`, an empty Control under the
## scene root, really inside the tree, and may await frames() or seconds(). The statics the UI keeps (motion, touch layout, text
## scale) are put back to their defaults before and after every test.

var host: Control


func before_each() -> void:
	_reset_statics()
	host = Control.new()
	host.size = Vector2(800, 600)
	Engine.get_main_loop().root.add_child(host)


func after_each() -> void:
	if host != null and is_instance_valid(host):
		Engine.get_main_loop().root.remove_child(host)
		host.free()
	_reset_statics()


func _reset_statics() -> void:
	FcMotion.reduced = false
	FcUiTokens.touch_mode = false
	FcUiTheme.build(1)


## Waits for `count` rendered frames.
func frames(count: int = 1) -> void:
	for i in count:
		await Engine.get_main_loop().process_frame


## Waits for real seconds.
func seconds(t: float) -> void:
	await Engine.get_main_loop().create_timer(t).timeout
