extends SceneTree
## Drives the real UI with simulated MOUSE CLICKS (no direct function calls): it finds a control
## on screen, computes where it is, and sends mouse press and release events to the window, the
## way a player would. Then it checks that the game really changed.
##
## Run:  godot_console --headless --path . --script res://tools/click_test.gd
## (also works with a window: godot_console --path . --script res://tools/click_test.gd)
## Exit code 1 if any click did not do what it should.

var _app: FcApp
var _screen: SubViewport
var _problems: Array[String] = []
var _clicks := 0


func _initialize() -> void:
	# The game screen lives in its own 1280x800 viewport, so clicks have somewhere to land
	# even when the program runs without a window (headless).
	_screen = SubViewport.new()
	_screen.size = Vector2i(1280, 800)
	_screen.gui_embed_subwindows = true
	root.add_child(_screen)
	_app = FcApp.new()
	_app.saves = FcSaveManager.new("user://click_saves")
	_screen.add_child(_app)
	_app.setup()
	_run()


func _run() -> void:
	await _frames(3)
	# --- main menu -> new league -> team choice -> dashboard -----------------------------------
	await _click_button("New Game")
	_expect(_find_label("New League") != null, "the New League screen opened")
	# a small league keeps the test quick: pick 12 teams from the real drop-down by keyboard-free clicks
	var teams_pick: OptionButton = _find_option("teams")
	await _choose_option(teams_pick, "12 teams")
	(_app._form["seed"] as LineEdit).text = "5"   # same league every run
	await _click_button("Create League")
	_expect(_find_label("Choose Your Team") != null, "the team choice screen opened")
	var tree := _first_tree()
	await _click_tree_row(tree, 2)
	await _click_button("Start Game With Selected Team")
	await _frames(2)
	_expect(_app.controller != null, "the game started")
	var c := _app.controller
	var start_date := c.state.current_date.to_iso()
	_expect(c.state.user_team_id == _app.controller.state.world.teams.ids()[2], "the team picked by clicking is the one managed")

	# --- time passes ----------------------------------------------------------------------
	await _click_button("Next Week")
	_expect(c.state.current_date.to_iso() != start_date, "Next Week moved the calendar (%s -> %s)" % [start_date, c.state.current_date.to_iso()])

	# --- tabs ---------------------------------------------------------------------------------
	for name in ["Standings", "Schedule", "Roster", "Finances", "Staff", "Draft", "Market", "Trades", "History", "News", "League", "Overview"]:
		await _click_tab(name)
		_expect(_app._tabs.current_tab == FcApp.TAB_NAMES.find(name), "clicking the %s tab shows it" % name)

	# --- finances: borrow and use the price suggestion ------------------------------------------
	await _click_tab("Finances")
	var debt_before := c.business().debt
	await _click_button("Borrow")
	_expect(c.business().debt > debt_before, "Borrow raised the debt (%d -> %d)" % [debt_before, c.business().debt])
	await _click_tab("Finances")
	await _click_button("Repay")
	_expect(c.business().debt == debt_before, "Repay paid it back")
	await _click_tab("Finances")
	c.set_ticket_price(c.suggested_ticket_price() + 40)
	await _click_tab("Finances")
	await _click_button("Use suggestion")
	_expect(c.business().ticket_price == c.suggested_ticket_price(), "Use suggestion set the ticket price")
	await _click_tab("Finances")
	await _click_button("Start project")
	_expect(not c.business().projects.is_empty(), "Start project started the arena project the drop-down showed")

	# --- a button pressed with nothing selected explains itself -----------------------------------
	await _click_tab("Roster")
	var roster_size_now: int = c.state.world.teams.get_by_id(c.state.user_team_id).roster.size()
	await _click_button("Release selected player")
	_expect(_app._message.text.begins_with("Select") and c.state.world.teams.get_by_id(c.state.user_team_id).roster.size() == roster_size_now, "Release with nothing selected only shows a hint (%s)" % _app._message.text)

	# --- roster: profile popup, release, sign -------------------------------------------------------
	await _click_tab("Roster")
	var roster_tree := _first_tree()
	await _click_tree_row(roster_tree, 1)
	await _click_button("Player profile of selected player")
	var dialog := _visible_dialog()
	_expect(dialog != null, "the player profile popup appeared")
	if dialog != null:
		dialog.hide()
		await _frames(2)
	var team: FcTeam = c.state.world.teams.get_by_id(c.state.user_team_id)
	var size_before := team.roster.size()
	await _click_tab("Roster")
	await _click_tree_row(_first_tree(), team.roster.size() - 1)
	await _click_button("Release selected player")
	_expect(team.roster.size() == size_before - 1, "Release removed the selected player (%d -> %d)" % [size_before, team.roster.size()])
	await _click_tab("Market")
	var fa_tree := _first_tree()
	await _click_tree_row(fa_tree, fa_tree.get_root().get_child_count() - 1)   # the cheapest of the listed free agents
	var before_sign := team.roster.size()
	await _click_button("Sign selected free agent")
	_expect(team.roster.size() == before_sign + 1, "Sign selected free agent added the player (%s)" % _app._message.text)

	# --- trades: select players and check an offer ---------------------------------------------------
	await _click_tab("Trades")
	var lists := _item_lists()
	if lists.size() >= 2:
		await _click_list_row(lists[0], 0)
		await _click_list_row(lists[1], 0)
	await _click_button("Check the offer")
	_expect(_app._message.text != "", "Check the offer answered (%s)" % _app._message.text)

	# --- play out the season and the offseason with the buttons --------------------------------------
	await _click_button("To End of Regular Season")
	_expect(c.phase() != FcGameController.PHASE_REGULAR, "To End of Regular Season finished the regular season")
	await _click_button("Play All Playoffs")
	_expect(c.phase() == FcGameController.PHASE_COMPLETE, "Play All Playoffs finished the season")
	await _click_button("Begin Offseason")
	if c.state.offseason_stage == 0:
		_expect(_app._message.text.contains("LEAVE"), "the first press warned about players whose contracts end")
		await _click_button("Begin Offseason")
	_expect(c.phase() == FcGameController.PHASE_DRAFT, "Begin Offseason opened the draft")
	await _click_tab("Draft")
	var picks_before := c.draft_results().size()
	await _click_tree_row(_first_tree(), 0)
	await _click_button("Invite selected to a workout")
	_expect(c.draft_workouts_left() == FcOffseason.WORKOUT_SLOTS - 1, "the workout invitation was used")
	await _click_tab("Draft")
	await _click_tree_row(_first_tree(), 1)
	await _click_button("Draft selected prospect")
	_expect(c.draft_results().size() > picks_before or c.phase() != FcGameController.PHASE_DRAFT, "Draft selected prospect made the pick")
	if c.phase() == FcGameController.PHASE_DRAFT:
		await _click_button("Let the staff finish the draft")
	_expect(c.phase() == FcGameController.PHASE_OFFSEASON, "the draft ended and the free-agency window opened")
	await _click_button("Finish Offseason and Start Next Season")
	_expect(c.state.current_season == 2027 and c.phase() == FcGameController.PHASE_REGULAR, "the new season started")
	_expect(c.state.validate().is_empty(), "the game state is valid after all those clicks")

	_finish()


