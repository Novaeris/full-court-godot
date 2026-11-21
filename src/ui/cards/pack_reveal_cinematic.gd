class_name FcPackRevealCinematic
extends FcPackReveal
## The five-stage pack opening (D-059, approved; the default). It is a drop-in replacement for FcPackReveal (same setup(), same signals, same
## `entries`, `effects_log`, `reveal_next`, `reveal_all`); the Dynasty pack screen uses it unless the player chose the Quick style in Settings
## (FcPreferences.pack_reveal_style), which keeps the plain FcPackReveal. Presentation grows with the rarity (data/ui/reveal_effects.json):
## common and uncommon turn over in their place (quick), rare comes forward briefly, epic and legendary get the full treatment.
##   1 PRESENT   the pack stands large with a rarity-tinted halo and a gentle pulse ("tap to open")
##   2 OPENING   the pack shakes, tears, light bursts out and the cards emerge face down in a row
##   3 REVEALING each card comes forward into a spotlight, builds tension (a glow, a swell), turns over, and lands in its place
##   4 (inside 3) epic and legendary cards get the special treatment: dimmed room, rays, shake, banner, name plate, a low hit
##   5 SUMMARY   the existing summary (best first, NEW and DUPLICATE marked, shard values, collection progress)
## INTEGRITY (unchanged): the opening was rolled, paid for and SAVED before this exists. This control only READS `entries` (never edited,
## never reordered), draws them in the order they were rolled and writes nothing. What each rarity looks like comes from data
## (FcRevealSpec). Skip (`reveal_all`) kills every tween, clears every effect, and produces exactly the same `effects_log` cards, the same
## summary and the same final state as watching. Reduced motion: no pack show, spotlight, particles, flash, shake or dim.

enum Phase { PRESENT, OPENING, REVEALING, SUMMARY }

const STAGE_HEIGHT := 660.0
const SPOT_TOP := 104.0
const PACK_BIG := Vector2(225, 315)

var phase: Phase = Phase.PRESENT
var fx: FcRevealFx = FcRevealFx.new()
var spotlight: FcCardFace = null
## What was staged, in order: [{stage, index, rarity}]; tests and the storyboard read it. Nothing reads it back into the game.
var presentation_log: Array = []
var _pack: FcPackArt = null
var _aura: _Aura = null
var _pack_tween: Tween = null
var _land_tween: Tween = null
var _tweens: Array = []
var _row_size := FcCardFace.SIZE_SMALL
var _pending_index := -1   # the card in the spotlight waiting to land (-1 none)
var _last_big_cue_ms := -100000
var _plate: Label = null


## A soft halo behind the pack in its tier colour.
class _Aura extends Control:
	var color := Color.WHITE
	var strength := 0.6:
		set(v):
			strength = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		for i in 9:
			var f := 1.0 - float(i) / 9.0
			draw_circle(c, size.x * 0.5 * f, Color(color, 0.05 * strength))


func _play_intro(pack_listing: Dictionary) -> void:
	_stage_box.custom_minimum_size = Vector2(300, STAGE_HEIGHT)
	_row_size = FcCardFace.SIZE_SMALL if entries.size() <= 7 else FcCardFace.SIZE_MINI
	_cards_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_cards_row.offset_top = -(_row_size.y + 8.0)
	_cards_row.alignment = FlowContainer.ALIGNMENT_CENTER
	for i in _faces.size():
		_faces[i].custom_minimum_size = _row_size
		_faces[i].size = _row_size
		_faces[i].modulate.a = 1.0
	fx.seed_from(str(opening.get("opening_id", "")))
	_stage_box.add_child(fx)
	if not is_inside_tree() or FcMotion.reduced:
		_enter_revealing()   # no show: the cards are simply there, face down
		return
	_cards_row.modulate.a = 0.0
	var tier := FcPackArt.tier_color(FcPackArt.tier_of(pack_listing))
	_aura = _Aura.new()
	_aura.color = tier
	_stage_box.add_child(_aura)
	_pack = FcPackArt.new().setup(pack_listing, PACK_BIG)
	_pack.size = PACK_BIG
	_pack.mouse_filter = Control.MOUSE_FILTER_STOP
	_pack.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_pack.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
			open_pack())
	_stage_box.add_child(_pack)
	_layout_pack.call_deferred()
	var stages := FcRevealSpec.stages()
	_pack_tween = _own_tween().set_loops()
	_pack_tween.tween_property(_aura, "strength", 1.0, float(stages["present_pulse"]) / 2.0).set_trans(Tween.TRANS_SINE)
	_pack_tween.tween_property(_aura, "strength", 0.45, float(stages["present_pulse"]) / 2.0).set_trans(Tween.TRANS_SINE)
	presentation_log.append({"stage": "present", "index": -1, "rarity": ""})
	_update_status()
	_build_actions()


