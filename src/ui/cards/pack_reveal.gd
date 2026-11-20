class_name FcPackReveal
extends VBoxContainer
## The pack-opening experience: the pack tears open, the cards lie face down, each click turns the next one over (its effect grows with
## its rarity), and a summary shows the whole pull (best first, NEW and DUPLICATE marked, what duplicates are worth, collection progress).
## Skip shows everything at once at any time.
##
## INTEGRITY: the cards were rolled, paid for and SAVED before this is shown (FcDynastyPacks). This control only READS the committed
## `opening` and presents its cards in the order they were rolled. It calls nothing that changes the game; the screen that owns it
## acknowledges the opening when Done is pressed. Animations can neither change nor reorder the result, and skipping gives exactly the
## same result as watching.
## Effects by FcRarityStyle.intensity: 0 a plain flip; 1 a rarity glow; 2 the light sweep; 3 a flash, particles and a short shake;
## 4 the same, bigger, with a banner and a pause. Reduced motion: no particles, flash, shake or pause (the flip is a quick fade swap).
## At most one flash per card and cards are revealed on the player's clicks, so flashes cannot exceed three per second.

signal card_revealed(index: int, entry: Dictionary, intensity: int)
signal finished

enum Stage { REVEALING, SUMMARY }

var stage: Stage = Stage.REVEALING
var opening: Dictionary = {}
var entries: Array = []
var next_index: int = 0
## What was presented, in order: [{index, card_id, rarity, intensity, quiet}]. Tests and the audio layer read it.
var effects_log: Array = []
var status := Label.new()
var _rows: Array = []
var _faces: Array[FcCardFace] = []
var _row_for: Callable
var _shards_for: Callable
var _progress: Callable
var _on_done: Callable
var _pack_name: String = ""
var _stage_box := Control.new()
var _cards_row := HFlowContainer.new()
var _flash := ColorRect.new()
var _actions := HBoxContainer.new()
var _intro: FcPackArt = null
var _done := false


## `opening` is the committed opening record ({opening_id, pack_id, cards: [{card_id, new, quantity}]}). `row_for(card_id)` returns the card
## row to draw; `shards_for(rarity)` what a duplicate of that rarity converts to; `progress()` the collection {owned, total} now;
## `on_done` runs when the player presses Done.
func setup(opening_record: Dictionary, pack_name: String, pack_listing: Dictionary, row_for: Callable, shards_for: Callable, progress: Callable, on_done: Callable) -> void:
	opening = opening_record
	entries = opening_record["cards"]
	_pack_name = pack_name
	_row_for = row_for
	_shards_for = shards_for
	_progress = progress
	_on_done = on_done
	for e in entries:
		_rows.append(row_for.call(str(e["card_id"])))
	add_theme_constant_override("separation", 10)
	add_child(FcUiTables.label("Opening: %s" % pack_name, FcUiTokens.TYPE_H2, true))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_stage_box.custom_minimum_size = Vector2(300, FcCardFace.SIZE_STANDARD.y + 40)
	_stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_stage_box)
	_cards_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards_row.add_theme_constant_override("h_separation", 10)
	_cards_row.add_theme_constant_override("v_separation", 10)
	_stage_box.add_child(_cards_row)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_box.add_child(_flash)
	add_child(_actions)
	for i in entries.size():
		var face := FcCardFace.new().setup({}, {"face_down": true})
		face.focus_mode = Control.FOCUS_ALL
		face.activated.connect(func() -> void: reveal_next())
		face.modulate.a = 1.0 if i == 0 else 0.55
		_cards_row.add_child(face)
		_faces.append(face)
	_build_actions()
	_update_status()
	_play_intro(pack_listing)


