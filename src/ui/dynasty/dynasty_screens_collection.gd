class_name FcDynastyScreensCollection
extends RefCounted
## Collection browser, card detail window, and the lineup / team builder.

const POSITIONS := ["", "PG", "SG", "SF", "PF", "C"]
const RARITIES := ["", "common", "uncommon", "rare", "epic", "legendary"]
const OWNERSHIP := [["all", "All cards"], ["owned", "Owned"], ["unowned", "Not owned yet"]]
const COMPARE_COMPOSITES := [["three", "3PT"], ["finishing", "FIN"], ["playmaking", "PLAY"], ["perimeter_d", "PER D"], ["interior_d", "INT D"], ["rebound", "REB"]]


# --- collection ---------------------------------------------------------------------------------------------------

static func build_collection(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	var prog := ctl.collection_progress()
	root.add_child(ui.heading("Collection: %d of %d cards" % [prog["owned"], prog["total"]]))
	if ctl.catalog.card_ids().is_empty() and ctl.profile().cards.is_empty():
		root.add_child(ui.note(ctl.catalog.playable_problem()))
		return root
	var f: Dictionary = ui.collection_filters
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 10)
	var search := LineEdit.new()
	search.placeholder_text = "Search name or edition"
	search.text = str(f.get("search", ""))
	search.custom_minimum_size = Vector2(190, 0)
	search.text_submitted.connect(func(t: String) -> void:
		f["search"] = t
		ui.refresh())
	bar.add_child(search)
	bar.add_child(_option(f, "position", POSITIONS, "Any position", ui))
	bar.add_child(_option(f, "rarity", RARITIES, "Any rarity", ui))
	var teams := [""]
	teams.append_array(FcCollectionQuery.teams(ctl.catalog))
	bar.add_child(_option(f, "team", teams, "Any team", ui))
	var own := OptionButton.new()
	for i in OWNERSHIP.size():
		own.add_item(OWNERSHIP[i][1])
		if str(f.get("ownership", "all")) == OWNERSHIP[i][0]:
			own.selected = i
	own.item_selected.connect(func(i: int) -> void:
		f["ownership"] = OWNERSHIP[i][0]
		ui.refresh())
	bar.add_child(own)
	var min_ovr := SpinBox.new()
	min_ovr.prefix = "Min OVR "
	min_ovr.min_value = 0
	min_ovr.max_value = 99
	min_ovr.value = int(f.get("min_overall", 0))
	min_ovr.value_changed.connect(func(v: float) -> void: f["min_overall"] = int(v))
	min_ovr.get_line_edit().text_submitted.connect(func(_t: String) -> void: ui.refresh())
	bar.add_child(min_ovr)
	var sort := OptionButton.new()
	for i in FcCollectionQuery.SORTS.size():
		sort.add_item(FcCollectionQuery.SORT_NAMES[i])
		if FcCollectionQuery.SORTS[i] == ui.collection_sort:
			sort.selected = i
	sort.item_selected.connect(func(i: int) -> void:
		ui.collection_sort = FcCollectionQuery.SORTS[i]
		ui.refresh())
	bar.add_child(sort)
	bar.add_child(FcUiTables.button("Apply", func() -> void:
		f["search"] = search.text
		ui.refresh()))
	bar.add_child(FcUiTables.button("Clear filters", func() -> void:
		ui.collection_filters = {}
		ui.refresh()))
	root.add_child(bar)
	var rows := ctl.collection_rows(f, ui.collection_sort)
	if rows.is_empty():
		root.add_child(ui.note("No cards match these filters."))
		return root
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for row in rows:
		grid.add_child(FcCardView.build(row, {"on_click": func() -> void: ui.show_card_detail(str(row["card_id"]))}))
	root.add_child(grid)
	return root


static func _option(f: Dictionary, key: String, values: Array, any_text: String, ui: FcDynastyUi) -> OptionButton:
	var o := OptionButton.new()
	for i in values.size():
		o.add_item(any_text if str(values[i]) == "" else str(values[i]).capitalize() if key == "rarity" else str(values[i]))
		if str(f.get(key, "")) == str(values[i]):
			o.selected = i
	o.item_selected.connect(func(i: int) -> void:
		f[key] = str(values[i])
		ui.refresh())
	return o