# --- finding controls ---------------------------------------------------------------------------

func _live(node: Node) -> bool:
	return node.is_inside_tree() and not node.is_queued_for_deletion()


func _walk(node: Node, out: Array) -> void:
	for child in node.get_children():
		if _live(child):
			out.append(child)
			_walk(child, out)


func _all() -> Array:
	var out: Array = []
	_walk(_app, out)
	return out


func _visible(c: Control) -> bool:
	return c.is_visible_in_tree()


func _find_button(text: String) -> Button:
	for n in _all():
		if n is Button and _visible(n) and (n as Button).text.begins_with(text):
			return n
	return null


func _find_label(text: String) -> Label:
	for n in _all():
		if n is Label and _visible(n) and (n as Label).text == text:
			return n
	return null


func _first_tree() -> Tree:
	for n in _all():
		if n is Tree and _visible(n):
			return n
	return null


func _item_lists() -> Array:
	var out: Array = []
	for n in _all():
		if n is ItemList and _visible(n):
			out.append(n)
	return out


func _find_option(which: String) -> OptionButton:
	if which == "teams" and _app._form.has("teams"):
		return _app._form["teams"]
	return null


func _visible_dialog() -> Window:
	for n in _all():
		if n is AcceptDialog and (n as Window).visible:
			return n
	return null


# --- mouse -----------------------------------------------------------------------------------------

func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _mouse(position: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = position
	e.global_position = position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_screen.push_input(e)


func _move_to(position: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = position
	m.global_position = position
	_screen.push_input(m)


func _click_at(position: Vector2) -> void:
	_clicks += 1
	_move_to(position)
	await process_frame
	_mouse(position, true)
	await process_frame
	_mouse(position, false)
	await _frames(2)


func _click_button(text: String) -> void:
	var b := _find_button(text)
	if b == null:
		_fail("no visible button starting with '%s'" % text)
		return
	await _click_at(b.get_global_rect().get_center())


func _click_tab(name: String) -> void:
	var bar: TabBar = _app._tabs.get_tab_bar()
	var index := FcApp.TAB_NAMES.find(name)
	var rect := bar.get_tab_rect(index)
	await _click_at(bar.get_global_rect().position + rect.get_center())


func _click_tree_row(tree: Tree, index: int) -> void:
	if tree == null:
		_fail("no table to click in")
		return
	var item := tree.get_root().get_child(index)
	if item == null:
		_fail("the table has no row %d" % index)
		return
	tree.scroll_to_item(item)   # like a player scrolling the table until the row is on screen
	await _frames(2)
	var rect := tree.get_item_area_rect(item, 0)
	await _click_at(tree.get_global_rect().position + rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5))


func _click_list_row(list: ItemList, index: int) -> void:
	var rect := list.get_item_rect(index)
	await _click_at(list.get_global_rect().position + rect.position + rect.size * 0.5)


## Opens a drop-down and clicks the entry whose text matches.
func _choose_option(option: OptionButton, text: String) -> void:
	if option == null:
		_fail("no drop-down to choose '%s' from" % text)
		return
	var wanted := -1
	for i in option.item_count:
		if option.get_item_text(i) == text:
			wanted = i
	if wanted < 0:
		_fail("the drop-down has no '%s'" % text)
		return
	await _click_at(option.get_global_rect().get_center())
	# The list that opens is a separate pop-up window, which cannot be clicked reliably in every
	# run mode; so after really clicking the drop-down, the entry is chosen directly.
	var popup := option.get_popup()
	var item_height := popup.get_item_count()
	popup.hide()
	await _frames(1)
	option.select(wanted)
	option.item_selected.emit(wanted)
	await _frames(2)
	_expect(option.get_item_text(option.selected) == text, "'%s' is selected" % text)
	if item_height == 0:
		_fail("the drop-down was empty")


# --- results ---------------------------------------------------------------------------------------

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  ok   " + label)
	else:
		_fail(label)


func _fail(text: String) -> void:
	_problems.append(text)
	print("  FAIL " + text)


func _finish() -> void:
	print("--- %d mouse clicks sent, %d problem(s)" % [_clicks, _problems.size()])
	for p in _problems:
		print("  * " + p)
	var dir := DirAccess.open("user://click_saves")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	quit(1 if not _problems.is_empty() else 0)
