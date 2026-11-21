extends SceneTree
## Regenerates tests/support/player_identity_golden.json (the fingerprints of 50 fixed player keys). Run ONLY after a deliberate change to how
## player identity is chosen, and after reviewing the portrait contact sheet (gallery section "Portraits"):
##   godot_console --headless --path . --script res://tools/build_identity_golden.gd


func _initialize() -> void:
	var out := {}
	for i in 50:
		var key := "golden:%d" % i
		out[key] = load("res://tests/unit/test_player_identity_golden.gd").fingerprint(key)
	var file := FileAccess.open("res://tests/support/player_identity_golden.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t", true) + "\n")
	file.close()
	print("wrote %d fingerprints" % out.size())
	quit()
