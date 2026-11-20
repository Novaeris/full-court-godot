extends SceneTree
## Drives the real Career Mode screens with simulated MOUSE CLICKS: main menu, create a player, let the draft decide (with the
## scouting report on screen), answer the first decision, play a week, spend development points, train, finish the season, save.
## After each click it checks that the career really changed.
##
## Run:  godot_console --headless --path . --script res://tools/career_click_test.gd   (or tools/career_click_test.ps1)
## Exit code 1 if any click did not do what it should.

var _app: FcApp
var _screen: SubViewport
var _problems: Array[String] = []
var _clicks := 0


func _initialize() -> void:
	_screen = SubViewport.new()
	_screen.size = Vector2i(1280, 800)
	_screen.gui_embed_subwindows = true
	root.add_child(_screen)
	_app = FcApp.new()
	_app.preferences = FcPreferences.new("user://test_preferences.cfg")
	_app.preferences.tutorial_done = true
	_app.saves = FcSaveManager.new("user://career_click_saves")
	_screen.add_child(_app)
	_app.setup()
	_run()


func _career_tab(index: int) -> void:
	for n in _all():
		if n is TabContainer and _visible(n):
			var bar: TabBar = (n as TabContainer).get_tab_bar()
			if bar.tab_count == 4:
				await _click_at(bar.get_global_rect().position + bar.get_tab_rect(index).get_center())
				return
	_fail("no Career tabs on screen")


func _run() -> void:
	await _frames(3)
	await _click_button("Career Mode")
	_expect(_find_button("Create a player") != null, "the Career Mode home opened")
	await _click_button("Create a player")
	var creator = _app._form.get("career_creator")
	_expect(creator != null, "the creator opened")
	if creator == null:
		_finish()
		return
	creator.set_field("first_name", "Maya")   # typing is not simulated; the build itself is the default
	creator.set_field("last_name", "Okoro")
	for step in 4:   # the creator is five steps; the build is checked and created on the last one
		await _click_button("Next step")
	await _click_button("Check my build")
	_expect(creator.check().is_empty(), "the default build with a name is valid")
	await _click_button("Create my player")
	await _frames(2)
	_expect(_app.career != null, "Create my player made the career")
	if _app.career == null:
		_finish()
		return
	var c := _app.career
	_expect(not c.is_signed(), "he starts without a team")

	await _career_tab(1)   # Season
	var outlook := c.draft_outlook()
	await _click_button("Let the draft decide")
	_expect(c.is_signed() and c.state.user_team_id == outlook["team_id"], "the draft signed him with the team the scouting report showed")

	var pending := c.pending_event()
	if not pending.is_empty():
		await _career_tab(1)
		await _click_button(pending["choices"][0]["label"])
		_expect(c.pending_event().is_empty(), "answering the decision with a click cleared it")

	await _career_tab(1)
	var played_before := c.state.current_date.to_iso()
	await _click_button("Play next week")
	_expect(c.state.current_date.to_iso() != played_before, "Play next week moved the calendar")

	await _career_tab(2)   # Develop
	c.profile().development_points += 12
	_app.show_career_hub()
	await _frames(2)
	await _career_tab(2)
	var points := c.profile().development_points
	var overall := FcCareerRules.overall_now(c.player())
	await _click_button("+1")
	_expect(c.profile().development_points < points, "a +1 click spent development points (%d -> %d)" % [points, c.profile().development_points])
	_expect(FcCareerRules.overall_now(c.player()) >= overall, "and did not lower the overall")
	await _career_tab(2)
	var xp := c.profile().xp
	await _click_button("Train")
	_expect(c.profile().xp > xp, "Train gave XP")

	await _career_tab(1)
	var seasons := c.profile().history.size()
	await _click_button("Finish the season")
	_expect(c.profile().history.size() == seasons + 1, "Finish the season recorded the season")

	await _click_button("Save")
	_expect(_app.saves.list_slots().size() >= 1, "Save wrote the career to disk")
	_finish()


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
	var parent := b.get_parent()
	while parent != null:   # like a player scrolling until the button is on screen
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(b)
			await _frames(2)
		parent = parent.get_parent()
	await _click_at(b.get_global_rect().get_center())


func _click_tab(name: String) -> void:
	var bar: TabBar = _app._tabs.get_tab_bar()
	var index := FcApp.TAB_NAMES.find(name)
	var rect := bar.get_tab_rect(index)
	await _click_at(bar.get_global_rect().position + rect.get_center())


## Clicks one of the pages inside the open tab (Finances: 0 summary, 1 prices, 2 sponsors and loans, 3 arena; Trades: 0 offers, 1 propose).
func _click_page(index: int) -> void:
	var pages := _app._tabs.get_current_tab_control() as TabContainer
	if pages == null:
		_fail("the Finances tab has no pages")
		return
	var bar := pages.get_tab_bar()
	await _click_at(bar.get_global_rect().position + bar.get_tab_rect(index).get_center())
	_expect(pages.current_tab == index, "the Finances page %d opened" % index)


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
	var dir := DirAccess.open("user://career_click_saves")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	quit(1 if not _problems.is_empty() else 0)
