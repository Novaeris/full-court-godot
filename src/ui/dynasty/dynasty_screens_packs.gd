class_name FcDynastyScreensPacks
extends RefCounted
## The pack market (published prices and odds), the pack-opening reveal, and direct card acquisition.
## The cards of a pack are already in the collection and saved before the reveal starts; the screen only shows them.


static func build_packs(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_child(ui.heading("Pack Market"))
	var pending := ctl.pending_openings()
	for o in pending:
		var p := ui.panel([FcUiTables.label("A pack is waiting to be revealed (%s)." % ctl.catalog.packs().get(o["pack_id"], {}).get("name", o["pack_id"]), 16, true),
			FcUiTables.button("Continue the reveal", func() -> void: show_reveal(ui, o))])
		root.add_child(p)
	var packs := ctl.pack_listing()
	if packs.is_empty():
		root.add_child(ui.note("The loaded release publishes no packs for sale yet."))
		return root
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	for pk in packs:
		flow.add_child(_pack_panel(ui, pk))
	root.add_child(flow)
	return root


static func _pack_panel(ui: FcDynastyUi, pk: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(300, 0)
	v.add_child(FcUiTables.label(pk["name"], 20, true))
	v.add_child(FcUiTables.label("%d card%s    Price: %s %s" % [pk["cards_per_pack"], "" if pk["cards_per_pack"] == 1 else "s", FcDynastyStyle._n(pk["amount"]), pk["currency"]], 15))
	if pk["fixed"]:
		v.add_child(ui.note("Always contains exactly these cards (no randomness).", 280))
	else:
		v.add_child(FcUiTables.label("Published odds per card", 13, true))
		for r in FcDynastyContentRules.RARITY_ORDER:
			var w := int(pk["odds"].get(r, 0))
			if w > 0:
				var line := FcUiTables.label("%s   %s%%" % [FcDynastyStyle.rarity_label(r), _percent(w)], 13)
				line.add_theme_color_override("font_color", FcDynastyStyle.rarity_color(r))
				v.add_child(line)
		for g in pk["guarantees"]:
			v.add_child(ui.note("Guaranteed: at least %d %s or better." % [int(g["count"]), str(g["min_rarity"])], 280))
		if not pk["pity"].is_empty():
			v.add_child(ui.note("Bad-luck protection: a %s or better is guaranteed within %d packs (%d since your last)." % [str(pk["pity"]["rarity"]), int(pk["pity"]["after"]), pk["pity_progress"]], 280))
	var buy := FcUiTables.button("Buy and open", func() -> void: _buy(ui, pk))
	buy.disabled = not pk["affordable"]
	buy.tooltip_text = "" if pk["affordable"] else "Not enough %s" % pk["currency"]
	v.add_child(buy)
	return ui.panel([v])


static func _percent(basis_points: int) -> String:
	return "%d.%02d" % [basis_points / 100, basis_points % 100]


static func _buy(ui: FcDynastyUi, pk: Dictionary) -> void:
	var r := ui.ctl.buy_pack(str(pk["pack_id"]))
	if not r.ok:
		ui.say(r.message)
		return
	show_reveal(ui, r.data["opening"])


## The reveal sequence. Click the card (or press Reveal next) to flip the next one; Skip shows everything at once.
static func show_reveal(ui: FcDynastyUi, opening: Dictionary) -> void:
	var ctl := ui.ctl
	var body: Control = ui._body
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var state := {"i": 0}
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	var pack_name := str(ctl.catalog.packs().get(opening["pack_id"], {}).get("name", opening["pack_id"]))
	root.add_child(ui.heading("Opening: %s" % pack_name))
	var status := FcUiTables.label("", 16)
	root.add_child(status)
	var shown := HFlowContainer.new()
	shown.add_theme_constant_override("h_separation", 10)
	shown.add_theme_constant_override("v_separation", 10)
	root.add_child(shown)
	var back_holder := HBoxContainer.new()
	root.add_child(back_holder)
	var actions := HBoxContainer.new()
	root.add_child(actions)
	var entries: Array = opening["cards"]
	var finish := func() -> void:
		var r := ctl.acknowledge_opening(str(opening["opening_id"]))
		ui.report(r, "")
		ui.show_tab("packs")
	# lambdas capture variables by value, so the two that call each other share a Dictionary
	var fns := {}
	var reveal_one := func(animate: bool) -> void:
		var i: int = state["i"]
		if i >= entries.size():
			return
		var e: Dictionary = entries[i]
		var row := ctl.card_detail(str(e["card_id"]))
		row["owned"] = true
		var tag := "NEW" if bool(e["new"]) else "DUPLICATE"
		var w := FcCardView.build(row, {"tag": tag, "on_click": func() -> void: ui.show_card_detail(str(e["card_id"]))})
		shown.add_child(w)
		if animate:
			w.pivot_offset = FcCardView.SIZE / 2.0
			w.scale = Vector2(0.2, 0.2)
			w.modulate.a = 0.0
			var tw := ui.app.create_tween()
			tw.set_parallel(true)
			tw.tween_property(w, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(w, "modulate:a", 1.0, 0.2)
		state["i"] = i + 1
		fns["update"].call()
	fns["update"] = func() -> void:
		for c in back_holder.get_children():
			back_holder.remove_child(c)
			c.queue_free()
		for c in actions.get_children():
			actions.remove_child(c)
			c.queue_free()
		var done: bool = state["i"] >= entries.size()
		if not done:
			status.text = "Card %d of %d. Click the card to reveal it." % [state["i"] + 1, entries.size()]
			back_holder.add_child(FcCardView.build({}, {"face_down": true, "on_click": func() -> void: reveal_one.call(true)}))
			actions.add_child(FcUiTables.button("Reveal next", func() -> void: reveal_one.call(true)))
			actions.add_child(FcUiTables.button("Skip animation (reveal all)", func() -> void:
				while state["i"] < entries.size():
					reveal_one.call(false)))
		else:
			var new_count := 0
			for e in entries:
				new_count += 1 if bool(e["new"]) else 0
			status.text = "Pack opened: %d new card%s, %d duplicate%s. Everything is already in your collection." % [new_count, "" if new_count == 1 else "s", entries.size() - new_count, "" if entries.size() - new_count == 1 else "s"]
			actions.add_child(FcUiTables.button("Done", finish))
	body.add_child(root)
	fns["update"].call()
	# keyboard: Enter or Space reveals the next card
	status.focus_mode = Control.FOCUS_NONE


# --- direct acquisition -------------------------------------------------------------------------------------------

static func build_market(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_child(ui.heading("Player Market"))
	root.add_child(ui.note("Buy specific cards outright at the price published with the content. Packs are the other way to collect.", 600))
	var listing := ctl.market_listing()
	if listing.is_empty():
		root.add_child(ui.note("No cards are listed for sale in the loaded release."))
		return root
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	for item in listing:
		var v := VBoxContainer.new()
		var card: Dictionary = item["card"].duplicate()
		card["owned"] = true
		card["quantity"] = item["owned"]
		v.add_child(FcCardView.build(card, {"caption": "%s %s" % [FcDynastyStyle._n(item["amount"]), item["currency"]], "on_click": func() -> void: ui.show_card_detail(str(card["card_id"]))}))
		var buy := FcUiTables.button("Buy", func() -> void:
			var r := ctl.acquire_card(str(card["card_id"]))
			ui.report(r, "Bought %s." % card["name"])
			ui.refresh())
		buy.disabled = not item["affordable"]
		v.add_child(buy)
		flow.add_child(v)
	root.add_child(flow)
	return root