func _layout_pack() -> void:
	if _pack == null or not is_instance_valid(_pack):
		return
	var w := _stage_box.size.x if _stage_box.size.x > 0.0 else size.x
	_pack.position = Vector2((w - PACK_BIG.x) / 2.0, 40.0)
	_pack.pivot_offset = PACK_BIG / 2.0
	_aura.size = PACK_BIG * 2.1
	_aura.position = _pack.position + PACK_BIG / 2.0 - _aura.size / 2.0


## Stage 2: tears the pack open and brings the cards out. `animate` false (skip, reduced motion) goes straight to the cards.
func open_pack(animate: bool = true) -> void:
	if phase != Phase.PRESENT:
		return
	phase = Phase.OPENING
	presentation_log.append({"stage": "open", "index": -1, "rarity": ""})
	_update_status()
	if _pack_tween != null and _pack_tween.is_valid():
		_pack_tween.kill()
	if not animate or FcMotion.reduced or not is_inside_tree() or _pack == null:
		_enter_revealing()
		return
	var stages := FcRevealSpec.stages()
	_layout_pack()
	var center := _pack.position + PACK_BIG / 2.0
	var tier := FcPackArt.tier_color(_pack.tier)
	var tw := _own_tween()
	tw.tween_property(_pack, "rotation", 0.05, 0.06)
	tw.tween_property(_pack, "rotation", -0.05, 0.08)
	tw.tween_property(_pack, "rotation", 0.03, 0.06)
	tw.tween_property(_pack, "rotation", 0.0, 0.05)
	tw.tween_callback(func() -> void:
		FcAudio.cue("pack_tear")
		_pack.tear(float(stages["tear"]))
		fx.burst(center + Vector2(0, -PACK_BIG.y * 0.3), tier, 36, 300.0)
		fx.rays(center, tier, 12, 0.9)
		fx.flash(tier, 0.1, 0.3))
	tw.tween_interval(float(stages["tear"]))
	tw.tween_callback(func() -> void:
		if is_instance_valid(_pack):
			FcMotion.fade_out(_pack, 0.18, true)
		if is_instance_valid(_aura):
			FcMotion.fade_out(_aura, 0.25, true)
		_emerge_cards())
	tw.tween_interval(float(stages["emerge"]) + float(stages["emerge_stagger"]) * float(entries.size()))
	tw.tween_callback(_enter_revealing)


