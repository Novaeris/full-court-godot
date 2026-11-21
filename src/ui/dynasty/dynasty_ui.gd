class_name FcDynastyUi
extends RefCounted
## The Dynasty Mode shell: profile selection, the navigation bar, and the hub. The other screens are built by the
## FcDynastyScreens* classes and plug in through TABS. Screens only call FcDynastyController (never the domain services), so
## nothing here can edit a balance or grant a card.

## [id, label, icon]. On the mobile bottom bar only MOBILE_PRIMARY are shown directly; the rest are under "More".
const TABS := [
	["hub", "Hub", "house"], ["collection", "Collection", "layers"], ["lineup", "Lineup", "user"], ["packs", "Packs", "package"],
	["market", "Market", "arrow-up-down"], ["play", "Play", "play"], ["challenges", "Challenges", "star"],
	["tournament", "Tournament", "trophy"], ["season", "Season", "sparkles"],
]
const MOBILE_PRIMARY := ["hub", "collection", "packs", "play"]

var app: FcApp
var ctl: FcDynastyController
var tab: String = "hub"
## Filter and sort choices the collection screen keeps while you move around.
var collection_filters: Dictionary = {}
var collection_sort: String = "overall_desc"
var _body: VBoxContainer
var _form := {}


func _init(application: FcApp, controller: FcDynastyController) -> void:
	app = application
	ctl = controller


func say(text: String) -> void:
	app._say(text)


## Shows the result of a controller call: the failure message (an error toast), or the success text (a success toast).
func report(result: FcDynastyResult, success_text: String = "") -> bool:
	if result.ok:
		if success_text != "":
			app.notify(FcToast.Kind.SUCCESS, success_text)
	else:
		app.notify(FcToast.Kind.ERROR, result.message)
	return result.ok


# --- entry: profiles --------------------------------------------------------------------------------------------

