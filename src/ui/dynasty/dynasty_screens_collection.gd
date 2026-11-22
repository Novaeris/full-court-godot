class_name FcDynastyScreensCollection
extends RefCounted
## Collection browser, card detail window, and the lineup / team builder.

const POSITIONS := [""] + FcPosition.PLAYABLE
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
		root.add_child(FcEmptyState.new("No cards yet", ctl.catalog.playable_problem()))
		return root
	var completion := FcCompletionPanel.build(FcCompletion.compute(ctl.collection_rows({}, "overall_desc")))
	root.add_child(completion)
	var f: Dictionary = ui.collection_filters
	var bar := FcFilterBar.new()
	bar.add_search("search", "Search name or edition")
	bar.add_dropdown("position", "Any position", _pairs(POSITIONS.slice(1)))
	bar.add_chips("rarity", _rarity_pairs(), false)
	var teams := FcCollectionQuery.teams(ctl.catalog)
	bar.add_dropdown("team", "Any team", _pairs(teams))
	bar.add_dropdown("ownership", "All cards", [["Owned", "owned"], ["Not owned yet", "unowned"]])
	bar.add_dropdown("min_overall", "Any overall", [["60+", 60], ["70+", 70], ["80+", 80], ["90+", 90]])
	bar.add_clear_button("Clear filters")
	bar.set_values(_to_bar(f))
	root.add_child(bar)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	var sort := FcDropdown.new()
	var sort_items: Array = []
	for i in FcCollectionQuery.SORTS.size():
		sort_items.append([FcCollectionQuery.SORT_NAMES[i], FcCollectionQuery.SORTS[i]])
	sort.set_items(sort_items, ui.collection_sort)
	tools.add_child(FcDynastyUi.wl("Sort", FcUiTokens.TYPE_SMALL))
	tools.add_child(sort)
	var view := FcChoiceGroup.new()
	view.set_options([["grid", "Grid"], ["carousel", "Carousel"]], str(ui.app.ui_state.get_value("collection", "view", "grid")))
	tools.add_child(view)
	root.add_child(tools)
	var holder := VBoxContainer.new()
	root.add_child(holder)
	completion.visible = view.current_id != "carousel"   # the carousel needs the room
	var refill := func(mode: String) -> void:
		completion.visible = mode != "carousel"
		_fill_results(ui, holder, mode)
	bar.changed.connect(func(values: Dictionary) -> void:
		ui.collection_filters = _to_query(values)
		refill.call(view.current_id))
	sort.chosen.connect(func(value) -> void:
		ui.collection_sort = str(value)
		refill.call(view.current_id))
	view.selected.connect(func(id: String) -> void:
		ui.app.ui_state.set_value("collection", "view", id)
		refill.call(id))
	refill.call(view.current_id)
	return root


