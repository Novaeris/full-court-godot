extends FcLiveTestCase
## The high-fidelity figure (prototype) draws without script errors for many seeded players, at every size and crop, and does not
## change the shipped default or a resolved visual.


class Probe extends Control:
	var visual: Dictionary = {}
	var mode := "bust"

	func _draw() -> void:
		match mode:
			"full":
				FcPlayerFigure.draw(self, Rect2(Vector2.ZERO, size), visual, true)
			"head":
				FcPlayerFigure.draw_headshot(self, Rect2(Vector2.ZERO, size), visual)
			_:
				FcPlayerFigure.draw(self, Rect2(Vector2.ZERO, size), visual)


func after_each() -> void:
	FcPlayerFigure.hd_enabled = false
	super.after_each()


func test_the_hd_figure_draws_every_look_at_every_size() -> void:
	FcPlayerFigure.hd_enabled = true
	var probes: Array = []
	for i in 40:
		var v := FcPlayerVisual.resolve(FcPlayerPresentation.subject("hdlive:%d" % i, "Live %d" % i, {"name": "T%d" % (i % 5), "abbreviation": "T%d" % (i % 5)}, i))
		v["age"] = 19 + i % 24
		for m in ["bust", "head", "full"]:
			for px in [24, 48, 96, 200]:
				var p := Probe.new()
				p.visual = v
				p.mode = m
				p.size = Vector2(px, px * (2.2 if m == "full" else 1.0))
				host.add_child(p)
				probes.append(p)
	await frames(3)
	assert_eq(probes.size(), 40 * 3 * 4)


func test_the_same_visual_gives_the_same_resolved_description_with_the_switch_on_or_off() -> void:
	var subject := FcPlayerPresentation.subject("hdlive:same", "Same", {}, 4)
	var off := FcPlayerVisual.resolve(subject)
	FcPlayerFigure.hd_enabled = true
	assert_eq(FcPlayerVisual.resolve(subject), off, "the switch is presentation only")
