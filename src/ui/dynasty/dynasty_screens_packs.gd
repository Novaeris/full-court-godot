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
		var p := ui.panel([FcDynastyUi.wl("A pack is waiting to be revealed (%s)." % ctl.catalog.packs().get(o["pack_id"], {}).get("name", o["pack_id"]), 16, true),
			FcDynastyUi.btn("Continue the reveal", func() -> void: show_reveal(ui, o))])
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
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	var art := FcPackArt.new().setup(pk)
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(art)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(240, 0)
	v.add_child(FcDynastyUi.wl(pk["name"], FcUiTokens.TYPE_H2, true))
	var tier := FcPackArt.tier_of(pk)
	if tier != "fixed":
		var chip := FcDynastyUi.wl("Best pull: %s" % FcRarityStyle.label(tier), FcUiTokens.TYPE_SMALL)
		chip.add_theme_color_override("font_color", FcRarityStyle.color(tier))
		v.add_child(chip)
	v.add_child(FcDynastyUi.wl("%d card%s    Price: %s %s" % [pk["cards_per_pack"], "" if pk["cards_per_pack"] == 1 else "s", FcDynastyStyle._n(pk["amount"]), pk["currency"]], FcUiTokens.TYPE_BODY))
	if str(pk["set_name"]) != "":
		v.add_child(FcDynastyUi.wl("Set: %s%s" % [pk["set_name"], ("  (%s)" % str(pk["window"])) if str(pk["window"]) != "" else ""], FcUiTokens.TYPE_SMALL))
	if pk["fixed"]:
		v.add_child(ui.note("Always contains exactly these cards (no randomness).", 280))
	else:
		v.add_child(FcDynastyUi.wl("Published odds per card", FcUiTokens.TYPE_SMALL, true))
		for r in FcDynastyContentRules.RARITY_ORDER:
			var w := int(pk["odds"].get(r, 0))
			if w > 0:
				var line := FcDynastyUi.wl("%s   %s%%" % [FcDynastyStyle.rarity_label(r), _percent(w)], FcUiTokens.TYPE_SMALL)
				line.add_theme_color_override("font_color", FcDynastyStyle.rarity_color(r))
				v.add_child(line)
		for g in pk["guarantees"]:
			v.add_child(ui.note("Guaranteed: at least %d %s or better." % [int(g["count"]), str(g["min_rarity"])], 280))
		if not pk["pity"].is_empty():
			v.add_child(ui.note("Bad-luck protection: a %s or better is guaranteed within %d packs (%d since your last)." % [str(pk["pity"]["rarity"]), int(pk["pity"]["after"]), pk["pity_progress"]], 280))
	var buy := FcButton.make("Buy and open", FcButton.Variant.PRIMARY, func() -> void: _buy(ui, pk))
	buy.disabled = not pk["affordable"]
	buy.tooltip_text = "" if pk["affordable"] else "Not enough %s" % pk["currency"]
	v.add_child(buy)
	row.add_child(v)
	return ui.panel([row])


static func _percent(basis_points: int) -> String:
	return "%d.%02d" % [basis_points / 100, basis_points % 100]


static func _buy(ui: FcDynastyUi, pk: Dictionary) -> void:
	var r := ui.ctl.buy_pack(str(pk["pack_id"]))
	if not r.ok:
		ui.say(r.message)
		return
	show_reveal(ui, r.data["opening"])


## The reveal sequence (see FcPackReveal). The pack's cards are already in the collection and saved; the screen only presents them and,
## when the player presses Done, acknowledges the opening through the controller (the one call this screen makes).
static func show_reveal(ui: FcDynastyUi, opening: Dictionary) -> void:
	var ctl := ui.ctl
	var body: Control = ui._body
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	var listing := {}
	for pk in ctl.pack_listing():
		if str(pk["pack_id"]) == str(opening["pack_id"]):
			listing = pk
	if listing.is_empty():
		listing = {"name": str(ctl.catalog.packs().get(opening["pack_id"], {}).get("name", opening["pack_id"])), "cards_per_pack": opening["cards"].size(), "fixed": false, "odds": {}}
	var pack_name := str(listing.get("name", opening["pack_id"]))
	var reveal: FcPackReveal = FcPackReveal.new() if ui.app.preferences.pack_reveal_style == "quick" else FcPackRevealCinematic.new()   # Settings: Pack opening
	reveal.setup(opening, pack_name, listing,
		func(card_id: String) -> Dictionary:
			var row := ctl.card_detail(card_id)
			row["owned"] = true
			return row,
		func(rarity: String) -> int: return ctl.catalog.config.shards_for(rarity),
		ctl.collection_progress,
		func() -> void:
			var r := ctl.acknowledge_opening(str(opening["opening_id"]))
			ui.report(r, "")
			ui.show_tab("packs"))
	body.add_child(reveal)


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
		var buy := FcDynastyUi.btn("Buy", func() -> void:
			var r := ctl.acquire_card(str(card["card_id"]))
			ui.report(r, "Bought %s." % card["name"])
			ui.refresh())
		buy.disabled = not item["affordable"]
		v.add_child(buy)
		flow.add_child(v)
	root.add_child(flow)
	return root
