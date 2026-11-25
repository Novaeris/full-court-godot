class_name FcPlayerBaker
extends Node
## Bakes V2 player meshes a little each frame (FcPlayerLod.bake_progressively): the replay opens at once with the morphs shown live, and each mesh
## switches to its baked, LOD-chained version within a second or two. At least one mesh per frame; frees itself when the queue is empty.

var jobs: Array = []
var budget_ms: float = 6.0


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	var done := 0
	while not jobs.is_empty() and (done == 0 or float(Time.get_ticks_usec() - start) / 1000.0 < budget_ms):
		FcPlayerLod._run(jobs.pop_front())
		done += 1
	if jobs.is_empty():
		queue_free()
