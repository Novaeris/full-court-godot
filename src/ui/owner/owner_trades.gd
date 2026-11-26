class_name FcOwnerTrades
extends RefCounted
## The Trades tab: offers from other teams, and a page to propose a trade (players and draft picks on both sides).
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var w := controller.state.world
	var user_id := controller.state.user_team_id
	var box := VBoxContainer.new()   # the "Propose a trade" page
	var offers_page := VBoxContainer.new()
	var others: Array[int] = []
	for t in w.teams.all():
		if t.id != user_id and w.leagues.get_by_id(controller.league_id).contains_team(t.id):
			others.append(t.id)
	if others.is_empty():
		box.add_child(FcUiTables.label("There is nobody to trade with."))
		return box
	if not ctx.memory["trade_partner"] in others:
		ctx.memory["trade_partner"] = others[0]
	var picker := FcDropdown.new()
	for tid in others:
		picker.add_item(ctx.team_name(tid))
	picker.selected = others.find(ctx.memory["trade_partner"])
	picker.item_selected.connect(func(i):
		ctx.memory["trade_partner"] = others[i]
		ctx.refresh_now())
	var offers := controller.trade_offers()
	if not offers.is_empty():
		offers_page.add_child(FcUiTables.label("Offers from other teams (new ones every two weeks)", FcUiTokens.TYPE_H3, true))
		var offer_rows: Array = []
		for o in offers:
			var theirs: FcPlayer = w.players.get_by_id(o["get"])
			var mine: FcPlayer = w.players.get_by_id(o["give"])
			var ratings_now := FcPlayerRatings.load_default()
			offer_rows.append([o["name"], "%s (%d, age %d)" % [mine.identity.full_name(), roundi(ratings_now.overall(mine)), mine.age_on(FcDate.new(controller.contract_year(), 7, 1))], "%s (%d, age %d)" % [theirs.identity.full_name(), roundi(ratings_now.overall(theirs)), theirs.age_on(FcDate.new(controller.contract_year(), 7, 1))]])
		var offer_table := FcTable.from_strings(["Team", "They want", "They offer you"], offer_rows, [], {"max_rows": 6})
		offer_table.size_flags_vertical = Control.SIZE_FILL
		offers_page.add_child(offer_table)
		var offer_buttons := HFlowContainer.new()
		offer_buttons.add_child(FcUiTables.button("Accept selected offer", func():
			if offer_table.selected_id == null:
				ctx.tell("Select an offer first.")
				return
			var result := controller.accept_trade_offer(offers[int(offer_table.selected_id)])
			ctx.tell(result["reason"])
			if result["accepted"]:
				ctx.refresh_now()))
		offer_buttons.add_child(FcUiTables.button("Decline selected offer", func():
			if offer_table.selected_id == null:
				ctx.tell("Select an offer first.")
				return
			controller.decline_trade_offer(offers[int(offer_table.selected_id)])
			ctx.refresh_now()))
		offers_page.add_child(offer_buttons)
	box.add_child(FcUiTables.label("Trade with:", FcUiTokens.TYPE_H3, true))
	box.add_child(picker)
	var ratings := FcPlayerRatings.load_default()
	var year := controller.state.current_season
	var lists: Array = []
	var ids_by_list: Array = []
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in [[user_id, "You give"], [ctx.memory["trade_partner"], "You get"]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(FcUiTables.label(side[1], FcUiTokens.TYPE_H3, true))
		var ids: Array[int] = []
		var trade_rows: Array = []
		for pid in w.teams.get_by_id(side[0]).roster.player_ids:
			var p: FcPlayer = w.players.get_by_id(pid)
			var c := w.active_contract_of(pid)
			trade_rows.append({"id": pid, "name": p.identity.full_name(), "pos": FcPosition.abbreviation(p.primary_position), "age": p.age_on(FcDate.new(year, 7, 1)), "ovr": roundi(ratings.overall(p)),
				"cap": c.cap_hit_for(year) if c != null else 0, "flag": "No-trade" if c != null and c.no_trade else ""})
			ids.append(pid)
		var list := FcTable.new([
			{"key": "name", "title": "Player", "kind": "custom", "fill": true, "sort_value": func(r: Dictionary): return r["name"], "make": func() -> Control: return FcPlayerChip.new(),
				"bind": func(cell: Control, row: Dictionary) -> void: (cell as FcPlayerChip).setup({"subject": FcPlayerPresentation.subject_for_player(w, int(row["id"])), "name": row["name"], "overall": row["ovr"]}, "", false, 32, true)},
			{"key": "pos", "title": "Pos", "width": 48}, {"key": "age", "title": "Age", "width": 46, "kind": "number"},
			{"key": "ovr", "title": "Ovr", "width": 58, "kind": "rating", "align": "center"},
			{"key": "cap", "title": "Cap hit", "width": 84, "kind": "number", "format": func(v) -> String: return FcUiTables.money(int(v)) if int(v) > 0 else "-"},
			{"key": "flag", "title": "", "width": 76}], trade_rows, {"multi": true, "row_height": 40, "max_rows": 8})
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.custom_minimum_size.y = 40 * 5
		col.add_child(list)
		columns.add_child(col)
		lists.append(list)
		ids_by_list.append(ids)
	box.add_child(columns)
	var pick_lists: Array = []
	var picks_by_list: Array = []
	var pick_columns := HBoxContainer.new()
	for side in [[user_id, "Draft picks you give"], [ctx.memory["trade_partner"], "Draft picks you get"]]:
		var col2 := VBoxContainer.new()
		col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col2.add_child(FcUiTables.label(side[1], FcUiTokens.TYPE_H3, true))
		var refs: Array = []
		var pick_rows: Array = []
		for entry in controller.tradable_picks(side[0]):
			pick_rows.append([entry["label"]])
			refs.append([entry["year"], entry["round"], entry["original"]])
		var plist := FcTable.from_strings(["Pick"], pick_rows, [], {"multi": true, "max_rows": 4})
		col2.add_child(plist)
		pick_columns.add_child(col2)
		pick_lists.append(plist)
		picks_by_list.append(refs)
	box.add_child(pick_columns)
	var pick_refs := func(index: int) -> Array:
		var out2: Array = []
		for i in pick_lists[index].selected_ids():
			out2.append(picks_by_list[index][i])
		return out2
	var pick := func(index: int) -> Array:
		var out: Array = []
		for id in lists[index].selected_ids():
			out.append(id)
		return out
	var row := HFlowContainer.new()
	row.add_child(FcUiTables.button("Check the offer", func():
		ctx.tell(controller.propose_trade(ctx.memory["trade_partner"], pick.call(0), pick.call(1), true, pick_refs.call(0), pick_refs.call(1))["reason"])))
	row.add_child(FcUiTables.button("Propose trade", func():
		var r := controller.propose_trade(ctx.memory["trade_partner"], pick.call(0), pick.call(1), false, pick_refs.call(0), pick_refs.call(1))
		if r["accepted"]:
			ctx.refresh_now()
		ctx.tell(r["reason"])))
	box.add_child(row)
	if offers.is_empty():
		offers_page.add_child(FcUiTables.label("No team has made you an offer right now. New offers can arrive every two weeks during the season and in the free-agency window."))
	var pages := FcTabPages.new()
	pages.add_page(offers_page, "Offers from teams (%d)" % offers.size())
	pages.add_page(box, "Propose a trade")
	pages.current_tab = (0 if not offers.is_empty() else 1) if ctx.memory["trade_page"] < 0 else clampi(ctx.memory["trade_page"], 0, 1)
	pages.tab_changed.connect(func(i): ctx.memory["trade_page"] = i)
	return pages