## Turns the next card over (animated unless `animate` is false). Does nothing once every card is revealed.
func reveal_next(animate: bool = true) -> void:
	if stage != Stage.REVEALING or next_index >= entries.size():
		return
	var i := next_index
	next_index += 1
	var rarity := str(_rows[i].get("rarity", "common"))
	var intensity := FcRarityStyle.intensity(rarity)
	var face := _faces[i]
	face.setup(_rows[i], {"tag": "NEW" if bool(entries[i]["new"]) else "DUPLICATE", "face_down": true})
	var quiet := not animate or FcMotion.reduced or not is_inside_tree()
	effects_log.append({"index": i, "card_id": str(entries[i]["card_id"]), "rarity": rarity, "intensity": intensity, "quiet": quiet})
	var tw := face.flip_to(false, FcUiTokens.DUR_SLOW if animate else 0.0)
	if not quiet:
		_celebrate(face, rarity, intensity)
	if i + 1 < _faces.size():
		_faces[i + 1].modulate.a = 1.0
	card_revealed.emit(i, entries[i], intensity)
	if next_index >= entries.size():
		if tw != null:
			tw.finished.connect(func() -> void: _after_last(intensity), CONNECT_ONE_SHOT)
		else:
			_show_summary()
	else:
		_update_status()
		_build_actions()


## Reveals every remaining card at once (no animation) and shows the summary. The result is identical to watching.
func reveal_all() -> void:
	while stage == Stage.REVEALING and next_index < entries.size():
		reveal_next(false)
	if stage == Stage.REVEALING:
		_show_summary()


func new_count() -> int:
	var n := 0
	for e in entries:
		n += 1 if bool(e["new"]) else 0
	return n


func _after_last(intensity: int) -> void:
	var pause := 0.0 if FcMotion.reduced else (0.55 if intensity >= 4 else (0.25 if intensity >= 3 else 0.0))
	if pause > 0.0 and is_inside_tree():
		get_tree().create_timer(pause).timeout.connect(_show_summary, CONNECT_ONE_SHOT)
	else:
		_show_summary()


func _update_status() -> void:
	if stage == Stage.REVEALING:
		status.text = "Card %d of %d. Click the card to reveal it." % [mini(next_index + 1, entries.size()), entries.size()]


func _build_actions() -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	if stage == Stage.REVEALING:
		_actions.add_child(FcButton.make("Reveal next", FcButton.Variant.PRIMARY, func() -> void: reveal_next()))
		_actions.add_child(FcButton.make("Skip animation (reveal all)", FcButton.Variant.SECONDARY, reveal_all))
	else:
		_actions.add_child(FcButton.make("Done", FcButton.Variant.PRIMARY, func() -> void:
			if _done:
				return   # a double click must not acknowledge the opening twice
			_done = true
			finished.emit()
			if _on_done.is_valid():
				_on_done.call()))


# --- intro and effects -------------------------------------------------------------------------------------------------

func _play_intro(pack_listing: Dictionary) -> void:
	if not is_inside_tree() or FcMotion.reduced:
		return
	_intro = FcPackArt.new().setup(pack_listing)
	_intro.size = FcPackArt.SIZE
	_intro.position = Vector2(_stage_box.size.x / 2.0 - FcPackArt.SIZE.x / 2.0, 10)
	_intro.z_index = 5
	_stage_box.add_child(_intro)
	_cards_row.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_intro, "rotation", 0.06, 0.07)
	tw.tween_property(_intro, "rotation", -0.06, 0.1)
	tw.tween_property(_intro, "rotation", 0.0, 0.07)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_intro) and _intro.is_inside_tree():
			_intro.tear(0.3))
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void:
		if is_instance_valid(_intro) and _intro.is_inside_tree():
			FcMotion.fade_out(_intro, 0.15, true)
		if is_instance_valid(_cards_row) and _cards_row.is_inside_tree():
			FcMotion.fade_in(_cards_row, 0.2))


