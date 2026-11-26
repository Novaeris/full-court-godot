class_name FcOwnerStaff
extends RefCounted
## The Staff tab: the front office (chemistry, what the general manager handles, direction) and the people (hire, fire, extend).
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var box := VBoxContainer.new()   # the "People" page
	var front := VBoxContainer.new()   # the "Front office" page
	var w := controller.state.world
	var tid := controller.state.user_team_id
	var rows: Array = []
	var ids: Array[int] = []
	for sc in w.staff_contracts_of_team(tid):
		var m: FcStaffMember = w.staff.get_by_id(sc.staff_id)
		rows.append([FcStaffRole.display_name(sc.role), m.identity.full_name(), m.reputation, m.experience_years, FcUiTables.money(sc.salary_for(controller.state.current_season)), sc.end_season()])
		ids.append(m.id)
	if controller.state.mode == FcGameState.MODE_OWNER:
		var chemistry := controller.staff_chemistry()
		front.add_child(FcUiTables.label("Staff chemistry: %d / 100 (%s)" % [chemistry["score"], chemistry["label"]], FcUiTokens.TYPE_H3, true))
		front.add_child(FcUiTables.label("It moves how fast your players develop (%+.1f coaching points now)." % chemistry["development_bonus"], FcUiTokens.TYPE_SMALL))
		for part in chemistry["parts"]:
			front.add_child(FcUiTables.label("%s: %d. %s" % [part["name"], roundi(part["value"]), part["note"]], FcUiTokens.TYPE_SMALL))
		front.add_child(FcUiTables.label("Front office: what your general manager handles", FcUiTokens.TYPE_H3, true))
		var gm := controller.gm_summary()
		if gm.is_empty():
			front.add_child(FcUiTables.label("You have no general manager, so you decide everything yourself. Hire one below."))
		else:
			front.add_child(FcUiTables.label("%s (talent evaluation %d, negotiation %d). A sharper eye means better re-signing, drafting and signings; leave an area unticked to decide it yourself." % [gm["name"], gm["talent_evaluation"], gm["negotiation"]]))
			var checks := HFlowContainer.new()
			for entry in [["contracts", "Re-sign my players"], ["draft", "Run the draft"], ["free_agency", "Sign free agents"], ["trades", "Make trades"], ["injuries", "Replace injured players"]]:
				var title: String = entry[1]
				var key: String = entry[0]
				var check := FcToggle.make(title, controller.delegation_on(key), func(on: bool) -> void: controller.set_delegation(key, on))
				check.tooltip_text = {"contracts": "Your general manager re-signs the players you would keep, at fair terms.", "draft": "Your general manager picks for you in the draft, using the scouts' board.", "free_agency": "Your general manager signs free agents within the budget you set.", "trades": "Your general manager looks for trades that fit your philosophy.", "injuries": "Your general manager signs replacements when injuries leave you short."}.get(key, "")
				checks.add_child(check)
			front.add_child(checks)
			var direction_row := HFlowContainer.new()
			direction_row.add_child(FcUiTables.label("Philosophy:"))
			var philosophy_pick := FcDropdown.new()
			philosophy_pick.tooltip_text = "Tells your general manager what to value: win now (today's ability, veterans), balanced, or rebuild (youth and potential)."
			for name in ["Win now (value today's ability, buy veterans)", "Balanced", "Rebuild (value youth and potential, sell veterans)"]:
				philosophy_pick.add_item(name)
			philosophy_pick.selected = FcGameState.PHILOSOPHIES.find(controller.philosophy())
			direction_row.add_child(philosophy_pick)
			direction_row.add_child(FcUiTables.label("   Budget:"))
			var budget_pick := FcDropdown.new()
			budget_pick.tooltip_text = "How much payroll your general manager may commit: frugal stays below the cap, normal uses it, aggressive goes above it but under the tax line."
			for name in ["Frugal (92% of the cap)", "Normal (the cap)", "Aggressive (up to 115%, below the tax line)"]:
				budget_pick.add_item(name)
			budget_pick.selected = FcGameState.BUDGETS.find(controller.state.direction["budget"])
			direction_row.add_child(budget_pick)
			var apply_direction := func(_i):
				controller.set_direction(FcGameState.PHILOSOPHIES[philosophy_pick.selected], FcGameState.BUDGETS[budget_pick.selected])
				ctx.tell("Direction set. Your general manager follows it when he re-signs, drafts, trades and signs players (only in the areas ticked above).")
			philosophy_pick.item_selected.connect(apply_direction)
			budget_pick.item_selected.connect(apply_direction)
			front.add_child(direction_row)
			var card := controller.gm_report()
			if not card.is_empty():
				front.add_child(FcUiTables.label("Last season: %s. %d wins (about %d expected), payroll %s against a budget of %s." % [card["grade"], card["wins"], card["expected_wins"], FcUiTables.money(card["payroll"]), FcUiTables.money(card["limit"])]))
	box.add_child(FcUiTables.label("Your staff", FcUiTokens.TYPE_H3, true))
	var table := FcTable.from_strings(["Role", "Name", "Reputation", "Experience", "Salary", "Through"], rows)
	box.add_child(table)
	if controller.state.mode == FcGameState.MODE_OWNER:
		var row := HFlowContainer.new()
		row.add_child(FcUiTables.button("Fire selected", func():
			if table.selected_id != null and controller.fire_staff(ids[int(table.selected_id)]):
				ctx.tell("Fired.")
			ctx.refresh_now()))
		var role_picker := FcDropdown.new()
		role_picker.tooltip_text = "The job you want to fill. A general manager and head coach are one each; you can have several assistants and scouts."
		for role in [FcStaffRole.Id.GENERAL_MANAGER, FcStaffRole.Id.HEAD_COACH, FcStaffRole.Id.ASSISTANT_COACH, FcStaffRole.Id.SCOUT, FcStaffRole.Id.MEDICAL, FcStaffRole.Id.BUSINESS_EXECUTIVE]:
			role_picker.add_item(FcStaffRole.display_name(role))
			role_picker.set_item_metadata(role_picker.item_count - 1, role)
		var person_picker := FcDropdown.new()
		person_picker.tooltip_text = "Available people with their reputation, asking salary and the staff chemistry you would have if you hired them."
		var fill := func():
			person_picker.clear()
			var role: int = role_picker.get_item_metadata(role_picker.selected)
			for m in controller.staff_pool(role).slice(0, 12):
				person_picker.add_item("%s (rep %d, %s, staff chemistry would be %d)" % [m.identity.full_name(), m.reputation, FcUiTables.money(controller.asking_salary(m.id)), controller.staff_chemistry(m.id, role)["score"]])
				person_picker.set_item_metadata(person_picker.item_count - 1, m.id)
		role_picker.item_selected.connect(func(_i): fill.call())
		fill.call()
		row.add_child(FcUiTables.label("Hire a"))
		row.add_child(role_picker)
		row.add_child(person_picker)
		var hire_salary := SpinBox.new()
		hire_salary.tooltip_text = "The yearly salary you offer, in millions. A person accepts a little less than they ask, and a better negotiating general manager gets a bigger discount."
		hire_salary.min_value = 0.05
		hire_salary.max_value = 30
		hire_salary.step = 0.05
		var hire_years := SpinBox.new()
		hire_years.tooltip_text = "Contract length in years. Longer deals make people accept a slightly lower salary."
		hire_years.min_value = 1
		hire_years.max_value = 5
		hire_years.value = 3
		var sync_offer := func(_i = 0):
			if person_picker.item_count > 0:
				hire_salary.value = controller.asking_salary(person_picker.get_item_metadata(person_picker.selected)) / 1e6
		person_picker.item_selected.connect(sync_offer)
		role_picker.item_selected.connect(func(_i): sync_offer.call())
		sync_offer.call()
		row.add_child(FcUiTables.label("$M"))
		row.add_child(hire_salary)
		row.add_child(FcUiTables.label("years"))
		row.add_child(hire_years)
		row.add_child(FcUiTables.button("Hire", func():
			if person_picker.item_count == 0:
				return
			var error := controller.hire_staff(person_picker.get_item_metadata(person_picker.selected), role_picker.get_item_metadata(role_picker.selected), int(hire_years.value), roundi(hire_salary.value * 1e6))
			ctx.tell("Hired." if error == "" else error)
			if error == "":
				ctx.refresh_now()))
		box.add_child(row)
		var extend_row := HFlowContainer.new()
		extend_row.add_child(FcUiTables.label("Contract extension for the selected staff member: $M"))
		var ext_pay := SpinBox.new()
		ext_pay.tooltip_text = "The yearly salary you offer, in millions, to keep this staff member."
		ext_pay.min_value = 0.05
		ext_pay.max_value = 30
		ext_pay.step = 0.05
		var ext_len := SpinBox.new()
		ext_len.tooltip_text = "Length of the new contract in years."
		ext_len.min_value = 1
		ext_len.max_value = 5
		ext_len.value = 3
		table.row_selected.connect(func(id) -> void: ext_pay.value = controller.asking_salary(ids[int(id)]) / 1e6)
		extend_row.add_child(ext_pay)
		extend_row.add_child(FcUiTables.label("years"))
		extend_row.add_child(ext_len)
		extend_row.add_child(FcUiTables.button("Extend staff contract", func():
			if table.selected_id == null:
				ctx.tell("Select a staff member first.")
				return
			var r := controller.extend_staff(ids[int(table.selected_id)], roundi(ext_pay.value * 1e6), int(ext_len.value))
			ctx.tell(r["reason"])))
		box.add_child(extend_row)
	if controller.state.mode != FcGameState.MODE_OWNER:
		return box
	var pages := FcTabPages.new()
	for entry in [["Front office", front], ["People", box]]:
		pages.add_page(entry[1], entry[0])
	pages.current_tab = clampi(ctx.memory["staff_page"], 0, 1)
	pages.tab_changed.connect(func(i): ctx.memory["staff_page"] = i)
	return pages