## The face-down cards come out of the wrapper one after another (alpha and scale only; the layout is left to the container).
func _emerge_cards() -> void:
	var stages := FcRevealSpec.stages()
	_cards_row.modulate.a = 1.0
	for i in _faces.size():
		var face := _faces[i]
		face.modulate.a = 0.0
		face.pivot_offset = _row_size / 2.0
		face.scale = Vector2(0.4, 0.4)
		var tw := _own_tween().set_parallel(true)
		tw.tween_property(face, "modulate:a", 1.0, 0.2).set_delay(float(stages["emerge_stagger"]) * i)
		tw.tween_property(face, "scale", Vector2.ONE, float(stages["emerge"])).set_delay(float(stages["emerge_stagger"]) * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	presentation_log.append({"stage": "emerge", "index": -1, "rarity": ""})


func _enter_revealing() -> void:
	if phase == Phase.SUMMARY:
		return
	phase = Phase.REVEALING
	if is_instance_valid(_pack):
		_pack.queue_free()
		_pack = null
	if is_instance_valid(_aura):
		_aura.queue_free()
		_aura = null
	_cards_row.modulate.a = 1.0
	for face in _faces:
		face.modulate.a = 1.0
		face.scale = Vector2.ONE
	_update_status()
	_build_actions()


# --- stage 3 and 4: the cards ------------------------------------------------------------------------------------------

## Turns the next card over. Animated: the card comes forward, builds tension, turns, and its effects play; the player continues with the
## next tap. Not animated (skip, reduced motion): it simply turns over in its place. The committed result is identical either way.
func reveal_next(animate: bool = true) -> void:
	if stage != Stage.REVEALING:
		return
	if phase == Phase.PRESENT:
		open_pack(animate)
		if phase == Phase.PRESENT or phase == Phase.OPENING:
			return
	if phase == Phase.OPENING:
		return
	# a card still in the spotlight lands first; after the last one, the next tap shows the summary
	if _pending_index >= 0:
		_land_spotlight(animate)
		if next_index >= entries.size():
			_finish()
			return
		if animate:
			_begin_card.call_deferred(animate)   # let the landing start before the next card comes forward
			return
	_begin_card(animate)


func _begin_card(animate: bool) -> void:
	if stage != Stage.REVEALING or next_index >= entries.size() or _pending_index >= 0:
		return
	var i := next_index
	next_index += 1
	var rarity := str(_rows[i].get("rarity", "common"))
	var intensity := FcRarityStyle.intensity(rarity)
	var spec := FcRevealSpec.of(rarity)
	var quiet := not animate or FcMotion.reduced or not is_inside_tree()
	effects_log.append({"index": i, "card_id": str(entries[i]["card_id"]), "rarity": rarity, "intensity": intensity, "quiet": quiet})
	presentation_log.append({"stage": "card", "index": i, "rarity": rarity})
	card_revealed.emit(i, entries[i], intensity)
	if quiet:
		_turn_row_face(i, false)
		if next_index >= entries.size():
			_finish()
		else:
			_update_status()
			_build_actions()
		return
	if not bool(spec["spotlight"]):
		_quick_turn(i, rarity, spec)   # common and uncommon: one tap, the card turns over where it lies
		return
	_pending_index = i
	_spotlight_card(i, rarity, spec)
	_update_status()
	_build_actions()


## The quick presentation: the card turns over in its row with its rarity glow (and a few sparks for uncommon). No spotlight, no waiting.
func _quick_turn(i: int, rarity: String, spec: Dictionary) -> void:
	var face := _faces[i]
	face.setup(_rows[i], {"tag": "NEW" if bool(entries[i]["new"]) else "DUPLICATE", "face_down": true, "size": _row_size})
	var flip := face.flip_to(false, float(spec["flip"]))
	var intensity := FcRarityStyle.intensity(rarity)
	if float(spec["glow"]) > 0.0:
		face.set_glow(float(spec["glow"]))
	if int(spec["particles"]) > 0 and face.is_inside_tree() and fx.is_inside_tree():
		fx.burst(face.global_position - fx.global_position + face.size / 2.0, FcRarityStyle.color(rarity), int(spec["particles"]), 160.0)
	_cue("rarity_%d" % clampi(intensity, 0, 4), intensity)
	presentation_log.append({"stage": "impact", "index": i, "rarity": rarity})
	if next_index >= entries.size():
		if flip != null:
			flip.finished.connect(_finish, CONNECT_ONE_SHOT)
		else:
			_finish()
		return
	_update_status()
	_build_actions()


func _spotlight_card(i: int, rarity: String, spec: Dictionary) -> void:
	var stages := FcRevealSpec.stages()
	var color := FcRarityStyle.color(rarity)
	var w := _stage_box.size.x if _stage_box.size.x > 0.0 else size.x
	var spot_size := FcCardFace.SIZE_DETAIL
	spotlight = FcCardFace.new().setup({}, {"face_down": true, "size": spot_size})
	spotlight.size = spot_size
	spotlight.position = Vector2((w - spot_size.x) / 2.0, SPOT_TOP)
	spotlight.pivot_offset = spot_size / 2.0
	spotlight.tease_color = color
	spotlight.activated.connect(func() -> void: reveal_next())
	_stage_box.add_child(spotlight)
	var center := spotlight.position + spot_size / 2.0
	var tw := _own_tween()
	spotlight.scale = Vector2(0.55, 0.55)
	spotlight.modulate.a = 0.0
	var intro := _own_tween().set_parallel(true)
	intro.tween_property(spotlight, "scale", Vector2.ONE, float(stages["spotlight_in"])).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	intro.tween_property(spotlight, "modulate:a", 1.0, float(stages["spotlight_in"]))
	fx.dim(float(spec["dim"]), 0.3)
	# the tease: a glow that builds on the card back, rays behind it, a swell, a trembling card (epic and up)
	var tease := float(spec["tease"])
	if tease > 0.0:
		var audio := FcRevealSpec.audio()
		if bool(spec["swell"]):
			FcAudio.cue(str(audio["swell"]))
		if int(spec["rays"]) > 0:
			fx.rays(center, color, int(spec["rays"]), tease + 0.8)
		tw.tween_interval(float(stages["spotlight_in"]))
		tw.tween_property(spotlight, "tease", 1.0, tease)
		if float(spec["shake"]) > 0.0:
			var tremble := _own_tween().set_loops(maxi(1, int(tease / 0.08)))
			tremble.tween_property(spotlight, "rotation", 0.012, 0.04)
			tremble.tween_property(spotlight, "rotation", -0.012, 0.04)
			_tweens.append(tremble)
	else:
		tw.tween_interval(float(stages["spotlight_in"]))
	tw.tween_callback(_turn_spotlight.bind(i, rarity, spec))


func _turn_spotlight(i: int, rarity: String, spec: Dictionary) -> void:
	if spotlight == null or not is_instance_valid(spotlight):
		return
	spotlight.rotation = 0.0
	spotlight.setup(_rows[i], {"tag": "NEW" if bool(entries[i]["new"]) else "DUPLICATE", "face_down": true, "size": FcCardFace.SIZE_DETAIL})
	spotlight.tease = 0.0
	var flip := spotlight.flip_to(false, float(spec["flip"]))
	if flip != null:
		flip.finished.connect(_impact.bind(i, rarity, spec), CONNECT_ONE_SHOT)
	else:
		_impact(i, rarity, spec)


## The moment the card is face up: sparks, a shockwave, a flash, a shake, a banner, the sting and (for the big ones) a low hit and a name plate.
func _impact(i: int, rarity: String, spec: Dictionary) -> void:
	if spotlight == null or not is_instance_valid(spotlight) or _pending_index != i:
		return
	var color := FcRarityStyle.color(rarity)
	var center := spotlight.position + FcCardFace.SIZE_DETAIL / 2.0
	var intensity := FcRarityStyle.intensity(rarity)
	if float(spec["glow"]) > 0.0:
		spotlight.set_glow(float(spec["glow"]))
	if bool(spec["sweep"]):
		spotlight.play_sweep()
	fx.burst(center, color, int(spec["particles"]), 220.0 + 60.0 * intensity)
	if bool(spec["shockwave"]):
		fx.shockwave(center, color)
	fx.flash(color, float(spec["flash"]))
	if float(spec["shake"]) > 0.0:
		_shake_card(spotlight, float(spec["shake"]))
	if bool(spec["banner"]):
		if str(spec["banner_text"]) == "name":
			fx.banner(str(_rows[i].get("name", "?")), color, 1.6, FcRarityStyle.label(rarity).to_upper())   # the player is the centrepiece, the rarity supports
		else:
			fx.banner(FcRarityStyle.label(rarity).to_upper() + "!", color)
	_cue("rarity_%d" % clampi(intensity, 0, 4), intensity)
	if bool(spec["hit"]):
		_cue(str(FcRevealSpec.audio()["hit"]), intensity)
	if int(spec["haptic"]) > 0 and FcAudio.current != null:
		FcAudio.current.haptic(int(spec["haptic"]))
	if bool(spec["name_plate"]):
		_name_plate(i, color)
	presentation_log.append({"stage": "special" if intensity >= 3 else "impact", "index": i, "rarity": rarity})
	_update_status()


func _name_plate(i: int, color: Color) -> void:
	var plate_text := "%s  %d" % [str(_rows[i].get("name", "?")), int(_rows[i].get("overall", 0))]
	if str(FcRevealSpec.of(str(_rows[i].get("rarity", "common")))["banner_text"]) == "name" and bool(FcRevealSpec.of(str(_rows[i].get("rarity", "common")))["banner"]):
		var bits: Array = []
		for part in [str(_rows[i].get("position", "")), str(_rows[i].get("team", ""))]:
			if part != "":
				bits.append(part)
		plate_text = " · ".join(PackedStringArray(bits))   # the name is already the banner
	_plate = FcUiTables.label(plate_text, FcUiTokens.TYPE_H2, true)
	_plate.add_theme_color_override("font_color", color.lightened(0.35))
	_plate.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_plate.add_theme_constant_override("outline_size", 6)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.size = Vector2(FcCardFace.SIZE_DETAIL.x + 80.0, 30.0)
	_plate.position = Vector2(-40.0, FcCardFace.SIZE_DETAIL.y + 6.0)
	spotlight.add_child(_plate)
	FcMotion.fade_in(_plate, 0.25)


## A short shake of a card (it settles back to where it was).
func _shake_card(node: Control, amplitude: float) -> void:
	if FcMotion.reduced:
		return
	var home := node.position
	var tw := _own_tween()
	for k in 5:
		tw.tween_property(node, "position:x", home.x + (amplitude if k % 2 == 0 else -amplitude) * (1.0 - float(k) / 6.0), 0.04)
	tw.tween_property(node, "position:x", home.x, 0.04)


## Plays a cue unless a big one started a moment ago and this one is small (so a quick run of cards never layers stings into noise).
func _cue(id: String, intensity: int) -> void:
	var now := Time.get_ticks_msec()
	var gap := int(float(FcRevealSpec.audio()["min_gap_after_big"]) * 1000.0)
	if intensity <= 1 and now - _last_big_cue_ms < gap:
		return
	if intensity >= 3:
		_last_big_cue_ms = now
	FcAudio.cue(id)


## The spotlight card lands in its place in the row (the row card turns face up there) and the room lights up again.
func _land_spotlight(animate: bool) -> void:
	var i := _pending_index
	_pending_index = -1
	if i < 0:
		return
	fx.dim(0.0, 0.25 if animate else 0.0)
	var card := spotlight
	spotlight = null
	_plate = null
	if card == null or not is_instance_valid(card):
		_turn_row_face(i, false)
		return
	var stages := FcRevealSpec.stages()
	if not animate or FcMotion.reduced or not card.is_inside_tree():
		card.queue_free()
		_turn_row_face(i, false)
		return
	var target := _faces[i].global_position - _stage_box.global_position + _row_size / 2.0 - FcCardFace.SIZE_DETAIL / 2.0
	var tw := _own_tween().set_parallel(true)
	tw.tween_property(card, "position", target, float(stages["settle"])).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "scale", _row_size / FcCardFace.SIZE_DETAIL, float(stages["settle"])).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(card):
			card.queue_free()
		_turn_row_face(i, false))
	_land_tween = tw