func _celebrate(face: FcCardFace, rarity: String, intensity: int) -> void:
	var color := FcRarityStyle.color(rarity)
	if intensity >= 1:
		face.lift = 1.0   # the rarity-coloured glow
	if intensity >= 2:
		face.mouse_entered.emit()   # the light sweep
	if intensity >= 3:
		_burst(face, color, intensity)
		_flash_once(color)
		_shake(intensity)
	if intensity >= 4:
		_banner(FcRarityStyle.label(rarity).to_upper() + "!", color)


func _flash_once(color: Color) -> void:
	_flash.color = Color(color.lightened(0.5), 0.4)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.4)


func _shake(intensity: int) -> void:
	var amp := 3.0 + intensity * 1.5
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_cards_row, "position:x", amp if i % 2 == 0 else -amp, 0.04)
	tw.tween_property(_cards_row, "position:x", 0.0, 0.04)


func _burst(face: FcCardFace, color: Color, intensity: int) -> void:
	var p := CPUParticles2D.new()
	p.amount = 18 * intensity
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 280.0
	p.gravity = Vector2(0, 340)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	p.color = color.lightened(0.3)
	p.position = face.position + face.size / 2.0
	_cards_row.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _banner(text: String, color: Color) -> void:
	var label := FcUiTables.label(text, FcUiTokens.TYPE_DISPLAY_XL, true)
	label.add_theme_color_override("font_color", color.lightened(0.3))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.position.y = 4
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_box.add_child(label)
	FcMotion.pop_in(label, 0.25)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if is_instance_valid(label) and label.is_inside_tree():   # the summary may already have replaced the stage
			FcMotion.fade_out(label, 0.2, true))


# --- summary ---------------------------------------------------------------------------------------------------------

func _show_summary() -> void:
	if stage == Stage.SUMMARY:
		return
	stage = Stage.SUMMARY
	var fresh := new_count()
	var dupes := entries.size() - fresh
	status.text = "Pack opened: %d new card%s, %d duplicate%s. Everything is already in your collection." % [fresh, "" if fresh == 1 else "s", dupes, "" if dupes == 1 else "s"]
	var order: Array = range(entries.size())
	order.sort_custom(func(a: int, b: int) -> bool:   # best first; ties keep the order they were rolled in
		var ra := FcDynastyContentRules.rarity_rank(str(_rows[a].get("rarity", "common")))
		var rb := FcDynastyContentRules.rarity_rank(str(_rows[b].get("rarity", "common")))
		return ra > rb or (ra == rb and a < b))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var first := true
	for i in order:
		var row: Dictionary = _rows[i]
		var is_new := bool(entries[i]["new"])
		var options := {"tag": "NEW" if is_new else "DUPLICATE", "size": FcCardFace.SIZE_STANDARD, "inspected": first}
		if not is_new:
			options["caption"] = "worth %d shards" % int(_shards_for.call(str(row.get("rarity", "common"))))
		grid.add_child(FcCardFace.new().setup(row, options))
		first = false
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	holder.add_child(grid)
	var progress: Dictionary = _progress.call() if _progress.is_valid() else {}
	if not progress.is_empty():
		var owned := int(progress["owned"])
		var total := int(progress["total"])
		var line := FcUiTables.label("Collection: %d of %d cards%s" % [owned, total, "  (%d new)" % fresh if fresh > 0 else ""], FcUiTokens.TYPE_SMALL)
		line.theme_type_variation = "MutedLabel"
		holder.add_child(line)
		var bar := FcProgress.new(FcProgress.Variant.ACCENT)
		bar.set_progress(owned - fresh, total)
		holder.add_child(bar)
		if is_inside_tree():
			bar.set_progress_animated.call_deferred(owned, total)
		else:
			bar.set_progress(owned, total)
	# the summary takes the stage's place (a plain Control does not size itself to its content)
	remove_child(_stage_box)
	_stage_box.queue_free()
	add_child(holder)
	move_child(holder, get_child_count() - 2)
	_build_actions()