## The card detail window: the actual attributes and badges the simulation uses, plus duplicate actions.
static func show_detail(ui: FcDynastyUi, card_id: String) -> void:
	var ctl := ui.ctl
	var row := ctl.card_detail(card_id)
	if row.is_empty():
		return
	var dialog := AcceptDialog.new()
	dialog.title = "%s: %s" % [row["name"], row["edition"]]
	dialog.min_size = Vector2i(820, 620)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.add_child(FcCardView.build(row, {"size": Vector2(190, 270)}))
	if row["owned"]:
		left.add_child(FcUiTables.label("Copies owned: %d" % row["quantity"]))
		left.add_child(FcUiTables.label("Mastery (cosmetic): level %d, frame %s" % [row["mastery"], ctl.catalog.config.mastery_frame(row["mastery"])]))
		if row["available"]:
			var convert := FcUiTables.button("Convert a duplicate to %d shards" % ctl.catalog.config.shards_for(str(row["rarity"])), func() -> void:
				var r := ctl.convert_duplicate(card_id)
				dialog.queue_free()
				ui.report(r, "Converted a duplicate." if r.ok else "")
				ui.refresh())
			convert.disabled = row["spare"] < 1
			left.add_child(convert)
			var level := int(row["mastery"])
			var cost := ctl.catalog.config.mastery_cost(level)
			var mastery := FcUiTables.button("Raise mastery (1 duplicate + %d shards)" % cost, func() -> void:
				var r := ctl.apply_mastery(card_id)
				dialog.queue_free()
				ui.report(r, "Mastery raised. This changes how the card looks, never how it plays." if r.ok else "")
				ui.refresh())
			mastery.disabled = row["spare"] < 1 or level >= ctl.catalog.config.mastery_max() or ctl.profile().balance("shards") < cost
			left.add_child(mastery)
			left.add_child(ui.note("Duplicates become shards or cosmetic mastery. Ratings, attributes and badges never change.", 220))
	root.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(FcUiTables.label("%s   %s   %s overall" % [FcDynastyStyle.rarity_label(str(row["rarity"])), row["position"], row["overall"]], 18, true))
	if str(row["team"]) != "":
		right.add_child(FcUiTables.label("Team: %s" % row["team"]))
	if not row["available"]:
		right.add_child(ui.note("The loaded content release does not include this card. You still own it; it returns when a release brings it back.", 380))
	else:
		if bool(row["revision_changed"]):
			right.add_child(ui.note("The card's definition was updated by a newer release (revision %d)." % row["revision"], 380))
		var badges: Array = row["badges"]
		if not badges.is_empty():
			right.add_child(FcUiTables.label("Badges", 16, true))
			for b in badges:
				var def := FcBadges.get_badge(str(b))
				right.add_child(ui.note("%s: %s" % [def.get("name", b), def.get("description", "")], 380))
		var rows: Array = []
		var attrs: Dictionary = row["attributes"]
		for key in ctl.defs.attributes.keys():
			rows.append([ctl.defs.attributes.get_def(key).display_name, attrs.get(key, 0), ctl.defs.attributes.get_def(key).category.capitalize()])
		var tree := FcUiTables.table(["Attribute", "Rating", "Group"], rows, [200, 70, 0])
		tree.custom_minimum_size = Vector2(380, 300)
		right.add_child(tree)
	var stats: Dictionary = ctl.profile().card_stats.get(card_id, {})
	if not stats.is_empty() and int(stats["games"]) > 0:
		right.add_child(FcUiTables.label("In your games: %d played, %.1f pts, %.1f reb, %.1f ast per game" % [stats["games"], float(stats["points"]) / stats["games"], float(stats["rebounds"]) / stats["games"], float(stats["assists"]) / stats["games"]]))
	root.add_child(right)
	dialog.add_child(root)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	ui.app.add_child(dialog)
	dialog.popup_centered()


# --- lineup -----------------------------------------------------------------------------------------------------