func _turn_row_face(i: int, _celebrate_it: bool) -> void:
	var face := _faces[i]
	face.setup(_rows[i], {"tag": "NEW" if bool(entries[i]["new"]) else "DUPLICATE", "face_down": true, "size": _row_size})
	face.flip_to(false, 0.0)
	face.modulate.a = 1.0


## Skip: every remaining card turns over in place at once, every tween and effect stops, and the summary shows. The same result as watching.
func reveal_all() -> void:
	_kill_presentation()
	if phase == Phase.PRESENT or phase == Phase.OPENING:
		phase = Phase.PRESENT
		open_pack(false)
	if _pending_index >= 0:
		_land_spotlight(false)
	while stage == Stage.REVEALING and next_index < entries.size():
		reveal_next(false)
	if stage == Stage.REVEALING:
		_finish()


## After the last card: the next tap (or the Continue button) shows the summary.
func _finish() -> void:
	_kill_presentation()
	phase = Phase.SUMMARY
	presentation_log.append({"stage": "summary", "index": -1, "rarity": ""})
	_show_summary()


func _show_summary() -> void:
	fx.stop_all()
	super._show_summary()


# --- status, buttons, cleanup ---------------------------------------------------------------------------------------------

func _update_status() -> void:
	if stage != Stage.REVEALING:
		return
	match phase:
		Phase.PRESENT:
			status.text = "Tap the pack to open it."
		Phase.OPENING:
			status.text = "Opening..."
		_:
			if _pending_index >= 0:
				var r := str(_rows[_pending_index].get("rarity", "common"))
				status.text = "%s! Tap to continue." % FcRarityStyle.label(r) if FcRarityStyle.intensity(r) >= 2 else "Tap to continue."
			else:
				status.text = "Card %d of %d. Click the card to reveal it." % [mini(next_index + 1, entries.size()), entries.size()]


func _build_actions() -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	if stage != Stage.REVEALING:
		super._build_actions()
		return
	var label := "Open pack" if phase == Phase.PRESENT else ("Continue" if _pending_index >= 0 else "Reveal next")
	if _pending_index >= 0 and next_index >= entries.size():
		label = "See your pull"
	_actions.add_child(FcButton.make(label, FcButton.Variant.PRIMARY, func() -> void: reveal_next()))
	_actions.add_child(FcButton.make("Skip animation (reveal all)", FcButton.Variant.SECONDARY, reveal_all))


func _own_tween() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


## Stops every tween, effect and pending timer of the show (Skip and the summary call this; the tweens belong to this node, so freeing the
## node does the same).
func _kill_presentation() -> void:
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	_pack_tween = null
	fx.stop_all()
	if spotlight != null and is_instance_valid(spotlight):
		spotlight.rotation = 0.0
	if is_instance_valid(_pack):
		_pack.queue_free()
		_pack = null
	if is_instance_valid(_aura):
		_aura.queue_free()
		_aura = null
	for face in _faces:
		if is_instance_valid(face):
			face.modulate.a = 1.0
			face.scale = Vector2.ONE
	_cards_row.modulate.a = 1.0
	_cards_row.position.x = 0.0