func show_entry() -> void:
	ctl.close_profile()
	var box := app._reset("Dynasty Mode", {"id": "dynasty_entry", "skin": FcModeSkin.COLLECTIBLE, "back": app.show_main_menu, "rebuild": show_entry})
	var intro := FcDynastyUi.wl("Collect fictional player cards, open packs, build a 13-player roster and compete in simulated games, challenges and tournaments. Your collection is yours: seasons and new content never remove it.", 15)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(160, 0)
	box.add_child(intro)
	box.add_child(_content_status())
	if not ctl.catalog.is_playable():
		box.add_child(_onboarding_panel())
	var profiles := ctl.profiles()
	if not profiles.is_empty():
		box.add_child(FcDynastyUi.wl("Your Dynasty teams", 18, true))
		for p in profiles:
			var row := HBoxContainer.new()
			var label := FcDynastyUi.wl("%s (%s)   %d cards   %s credits   record %s" % [p["team_name"], p["abbreviation"], p["cards"], FcDynastyStyle._n(p["credits"]), p["record"]])
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			if p["readable"]:
				row.add_child(FcDynastyUi.btn("Open", func() -> void: open_profile(str(p["slot"]))))
			row.add_child(FcDynastyUi.btn("Delete", func() -> void: _confirm_delete(str(p["slot"]), str(p["team_name"]))))
			box.add_child(row)
	if ctl.catalog.is_playable():
		box.add_child(FcDynastyUi.wl("Start a new Dynasty team", 18, true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_child(FcDynastyUi.wl("Team name"))
		var name_edit := LineEdit.new()
		name_edit.text = "My Dynasty"
		name_edit.custom_minimum_size = Vector2(160, 0)
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_edit)
		grid.add_child(FcDynastyUi.wl("Abbreviation (2-4 letters)"))
		var abbr_edit := LineEdit.new()
		abbr_edit.text = "DYN"
		abbr_edit.max_length = 4
		grid.add_child(abbr_edit)
		_form["name"] = name_edit
		_form["abbr"] = abbr_edit
		box.add_child(grid)
		box.add_child(FcDynastyUi.btn("Create team and receive the starter collection", func() -> void: on_create(name_edit.text, abbr_edit.text)))
	box.add_child(FcDynastyUi.btn("Back to the main menu", app.show_main_menu))


func _content_status() -> Control:
	var l := FcDynastyUi.wl(_content_text(), 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(160, 0)
	l.add_theme_color_override("font_color", FcUiTheme.TEXT_MUTED)
	return l


func _content_text() -> String:
	var cat := ctl.catalog
	var report: FcContentLoadReport = ctl.content.report if ctl.content != null else null
	var text := "Content release: %s (%d cards, %d packs, %d challenges)" % [cat.release_id() if cat.release_id() != "" else "none loaded", cat.card_ids().size(), cat.packs().size(), cat.challenges().size()]
	if report != null and report.used_starter:
		text += ". This is the bundled Founding Series release; a release published from Creator Studio replaces it."
	elif report != null and report.is_degraded():
		text += ". " + report.summary()
	return text


func _onboarding_panel() -> Control:
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(FcDynastyUi.wl("Dynasty needs content first", 18, true))
	var text := FcDynastyUi.wl("%s\n\nOpen Creator Studio (the separate project in this repository), create players and cards, set up packs and the starter collection (a dynasty_config support file), check the draft and publish a release. Then come back here: Dynasty loads the active release automatically." % ctl.catalog.playable_problem(), 14)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(160, 0)
	v.add_child(text)
	return panel


func on_create(team: String, abbr: String) -> bool:
	var r := ctl.create_profile(team, abbr)
	if not r.ok:
		say(r.message)
		return false
	show_tab("hub")
	return true


func open_profile(slot: String) -> bool:
	var r := ctl.open_profile(slot)
	if not r.ok:
		say(r.message)
		return false
	show_tab("hub")
	if str(r.data.get("recovered_from", "")) != "":
		say("Your Dynasty save was damaged; it was restored from its %s copy." % str(r.data["recovered_from"]))
	return true


func _confirm_delete(slot: String, team: String) -> void:
	app.host.modals.confirm("Delete this team?", "Delete '%s' and everything in it? This cannot be undone." % team, func() -> void:
		ctl.delete_profile(slot)
		show_entry(), true, "Delete")


# --- frame and navigation ------------------------------------------------------------------------------------------

func show_tab(tab_id: String) -> void:
	tab = tab_id
	var p := ctl.profile()
	var back: Callable = show_entry if tab_id == "hub" else func() -> void: show_tab("hub")
	var box := app._reset("Dynasty: %s" % p.team_name, {"id": "dynasty_" + tab_id, "skin": FcModeSkin.COLLECTIBLE, "back": back, "rebuild": func() -> void: show_tab(tab)})
	var mobile := app.layout.is_mobile()
	var exit_button := FcButton.make("Save and exit", FcButton.Variant.GHOST, show_entry)
	var nav := FcNavBar.new()
	nav.setup(TABS, tab_id, mobile, MOBILE_PRIMARY)
	nav.selected.connect(func(id: String) -> void: show_tab(id))
	var money := FcDynastyUi.wl(FcDynastyStyle.currency_text(p.balances), 15, true)
	money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mobile:
		var top := HBoxContainer.new()   # currencies and exit on top; the navigation bar goes along the bottom edge
		top.add_child(money)
		top.add_child(exit_button)
		box.add_child(top)
	else:
		var bar := HBoxContainer.new()
		nav.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(nav)
		bar.add_child(exit_button)
		box.add_child(bar)
		box.add_child(money)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	box.add_child(scroll)
	if mobile:
		app.host.set_bottom_bar(nav)   # along the bottom edge of the window, outside the screen's own layout
	var tip := app.hints.card("dynasty_" + tab_id)
	if tip != null:
		_body.add_child(tip)
	_body.add_child(_build_tab(tab_id))


## Rebuilds the current tab (after an action) and keeps the message that was just shown.
func refresh() -> void:
	var keep: String = app._message.text if app._message != null else ""
	show_tab(tab)
	if keep != "":
		say(keep)


func _build_tab(tab_id: String) -> Control:
	match tab_id:
		"collection":
			return FcDynastyScreensCollection.build_collection(self)
		"lineup":
			return FcDynastyScreensCollection.build_lineup(self)
		"packs":
			return FcDynastyScreensPacks.build_packs(self)
		"market":
			return FcDynastyScreensPacks.build_market(self)
		"play":
			return FcDynastyScreensPlay.build_play(self)
		"challenges":
			return FcDynastyScreensPlay.build_challenges(self)
		"tournament":
			return FcDynastyScreensPlay.build_tournament(self)
		"season":
			return FcDynastyScreensPlay.build_season(self)
	return _build_hub()


# --- helpers for screens ------------------------------------------------------------------------------------------

func heading(text: String) -> Label:
	return FcDynastyUi.wl(text, 20, true)


## A text label that wraps to the width it is given (a phone, a small window) instead of forcing the screen wider. `size` is a design size.
static func wl(text: String, size: int = 0, bold: bool = false) -> Label:
	var l := FcUiTables.label(text, size, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A button in the kit style (touch-sized on mobile layouts). `primary` makes it the screen's main action.
static func btn(text: String, on_press: Callable, primary: bool = false) -> FcButton:
	return FcButton.make(text, FcButton.Variant.PRIMARY if primary else FcButton.Variant.SECONDARY, on_press)


## A muted explanatory paragraph. `_width` is only a hint kept for older callers: the text wraps to the space available.
func note(text: String, _width: int = 520) -> Label:
	var l := wl(text, 14)
	l.add_theme_color_override("font_color", FcUiTheme.TEXT_MUTED)
	return l


func panel(children: Array) -> PanelContainer:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	p.add_child(v)
	for c in children:
		v.add_child(c)
	return p


func progress_bar(value: int, maximum: int) -> ProgressBar:
	var bar := FcProgress.new()
	bar.set_progress(float(value), float(maxi(1, maximum)))
	bar.custom_minimum_size = Vector2(110, 14)
	return bar


## Shows a card's detail window (attributes, badges, statistics, duplicate actions).
func show_card_detail(card_id: String) -> void:
	FcDynastyScreensCollection.show_detail(self, card_id)


# --- hub -----------------------------------------------------------------------------------------------------------

func _build_hub() -> Control:
	var s := ctl.hub_summary()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	if not s["playable"]:
		root.add_child(_onboarding_panel())
	# identity and strength
	var top := HBoxContainer.new()
	var ovr := FcDynastyUi.wl(str(s["overall"]), 54, true)
	ovr.tooltip_text = "Team overall, from your 13-player roster"
	top.add_child(ovr)
	var id_box := VBoxContainer.new()
	id_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_box.add_child(FcDynastyUi.wl("%s  (%s)" % [s["team_name"], s["abbreviation"]], 22))
	id_box.add_child(note("Team overall. %s" % (("Identity: " + ", ".join(s["identity"])) if not s["identity"].is_empty() else "Set a lineup to see your identity."), 420))
	var rec: Dictionary = s["record"]
	id_box.add_child(FcDynastyUi.wl("Record %d-%d    Points %d-%d    Streak %s" % [rec["wins"], rec["losses"], rec["points_for"], rec["points_against"], _streak(int(rec["streak"]))], 14))
	top.add_child(id_box)
	root.add_child(top)
	var featured := featured_card()
	if not featured.is_empty():
		root.add_child(_featured_panel(featured))
	# recommended next activity
	var next := _recommended(s)
	var rec_panel := PanelContainer.new()
	rec_panel.add_theme_stylebox_override("panel", FcDynastyStyle.box(FcUiTheme.ACCENT_SOFT, FcUiTheme.ACCENT, 2, 10, 10))
	var rv := VBoxContainer.new()
	rec_panel.add_child(rv)
	rv.add_child(FcDynastyUi.wl("Recommended next: %s" % next["title"], 18, true))
	rv.add_child(note(next["why"]))
	rv.add_child(FcDynastyUi.btn(next["button"], func() -> void: show_tab(str(next["tab"]))))
	root.add_child(rec_panel)
	var row := HFlowContainer.new()   # two columns on a wide screen, one under the other on a phone
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	# collection and season
	var col: Dictionary = s["collection"]
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(heading("Collection"))
	left.add_child(FcDynastyUi.wl("%d of %d cards (%d%%)" % [col["owned"], col["total"], col["percent"]]))
	left.add_child(progress_bar(col["owned"], col["total"]))
	var season: Dictionary = s["season"]
	left.add_child(heading("Season"))
	if season.is_empty():
		left.add_child(note("The loaded release has no season yet."))
	else:
		left.add_child(FcDynastyUi.wl("%s: %d season points" % [season["name"], season["points"]]))
		left.add_child(progress_bar(season["points"], maxi(season["top_milestone"], 1)))
	row.add_child(left)
	# challenges and packs
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(heading("Current challenges"))
	var shown := 0
	for c in ctl.challenge_listing():
		if c["claimed"] or shown >= 3:
			continue
		shown += 1
		right.add_child(FcDynastyUi.wl("%s  %d/%d%s" % [c["title"], c["progress"], c["target"], "  (claim it!)" if c["completed"] else ""], 14))
	if shown == 0:
		right.add_child(note("No open challenges."))
	right.add_child(heading("Packs you can open"))
	var affordable := 0
	for p in ctl.pack_listing():
		if p["affordable"]:
			affordable += 1
			right.add_child(FcDynastyUi.wl("%s: %s %s" % [p["name"], FcDynastyStyle._n(p["amount"]), p["currency"]], 14))
	if affordable == 0:
		right.add_child(note("Nothing you can afford right now. Play games and finish challenges to earn credits."))
	row.add_child(right)
	root.add_child(row)
	root.add_child(heading("Recent rewards and purchases"))
	if s["recent"].is_empty():
		root.add_child(note("Nothing yet."))
	for t in s["recent"]:
		root.add_child(FcDynastyUi.wl("%s   %s" % [_kind_name(str(t["kind"])), _deltas_text(t["deltas"])], 13))
	root.add_child(note("Content release %s. Card ratings, attributes and badges are static: they never change from playing or duplicates." % s["release_id"], 600))
	return root


## The card the hub shows off: the highest-rated card the player owns that the loaded release still has (ties: the lower card id).
## Chosen from existing data only; nothing is stored.
func featured_card() -> Dictionary:
	for row in ctl.collection_rows({"ownership": "owned"}, "overall_desc"):
		if bool(row["available"]):
			return row
	return {}


func _featured_panel(row: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.add_child(FcCardView.build(row, {"size": FcCardFace.SIZE_STANDARD, "on_click": func() -> void: show_card_detail(str(row["card_id"]))}))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := FcDynastyUi.wl("Featured card", FcUiTokens.TYPE_H3, true)
	words.add_child(title)
	words.add_child(FcDynastyUi.wl("%s (%s)" % [row["name"], row["edition"]], FcUiTokens.TYPE_BODY))
	words.add_child(note("Your highest-rated card. Click it to inspect, compare or turn it over.", 320))
	box.add_child(words)
	return box


func _recommended(s: Dictionary) -> Dictionary:
	if not s["playable"]:
		return {"title": "Add content", "why": "Dynasty needs published cards. See the notice above.", "button": "View collection", "tab": "collection"}
	if s["pending_openings"] > 0:
		return {"title": "Finish opening your pack", "why": "A pack you bought has cards waiting to be revealed.", "button": "Go to Packs", "tab": "packs"}
	if not s["lineup_ready"]:
		return {"title": "Set your lineup", "why": "A game needs 13 valid players: 5 starters, 7 bench and 1 reserve.", "button": "Open Lineup", "tab": "lineup"}
	if s["claimable"] > 0:
		return {"title": "Claim your rewards", "why": "%d challenge reward%s ready to claim." % [s["claimable"], " is" if s["claimable"] == 1 else "s are"], "button": "Open Challenges", "tab": "challenges"}
	if not s["tournament"].is_empty():
		return {"title": "Continue your tournament", "why": "You are still in %s." % s["tournament"]["name"], "button": "Open Tournament", "tab": "tournament"}
	for p in ctl.pack_listing():
		if p["affordable"] and p["amount"] > 0:
			return {"title": "Open a pack", "why": "You can afford %s." % p["name"], "button": "Open Packs", "tab": "packs"}
	return {"title": "Play a game", "why": "Games earn credits and move your challenges forward.", "button": "Play", "tab": "play"}


func _streak(value: int) -> String:
	if value > 0:
		return "W%d" % value
	if value < 0:
		return "L%d" % -value
	return "-"


func _kind_name(kind: String) -> String:
	return kind.replace("_", " ").capitalize()


func _deltas_text(deltas: Dictionary) -> String:
	var parts: Array[String] = []
	for c in deltas:
		parts.append("%s%d %s" % ["+" if int(deltas[c]) > 0 else "", int(deltas[c]), c])
	return ", ".join(parts)