static func _pairs(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append([str(v), v])
	return out


static func _rarity_pairs() -> Array:
	var out: Array = []
	for r in RARITIES.slice(1):
		out.append([FcRarityStyle.label(r), r])
	return out


## The query filters (empty ones left out) as the filter bar's values, and back.
static func _to_bar(query: Dictionary) -> Dictionary:
	var out := {}
	for key in ["search", "position", "rarity", "team", "ownership"]:
		out[key] = str(query.get(key, "")) if str(query.get(key, "all")) != "all" else ""
	out["min_overall"] = int(query["min_overall"]) if int(query.get("min_overall", 0)) > 0 else ""
	return out


static func _to_query(values: Dictionary) -> Dictionary:
	var out := {}
	for key in ["search", "position", "rarity", "team", "ownership"]:
		if str(values.get(key, "")) != "":
			out[key] = str(values[key])
	if values.get("min_overall", "") is int and int(values["min_overall"]) > 0:
		out["min_overall"] = int(values["min_overall"])
	return out


## Fills the results area (the grid or the carousel) for the current filters. Only this area is rebuilt when a filter changes, so
## the search box keeps its focus while the player types.
static func _fill_results(ui: FcDynastyUi, holder: VBoxContainer, mode: String) -> void:
	var ctl := ui.ctl
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var rows := ctl.collection_rows(ui.collection_filters, ui.collection_sort)
	if rows.is_empty():
		holder.add_child(FcEmptyState.new("No cards match", "Try fewer filters.", FcEmptyState.Kind.EMPTY, "search", "Clear filters", func() -> void:
			ui.collection_filters = {}
			ui.refresh()))
		return
	var profile_id := ctl.profile().profile_id
	var owned_ids: Array = []
	for r in ctl.collection_rows({"ownership": "owned"}):
		owned_ids.append(r["card_id"])
	var fresh := ui.app.ui_state.new_cards(profile_id, owned_ids)
	var ids: Array = []
	for r in rows:
		ids.append(r["card_id"])
	var open_card := func(card_id: String) -> void:
		var modal := FcCardInspector.open_for(ui, card_id, ids)
		modal.closed.connect(func() -> void: _fill_results(ui, holder, mode))   # NEW markers disappear for cards that were opened
	if mode == "carousel":
		var carousel := FcCardCarousel.new()
		carousel.options_for = func(row: Dictionary) -> Dictionary: return {"tag": "NEW" if fresh.has(row["card_id"]) else ""}
		carousel.set_rows(rows)
		carousel.activated.connect(func(i: int) -> void: open_card.call(str(rows[i]["card_id"])))
		holder.add_child(carousel)
		FcMotion.fade_in(carousel)
		return
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for row in rows:
		var card_id := str(row["card_id"])
		grid.add_child(FcCardView.build(row, {"tag": "NEW" if fresh.has(card_id) else "", "on_click": func() -> void: open_card.call(card_id)}))
	holder.add_child(grid)
	FcMotion.fade_in(grid)


## The card window: the inspector overlay (zoom, turn over, compare, previous and next).
static func show_detail(ui: FcDynastyUi, card_id: String) -> void:
	if ui.ctl.card_detail(card_id).is_empty():
		return
	FcCardInspector.open_for(ui, card_id, [])


# --- lineup -----------------------------------------------------------------------------------------------------

static func build_lineup(ui: FcDynastyUi) -> Control:
	var ctl := ui.ctl
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_child(FcDynastyUi.wl(str(ctl.team_overall()), 44, true))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(FcDynastyUi.wl("Team overall (weighted from your 13 slots: starters count most)", 14))
	var identity := ctl.team_identity()
	info.add_child(FcDynastyUi.wl("Identity: %s" % (", ".join(identity) if not identity.is_empty() else "set a lineup")))
	head.add_child(info)
	root.add_child(head)
	var problems := ctl.lineup_problems()
	if problems.is_empty():
		var ok := FcDynastyUi.wl("Lineup is valid and ready to play.")
		ok.add_theme_color_override("font_color", FcUiTheme.GOOD)
		root.add_child(ok)
	else:
		for p in problems.slice(0, 4):
			var l := FcDynastyUi.wl("Problem: %s" % p)
			l.add_theme_color_override("font_color", FcUiTheme.BAD)
			root.add_child(l)
		if problems.size() > 4:
			root.add_child(FcDynastyUi.wl("...and %d more." % (problems.size() - 4)))
	root.add_child(FcDynastyUi.btn("Auto-fill the recommended lineup", func() -> void:
		var r := ctl.auto_fill_lineup()
		ui.report(r, "Lineup set to the best players you own, by position.")
		ui.refresh()))
	root.add_child(ui.note("Starters must be able to play their slot's position (primary or secondary). Bench order is the substitution order. Rotation: give a player fewer or more minutes. One edition per real player.", 700))
	var views := ctl.roster_view()
	root.add_child(ui.heading("Starters"))
	var court := FcLineupCourt.new()
	var starters: Array = []
	for i in FcDynastyRoster.STARTERS:
		starters.append(_slot_widget(ui, views[i], true))
	court.set_slots(starters)
	root.add_child(court)
	var rotation := FcPanel.new("Starters: rotation and removal", FcPanel.Variant.SURFACE)
	for i in FcDynastyRoster.STARTERS:
		var line := HBoxContainer.new()
		var who := FcDynastyUi.wl("%s: %s" % [str(views[i]["name"]).trim_prefix("Starter "), views[i]["card"].get("name", "empty")], 13)
		line.add_child(who)
		var controls := _controls_row(ui, views[i])
		controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(controls)
		rotation.add(line)
	root.add_child(rotation)
	for g in [["Bench", 5, 12], ["Reserve", 12, 13]]:
		root.add_child(ui.heading(g[0]))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		for i in range(g[1], g[2]):
			flow.add_child(_slot_widget(ui, views[i]))
		root.add_child(flow)
	return root


## One roster slot: its name, the card (tap it to choose another player), the rotation setting and a remove button.
## `on_court` uses a smaller card (the court gives each starter less room).
static func _slot_widget(ui: FcDynastyUi, slot_view: Dictionary, on_court: bool = false) -> Control:
	var ctl := ui.ctl
	var slot: int = slot_view["slot"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	if on_court:
		v.custom_minimum_size.x = 84   # one compact column: position and a mini card (rotation and remove are below the court)
	var title := FcUiTables.label(str(slot_view["name"]).trim_prefix("Starter "), 13, true) if on_court else FcDynastyUi.wl(slot_view["name"], 13, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(title)
	var card: Dictionary = slot_view["card"]
	if card.is_empty():
		var empty := FcCardView.build({"name": "Empty", "overall": 0, "rarity": "common", "available": true, "owned": true, "position": "", "edition": "Choose a player", "art_path": ""},
			{"size": FcCardFace.SIZE_MINI if on_court else FcCardView.SMALL, "on_click": func() -> void: _pick(ui, slot)})
		empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(empty)
	else:
		var shown := FcCardView.build(card, {"size": FcCardFace.SIZE_MINI if on_court else FcCardView.SMALL, "on_click": func() -> void: _pick(ui, slot)})
		shown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(shown)
	if not on_court:
		v.add_child(_controls_row(ui, slot_view))
	return v


## The rotation setting (fewer, normal or more minutes) and the remove button of one slot.
static func _controls_row(ui: FcDynastyUi, slot_view: Dictionary) -> Control:
	var ctl := ui.ctl
	var slot: int = slot_view["slot"]
	var card: Dictionary = slot_view["card"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var minutes := OptionButton.new()
	for m in ["Fewer min", "Normal", "More min"]:
		minutes.add_item(m)
	minutes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minutes.selected = int(slot_view["minutes"]) + 1
	minutes.item_selected.connect(func(i: int) -> void:
		ctl.set_minutes(slot, i - 1)
		ui.say("Rotation updated."))
	minutes.disabled = card.is_empty()
	row.add_child(minutes)
	var clear := FcDynastyUi.btn("X", func() -> void:
		ctl.clear_slot(slot)
		ui.refresh())
	clear.tooltip_text = "Remove this player from the slot"
	clear.disabled = card.is_empty()
	row.add_child(clear)
	return row


## The card picker for a slot: every usable owned card, with a comparison against the current player, in a kit dialog.
static func _pick(ui: FcDynastyUi, slot: int) -> void:
	var ctl := ui.ctl
	var current_id := str(ctl.profile().roster.slots[slot])
	var current := ctl.catalog.view(current_id) if current_id != "" else {}
	var candidates := ctl.candidates_for(slot)
	var columns: Array = [
		{"key": "name", "title": "Player", "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["name"], "make": func() -> Control: return FcPlayerChip.new(),
			"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcPlayerChip).setup({"subject": FcPlayerPresentation.subject_for_card(row["view"]), "name": row["name"], "overall": row["overall"]}, str(row["edition"]), false, 36, false)},
		{"key": "pos", "title": "Pos", "width": 54},
		{"key": "overall", "title": "OVR", "width": 64, "kind": "rating", "align": "center"},
		{"key": "diff", "title": "vs current", "width": 92, "kind": "number", "format": func(v) -> String: return "%+d" % int(v) if not current.is_empty() else "-"}]
	for c in COMPARE_COMPOSITES:
		columns.append({"key": "c_" + str(c[0]), "title": str(c[1]), "width": 66, "kind": "number"})
	var rows: Array = []
	for v in candidates:
		var comps := ctl.catalog.ratings.compute(ctl.catalog.make_player(str(v["card_id"]), 1))
		var row := {"id": str(v["card_id"]), "name": v["name"], "edition": v["edition"], "pos": v["position"], "overall": v["overall"], "view": v,
			"diff": int(v["overall"]) - int(current["overall"]) if not current.is_empty() else 0}
		for c in COMPARE_COMPOSITES:
			row["c_" + str(c[0])] = roundi(float(comps.get(c[0], 0.0)))
		rows.append(row)
	var modal := FcModal.new("Choose a player for %s" % FcDynastyRoster.slot_name(slot), "", FcModal.Kind.CONFIRM, "Choose selected player", "Cancel")
	modal.panel.custom_minimum_size.x = 760
	var hint := ui.note("Double-click a row or select it and press Choose. Compare overall and key ratings with your current player." if not candidates.is_empty() else "You do not own a card that can play this slot.", 700)
	modal.content.add_child(hint)
	var table := FcTable.new(columns, rows, {"row_height": 44, "max_rows": 8, "empty_title": "No cards", "empty_text": "You do not own a card that can play this slot."})
	table.custom_minimum_size = Vector2(700, 44 * 9)
	modal.content.add_child(table)
	modal.confirm_button.disabled = candidates.is_empty()
	var choose := func() -> void:
		if table.selected_id == null:
			ui.say("Select a player first.")
			return
		ui.report(ui.ctl.assign_slot(slot, str(table.selected_id)), "Lineup updated.")
		ui.refresh()
	modal.confirmed.connect(choose)
	table.row_activated.connect(func(_id) -> void:
		modal.close(true))
	ui.app.host.modals.open(modal)


