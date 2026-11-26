class_name FcOwnerFinances
extends RefCounted
## The Finances tab in four pages: the books and league comparison, prices and the shop, sponsors and loans, arena and facilities.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var w := controller.state.world
	var b := controller.business()
	var cap := w.rules_of_league(controller.league_id).cap
	var summary := VBoxContainer.new()
	summary.add_child(FcUiTables.label("Your franchise", FcUiTokens.TYPE_H3, true))
	summary.add_child(FcUiTables.label("Payroll %s of a %s cap (hard limit %s). Cash %s. Debt %s. Value %s." % [
		FcUiTables.money(w.payroll_of_team(b.id, controller.state.current_season)), FcUiTables.money(cap.salary_cap),
		FcUiTables.money(cap.effective_limit()), FcUiTables.money(b.cash), FcUiTables.money(b.debt), FcUiTables.money(b.valuation)]))
	summary.add_child(FcUiTables.label("Fan interest %d, brand %d, arena quality %d." % [b.fan_interest, b.brand, b.facilities_level]))
	var executive := w.staff_in_role(b.id, FcStaffRole.Id.BUSINESS_EXECUTIVE)
	var executive_label: Label
	if executive == null:
		executive_label = FcUiTables.label("No business executive: sponsorships, marketing and overhead all suffer. Hire one on the Staff tab.")
	else:
		executive_label = FcUiTables.label("Business executive %s: marketing %d (sponsorships and brand), financial acumen %d (overhead), community relations %d (fan interest)." % [executive.identity.full_name(), executive.skills.get_value("marketing"), executive.skills.get_value("financial_acumen"), executive.skills.get_value("community_relations")])
	executive_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	executive_label.custom_minimum_size = Vector2(200, 0)
	summary.add_child(executive_label)
	var rows: Array = []
	var years: Array = []
	for r in w.finances.all():
		if r.team_id == b.id:
			years.append(r)
	years.reverse()
	for r in years:
		rows.append(["%d-%02d" % [r.year, (r.year + 1) % 100], r.wins, FcUiTables.money(r.total_revenue()), FcUiTables.money(r.total_expenses()), FcUiTables.money(r.profit()),
			r.average_attendance, "$%d" % r.ticket_price, FcUiTables.money(r.valuation_end)])
	if not years.is_empty():   # where the money came from and where it went, for the latest settled season (real books, never estimates)
		var latest: FcFinanceRecord = years[0]
		var money := func(v) -> String: return FcUiTables.money(int(v))
		var chart_row := HFlowContainer.new()
		chart_row.add_theme_constant_override("h_separation", FcUiTokens.SPACE_4)
		chart_row.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
		for entry in [["Revenue %d-%02d" % [latest.year, (latest.year + 1) % 100], latest.revenue], ["Expenses %d-%02d" % [latest.year, (latest.year + 1) % 100], latest.expenses]]:
			var chart_panel := FcPanel.new(str(entry[0]), FcPanel.Variant.SURFACE)
			chart_panel.custom_minimum_size.x = 330
			var chart := FcStackedBar.new(money)
			var chart_parts: Array = []
			for key in entry[1]:
				chart_parts.append({"label": str(key).replace("_", " ").capitalize(), "value": entry[1][key]})
			chart.set_parts(chart_parts)
			chart_panel.add(chart)
			chart_row.add_child(chart_panel)
		summary.add_child(chart_row)
	var books := HBoxContainer.new()
	books.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine.add_child(FcUiTables.label("Your seasons", FcUiTokens.TYPE_H3, true))
	mine.add_child(FcTable.from_strings(["Season", "Wins", "Revenue", "Expenses", "Profit", "Attendance", "Ticket", "Value"], rows))
	books.add_child(mine)
	var league_books := controller.league_finances()
	if not league_books.is_empty():
		var compare := VBoxContainer.new()
		compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		compare.add_child(FcUiTables.label("How you compare (last season, * = you)", FcUiTokens.TYPE_H3, true))
		var compare_rows: Array = []
		for entry in league_books:
			compare_rows.append(["%s%s" % ["* " if entry["team"] == b.id else "", entry["name"]], entry["wins"], FcUiTables.money(entry["revenue"]), FcUiTables.money(entry["profit"]), FcUiTables.money(entry["payroll"]), "$%d" % entry["price"], entry["attendance"]])
		compare.add_child(FcTable.from_strings(["Team", "Wins", "Revenue", "Profit", "Payroll", "Ticket", "Fans"], compare_rows, [150, 40, 72, 72, 72, 52, 48]))
		books.add_child(compare)
	summary.add_child(books)
	if controller.state.mode != FcGameState.MODE_OWNER:
		return summary

	# --- prices and the shop ---
	var pricing := VBoxContainer.new()
	pricing.add_child(FcUiTables.label("Tickets", FcUiTokens.TYPE_H3, true))
	var row := HBoxContainer.new()
	row.add_child(FcUiTables.label("Ticket price $"))
	var price := SpinBox.new()
	price.tooltip_text = "The price of a regular ticket. 'Use suggestion' sets the price that just fills your arena. Higher earns more per fan but empties seats; lower fills seats but earns less."
	price.min_value = 5
	price.max_value = 2000
	price.value = b.ticket_price
	row.add_child(price)
	row.add_child(FcUiTables.label("  Marketing $M"))
	var marketing := SpinBox.new()
	marketing.tooltip_text = "Yearly marketing spend in millions. It builds your brand, which lifts sponsors and merchandise. Money spent beyond what your market can use is wasted."
	marketing.min_value = 0
	marketing.max_value = 100
	marketing.step = 0.5
	marketing.value = b.marketing_budget / 1e6
	row.add_child(marketing)
	row.add_child(FcUiTables.button("Apply", func():
		var ok := controller.set_ticket_price(int(price.value)) and controller.set_marketing_budget(roundi(marketing.value * 1e6))
		ctx.tell("Updated." if ok else "Those values are not allowed.")))
	row.add_child(FcUiTables.label("   Suggested $%d" % controller.suggested_ticket_price()))
	row.add_child(FcUiTables.button("Use suggestion", func():
		price.value = controller.suggested_ticket_price()
		var ok2 := controller.set_ticket_price(int(price.value))
		ctx.tell("Ticket price set to the suggestion." if ok2 else "That price is not allowed.")))
	pricing.add_child(row)
	var hint := FcUiTables.label("The suggestion is the price that just fills your arena today. Fan interest and brand change as you win or lose, so check it each season; AI teams reprice every year.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(200, 0)
	pricing.add_child(hint)
	var tix := controller.ticket_plan_preview()
	var season_row := HBoxContainer.new()
	season_row.add_child(FcUiTables.label("Season tickets % of seats"))
	var season_share := SpinBox.new()
	season_share.tooltip_text = "The share of your seats sold as season tickets. Holders pay 12% less but always come. Good when seats would stay empty, a loss when the arena sells out anyway."
	season_share.min_value = 0
	season_share.max_value = 60
	season_share.step = 5
	season_share.value = b.season_ticket_share
	season_row.add_child(season_share)
	season_row.add_child(FcUiTables.label("  Promotion nights"))
	var promo_nights := SpinBox.new()
	promo_nights.tooltip_text = "Home games with half-price tickets that fill the arena. Each costs a little to stage and adds fans and fan interest. Only worth it when seats would otherwise be empty."
	promo_nights.min_value = 0
	promo_nights.max_value = 10
	promo_nights.value = b.promotion_nights
	season_row.add_child(promo_nights)
	season_row.add_child(FcUiTables.button("Apply", func():
		var ok3 := controller.set_season_ticket_share(int(season_share.value)) and controller.set_promotion_nights(int(promo_nights.value))
		ctx.tell("Ticket plan updated." if ok3 else "Those values are not allowed.")))
	pricing.add_child(season_row)
	var plan_hint := FcUiTables.label("Season holders pay $%d (12%% off) and always come (%d of %d seats now); promotion nights sell the rest of the arena at $%d and cost %s each. Both only pay when seats would otherwise be empty (demand now %d of %d seats)." % [
		tix["season_price"], tix["holders"], tix["capacity"], tix["promo_price"], FcUiTables.money(tix["promo_cost"]), tix["demand"], tix["capacity"]])
	plan_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plan_hint.custom_minimum_size = Vector2(200, 0)
	pricing.add_child(plan_hint)
	pricing.add_child(FcUiTables.label("Shop and concessions", FcUiTokens.TYPE_H3, true))
	var shop := HBoxContainer.new()
	shop.add_child(FcUiTables.label("Concession prices %"))
	var concessions := SpinBox.new()
	concessions.tooltip_text = "Food and drink prices as a percent of normal. Higher earns more per fan but lowers fan interest a little."
	concessions.min_value = 70
	concessions.max_value = 150
	concessions.step = 5
	concessions.value = b.concession_price_pct
	shop.add_child(concessions)
	shop.add_child(FcUiTables.label("   Playoff ticket price %"))
	var playoff_price := SpinBox.new()
	playoff_price.tooltip_text = "Playoff ticket prices as a percent of the regular price. Playoff demand is higher, so a higher premium earns more until the arena stops selling out."
	playoff_price.min_value = 100
	playoff_price.max_value = 300
	playoff_price.step = 10
	playoff_price.value = b.playoff_premium_pct
	shop.add_child(playoff_price)
	shop.add_child(FcUiTables.label("   Merchandise range"))
	var merch := FcDropdown.new()
	merch.tooltip_text = "The merchandise range. Limited is cheap but sells less; Premium sells most but costs a lot of stock and only works for a strong brand."
	for name in FcTeamBusiness.MERCH_TIERS:
		merch.add_item(name)
	merch.selected = b.merch_tier
	shop.add_child(merch)
	shop.add_child(FcUiTables.button("Apply shop settings", func():
		controller.set_concession_price(int(concessions.value))
		controller.set_playoff_premium(int(playoff_price.value))
		controller.set_merch_tier(merch.selected)
		ctx.tell("Shop settings updated. Higher concession prices earn more per fan but cost fan interest; a premium range sells more but costs more stock.")))
	pricing.add_child(shop)

	# --- sponsors and loans ---
	var money := VBoxContainer.new()
	money.add_child(FcUiTables.label("Sponsors", FcUiTokens.TYPE_H3, true))
	var sponsors := HBoxContainer.new()
	sponsors.add_child(FcUiTables.label("Signed:"))
	var deal_texts: Array[String] = []
	for deal in b.sponsor_deals:
		deal_texts.append("%s %s/yr%s, %d yr left" % [deal["sponsor"], FcUiTables.money(deal["amount"]), " + %s per playoff round" % FcUiTables.money(deal["bonus"]) if deal["bonus"] > 0 else "", deal["years_left"]])
	sponsors.add_child(FcUiTables.label(", ".join(deal_texts) if not deal_texts.is_empty() else "none yet (open-market income)"))
	money.add_child(sponsors)
	var offers := controller.sponsor_offers()
	if not offers.is_empty():
		var offer_row := HBoxContainer.new()
		offer_row.add_child(FcUiTables.label("Offers:"))
		var offer_pick := FcDropdown.new()
		offer_pick.tooltip_text = "Sponsors that want to sign with you. Fixed deals pay a steady amount; bonus deals pay less up front and more for playoff rounds won."
		for o in offers:
			offer_pick.add_item("%s: %s/yr x %d%s" % [o["sponsor"], FcUiTables.money(o["amount"]), o["years"], " + %s per playoff round" % FcUiTables.money(o["bonus"]) if o["bonus"] > 0 else ""])
		offer_row.add_child(offer_pick)
		offer_row.add_child(FcUiTables.button("Sign sponsor deal", func():
			var r5 := controller.accept_sponsor(offers[offer_pick.selected]["sponsor"])
			ctx.tell(r5["reason"])
			if r5["ok"]:
				ctx.refresh_now()))
		money.add_child(offer_row)
	var style_row := HBoxContainer.new()
	style_row.add_child(FcUiTables.label("Style of the rest of your sponsorship income:"))
	var plan := FcDropdown.new()
	plan.tooltip_text = "How the part of your sponsorship money not covered by signed deals is paid. Steady pays less but is guaranteed; Performance pays more only if you win."
	for name in FcTeamBusiness.SPONSOR_PLANS:
		plan.add_item(name)
	plan.selected = b.sponsor_plan
	plan.item_selected.connect(func(i):
		controller.set_sponsor_plan(i)
		ctx.tell("Sponsorship: %s. Steady pays less but guaranteed; Performance pays more only if you win." % FcTeamBusiness.SPONSOR_PLANS[i]))
	style_row.add_child(plan)
	money.add_child(style_row)
	money.add_child(FcUiTables.label("Loans", FcUiTokens.TYPE_H3, true))
	var loans := HBoxContainer.new()
	loans.add_child(FcUiTables.label("Loan $M"))
	var amount := SpinBox.new()
	amount.tooltip_text = "The amount, in millions, to borrow or repay. Debt costs 6% interest a season and your borrowing limit is a share of your franchise value."
	amount.min_value = 1
	amount.max_value = 500
	amount.value = 10
	loans.add_child(amount)
	loans.add_child(FcUiTables.button("Borrow", func():
		var r := controller.borrow(roundi(amount.value * 1e6))
		ctx.tell(r["reason"])
		if r["ok"]:
			ctx.refresh_now()))
	loans.add_child(FcUiTables.button("Repay", func():
		var r := controller.repay_debt(roundi(amount.value * 1e6))
		ctx.tell(r["reason"])
		if r["ok"]:
			ctx.refresh_now()))
	loans.add_child(FcUiTables.label("   Borrowing limit %s   Debt %s (6%% interest a season)" % [FcUiTables.money(controller.loan_limit()), FcUiTables.money(b.debt)]))
	money.add_child(loans)
	money.add_child(FcUiTables.label("Owner payouts", FcUiTokens.TYPE_H3, true))
	var payouts := HBoxContainer.new()
	payouts.add_child(FcUiTables.label("Dividend $M"))
	var dividend := SpinBox.new()
	dividend.tooltip_text = "Cash to pay yourself, in millions. The club must keep a reserve and cannot have debt. It does not change how the team plays."
	dividend.min_value = 1
	dividend.max_value = 5000
	dividend.value = 10
	payouts.add_child(dividend)
	payouts.add_child(FcUiTables.button("Pay myself", func():
		var rd := controller.take_dividend(roundi(dividend.value * 1e6))
		ctx.tell(rd["reason"])
		if rd["ok"]:
			ctx.refresh_now()))
	payouts.add_child(FcUiTables.label("   You can take %s now   Taken so far %s" % [FcUiTables.money(controller.dividend_limit()), FcUiTables.money(b.distributions)]))
	money.add_child(payouts)

	# --- arena and facilities ---
	var arena_page := VBoxContainer.new()
	arena_page.add_child(FcUiTables.label("Arena and facilities", FcUiTokens.TYPE_H3, true))
	var quality := HBoxContainer.new()
	quality.add_child(FcUiTables.label("Arena quality %d (it wears down a little every season)." % b.facilities_level))
	quality.add_child(FcUiTables.button("Invest in arena (+10)", func():
		ctx.tell("Arena improved." if controller.invest_in_facilities(10) else "Not enough cash for that.")
		ctx.refresh_now()))
	arena_page.add_child(quality)
	var build := HBoxContainer.new()
	build.add_child(FcUiTables.label("Building project:"))
	var options := controller.arena_project_options()
	var project_pick := FcDropdown.new()
	project_pick.tooltip_text = "Arena projects are paid up front and finish after a few seasons. Each kind can run once at a time."
	for o in options:
		project_pick.add_item("%s (%s, %d season%s)%s" % [o["name"], FcUiTables.money(o["cost"]), o["seasons"], "" if o["seasons"] == 1 else "s", " - under way" if o["running"] else ""])
	build.add_child(project_pick)
	build.add_child(FcUiTables.button("Start project", func():
		var r := controller.start_arena_project(options[project_pick.selected]["key"])
		ctx.tell(r["reason"])
		if r["ok"]:
			ctx.refresh_now()))
	arena_page.add_child(build)
	arena_page.add_child(FcUiTables.label("Built so far: arena suites level %d, practice facility level %d, medical center level %d." % [b.suites_level, b.practice_level, b.medical_level]))
	for o in options:
		var line := FcUiTables.label("%s: %s" % [o["name"], o["description"]])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(200, 0)
		arena_page.add_child(line)

	var pages := FcTabPages.new()
	for entry in [["Summary", summary], ["Prices and shop", pricing], ["Sponsors and loans", money], ["Arena and facilities", arena_page]]:
		pages.add_page(entry[1], entry[0])
	pages.current_tab = clampi(ctx.memory["finance_page"], 0, pages.get_tab_count() - 1)
	pages.tab_changed.connect(func(i): ctx.memory["finance_page"] = i)
	return pages