static func build_lineup(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_child(FcUiTables.label(str(ctl.team_overall()), 44, true))
	var info := VBoxContainer.new()
	info.add_child(FcUiTables.label("Team overall (weighted from your 13 slots: starters count most)", 14))
	var identity := ctl.team_identity()
	info.add_child(FcUiTables.label("Identity: %s" % (", ".join(identity) if not identity.is_empty() else "set a lineup")))
	head.add_child(info)
	root.add_child(head)
	var problems := ctl.lineup_problems()
	if problems.is_empty():
		var ok := FcUiTables.label("Lineup is valid and ready to play.")
		ok.add_theme_color_override("font_color", FcUiTheme.GOOD)
		root.add_child(ok)
	else:
		for p in problems.slice(0, 4):
			var l := FcUiTables.label("Problem: %s" % p)
			l.add_theme_color_override("font_color", FcUiTheme.BAD)
			root.add_child(l)
		if problems.size() > 4:
			root.add_child(FcUiTables.label("...and %d more." % (problems.size() - 4)))
	root.add_child(FcUiTables.button("Auto-fill the recommended lineup", func() -> void:
		var r := ctl.auto_fill_lineup()
		ui.report(r, "Lineup set to the best players you own, by position.")
		ui.refresh()))
	root.add_child(ui.note("Starters must be able to play their slot's position (primary or secondary). Bench order is the substitution order. Rotation: give a player fewer or more minutes. One edition per real player.", 700))
	var groups := [["Starters", 0, 5], ["Bench", 5, 12], ["Reserve", 12, 13]]
	var views := ctl.roster_view()
	for g in groups:
		root.add_child(ui.heading(g[0]))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		for i in range(g[1], g[2]):
			flow.add_child(_slot_widget(ui, views[i]))
		root.add_child(flow)
	return root


static func _slot_widget(ui: FcDynastyUi, slot_view: Dictionary) -> Control:
	var ctl := ui.ctl
	var slot: int = slot_view["slot"]
	var v := VBoxContainer.new()
	v.add_child(FcUiTables.label(slot_view["name"], 13, true))
	var card: Dictionary = slot_view["card"]
	if card.is_empty():
		var empty := FcCardView.build({"name": "Empty", "overall": 0, "rarity": "common", "available": true, "owned": true, "position": "", "edition": "Choose a player", "art_path": ""},
			{"size": FcCardView.SMALL, "on_click": func() -> void: _pick(ui, slot)})
		v.add_child(empty)
	else:
		v.add_child(FcCardView.build(card, {"size": FcCardView.SMALL, "on_click": func() -> void: _pick(ui, slot)}))
	var row := HBoxContainer.new()
	var minutes := OptionButton.new()
	for m in ["Fewer min", "Normal", "More min"]:
		minutes.add_item(m)
	minutes.selected = int(slot_view["minutes"]) + 1
	minutes.item_selected.connect(func(i: int) -> void:
		ctl.set_minutes(slot, i - 1)
		ui.say("Rotation updated."))
	minutes.disabled = card.is_empty()
	row.add_child(minutes)
	var clear := FcUiTables.button("X", func() -> void:
		ctl.clear_slot(slot)
		ui.refresh())
	clear.tooltip_text = "Remove this player from the slot"
	clear.disabled = card.is_empty()
	row.add_child(clear)
	v.add_child(row)
	return v


## The card picker for a slot: every usable owned card, with a comparison against the current player.
static func _pick(ui: FcDynastyUi, slot: int) -> void:
	var ctl := ui.ctl
	var current_id := str(ctl.profile().roster.slots[slot])
	var current := ctl.catalog.view(current_id) if current_id != "" else {}
	var dialog := AcceptDialog.new()
	dialog.title = "Choose a player for %s" % FcDynastyRoster.slot_name(slot)
	dialog.min_size = Vector2i(860, 560)
	var candidates := ctl.candidates_for(slot)
	var cols := ["Player", "Edition", "Pos", "OVR", "vs current"]
	for c in COMPARE_COMPOSITES:
		cols.append(c[1])
	var rows: Array = []
	for v in candidates:
		var comps := ctl.catalog.ratings.compute(ctl.catalog.make_player(str(v["card_id"]), 1))
		var diff := ""
		if not current.is_empty():
			diff = "%+d" % (int(v["overall"]) - int(current["overall"]))
		var row := [v["name"], v["edition"], v["position"], v["overall"], diff]
		for c in COMPARE_COMPOSITES:
			row.append(roundi(float(comps.get(c[0], 0.0))))
		rows.append(row)
	var tree := FcUiTables.table(cols, rows)
	tree.custom_minimum_size = Vector2(800, 400)
	tree.item_activated.connect(func() -> void:
		var item := tree.get_selected()
		if item == null:
			return
		_choose(ui, dialog, slot, str(candidates[item.get_index()]["card_id"])))
	var box := VBoxContainer.new()
	box.add_child(ui.note("Double-click a row or select it and press Choose. Compare overall and key ratings with your current player." if not candidates.is_empty() else "You do not own a card that can play this slot.", 800))
	box.add_child(tree)
	var choose := FcUiTables.button("Choose selected player", func() -> void:
		var item := tree.get_selected()
		if item != null:
			_choose(ui, dialog, slot, str(candidates[item.get_index()]["card_id"])))
	choose.disabled = candidates.is_empty()
	box.add_child(choose)
	dialog.add_child(box)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	ui.app.add_child(dialog)
	dialog.popup_centered()


static func _choose(ui: FcDynastyUi, dialog: Window, slot: int, card_id: String) -> void:
	var r := ui.ctl.assign_slot(slot, card_id)
	dialog.queue_free()
	ui.report(r, "Lineup updated.")
	ui.refresh()
