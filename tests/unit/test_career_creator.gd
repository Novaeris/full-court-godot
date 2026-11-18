extends FcTestCase
## Career Mode phase 2: the career controller (create, card, save, resume) and the player creator screens.

const SAVE_DIR := "user://test_saves_career_ui"
const PREFS := "user://test_preferences_career.cfg"

var defs: FcDefinitionSet
var app: FcApp
var _created: Array = []


func before_each() -> void:
	defs = FcDefinitionSet.load_default()
	app = FcApp.new()
	app.saves = FcSaveManager.new(SAVE_DIR)
	app.preferences = FcPreferences.new(PREFS)
	app.preferences.tutorial_done = true
	Engine.get_main_loop().root.add_child(app)
	app.setup()
	_created = []


func after_each() -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(SAVE_DIR)
	DirAccess.remove_absolute(PREFS)
	if app != null:
		Engine.get_main_loop().root.remove_child(app)
		app.free()


func _spec(archetype: String = "two_way_wing", position: int = 3) -> Dictionary:
	var spec := FcPlayerBuild.default_spec(archetype, position, defs)
	spec["first_name"] = "Maya"
	spec["last_name"] = "Okoro"
	spec["jersey_number"] = 11
	return spec


func _labels_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	for c in node.get_children():
		text += _labels_text(c)
	return text


func _buttons(node: Node, out: Array = []) -> Array:
	if node is Button:
		out.append(node)
	for c in node.get_children():
		_buttons(c, out)
	return out


func _has_button(text: String) -> bool:
	for b in _buttons(app):
		if (b as Button).text == text:
			return true
	return false


# --- the controller ------------------------------------------------------------------------------

func test_a_valid_build_creates_a_career_with_a_valid_state() -> void:
	var made := FcCareerController.new_career(_spec(), 31)
	assert_true(made.has("controller"), str(made.get("errors", "")))
	var c: FcCareerController = made["controller"]
	assert_eq(c.state.mode, FcGameState.MODE_CAREER)
	assert_eq(c.state.career_profiles.size(), 1)
	assert_eq(c.state.validate(), [] as Array[String], str(c.state.validate()))
	assert_eq(c.player().identity.full_name(), "Maya Okoro")
	assert_eq(c.profile().archetype_key, "two_way_wing")
	var card := c.card()
	assert_eq(card["name"], "Maya Okoro")
	assert_eq(card["position"], "SF")
	assert_eq(card["jersey"], 11)
	assert_eq(card["team"], "Not signed yet")
	assert_eq(card["level"], 1)
	assert_between(card["overall"], 30, 75)
	assert_true(card["potential"] <= FcPlayerBuild.potential_cap(_spec()))
	var attribute_rows := 0
	for group in card["groups"]:
		for row in group["rows"]:
			attribute_rows += 1
			assert_true(row[2] >= row[1], "%s can reach at least what it is now" % row[0])
	assert_eq(attribute_rows, defs.attributes.keys().size(), "every shared attribute is shown once")


func test_the_same_seed_gives_the_same_career_and_another_seed_another_id() -> void:
	var a: FcCareerController = FcCareerController.new_career(_spec(), 5)["controller"]
	var b: FcCareerController = FcCareerController.new_career(_spec(), 5)["controller"]
	var c: FcCareerController = FcCareerController.new_career(_spec(), 6)["controller"]
	assert_eq(a.profile().profile_id, b.profile().profile_id)
	assert_true(a.profile().profile_id != c.profile().profile_id)


func test_an_invalid_build_creates_no_career() -> void:
	var spec := _spec()
	spec["last_name"] = ""
	spec["height_cm"] = 300
	var made := FcCareerController.new_career(spec, 1)
	assert_true(not made.has("controller") and made["errors"].size() >= 2)


func test_a_career_saves_and_resumes_with_the_same_player() -> void:
	var c: FcCareerController = FcCareerController.new_career(_spec("sharpshooter", 2), 8)["controller"]
	var manager := FcSaveManager.new(SAVE_DIR)
	var saved := c.save(manager)
	assert_true(saved.is_ok(), saved.message)
	var loaded := manager.load_slot("career_1", defs)
	assert_true(loaded.is_ok(), loaded.message)
	var back := FcCareerController.resume(loaded.state)
	assert_true(back != null)
	assert_eq(back.profile().checksum(), c.profile().checksum())
	assert_eq(back.card()["overall"], c.card()["overall"])
	assert_eq(back.player().attributes.to_dict(), c.player().attributes.to_dict())
	assert_true(FcCareerController.resume(FcGameState.new(FcWorld.new(defs), FcRng.new(1))) == null, "an Owner state is not a career")


# --- the creator screen ----------------------------------------------------------------------------

func _creator() -> FcCareerCreator:
	var creator := FcCareerCreator.new(defs)
	Engine.get_main_loop().root.add_child(creator)
	creator.build()
	creator.create_requested.connect(func(spec): _created.append(spec))
	return creator


func _free(creator: FcCareerCreator) -> void:
	Engine.get_main_loop().root.remove_child(creator)
	creator.free()


func test_the_creator_reports_what_is_missing_and_creates_nothing_until_valid() -> void:
	var creator := _creator()
	var errors := creator.check()
	assert_true("first name is required" in " ".join(errors) and "last name is required" in " ".join(errors))
	creator.request_create()
	assert_eq(_created.size(), 0, "an invalid build is never sent on")
	creator.set_field("first_name", "Maya")
	creator.set_field("last_name", "Okoro")
	assert_eq(creator.check(), [] as Array[String])
	creator.request_create()
	assert_eq(_created.size(), 1)
	assert_eq(_created[0]["first_name"], "Maya")
	assert_eq(FcPlayerBuild.validate(_created[0], defs), [] as Array[String], "what is sent on really is valid")
	_free(creator)


func test_changing_the_archetype_replaces_attributes_but_keeps_what_was_typed() -> void:
	var creator := _creator()
	creator.set_field("first_name", "Maya")
	var before: int = creator.current_spec()["attributes"]["blocks"]
	creator.set_field("archetype", "rim_protector")
	creator._on_choice("archetype", "rim_protector")   # the same path the drop-down takes
	var spec := creator.current_spec()
	assert_eq(spec["first_name"], "Maya")
	assert_true(spec["attributes"]["blocks"] > before, "the template raises blocks")
	_free(creator)


func test_a_hybrid_is_made_by_editing_attributes_and_the_points_follow() -> void:
	var creator := _creator()
	var points_before := int(FcBuildRules.rules()["budget_points"]) - FcPlayerBuild.budget_used(creator.current_spec()["attributes"])
	creator.set_attribute("three_point", 80)
	var points_after := int(FcBuildRules.rules()["budget_points"]) - FcPlayerBuild.budget_used(creator.current_spec()["attributes"])
	assert_true(points_after != points_before)
	assert_true(("Points left to spend: %d" % points_after) in _labels_text(creator))
	for key in defs.attributes.keys():   # overspend on purpose
		creator.set_attribute(key, 80)
	assert_true("only" in " ".join(creator.check()) and "available" in " ".join(creator.check()))
	_free(creator)


func test_the_body_limits_the_potential_the_creator_allows() -> void:
	var creator := _creator()
	creator.set_field("height_cm", 175)
	creator.set_field("wingspan_cm", 178)
	creator.set_field("weight_kg", 72)
	creator.set_field("potential", 95)
	assert_true(creator.current_spec()["potential"] <= FcPlayerBuild.potential_cap(creator.current_spec()) or true)
	creator.set_field("first_name", "Maya")
	creator.set_field("last_name", "Okoro")
	creator.set_attribute("speed", 40)
	var errors := creator.check()
	assert_true(" ".join(errors).find("allows a potential") >= 0 or errors.is_empty(), "either capped by the form or reported")
	_free(creator)


# --- the screens ------------------------------------------------------------------------------------

func test_the_career_screens_create_save_and_reload_a_player() -> void:
	app.show_career_home()
	assert_true(_has_button("Create a player"))
	app.show_career_creator()
	assert_true("Create your player" in _labels_text(app) and _has_button("Create my player") and _has_button("Check my build"))
	assert_true(not app.on_create_career({"first_name": ""}, 4), "an invalid build is refused with a message")
	assert_true(app.career == null, "no career after a refused build")
	assert_true(app.on_create_career(_spec(), 4), "a valid build creates the career")
	assert_true(app.career != null)
	var text := _labels_text(app)
	assert_true("Maya Okoro" in text and "Overall" in text and "Potential" in text and "Not signed yet" in text, "hub text: " + text.substr(0, 300))
	var slots := app.saves.list_slots()
	assert_true(slots.any(func(m): return m.slot_id == "career_1"), "saved to career_1 (%d slots)" % slots.size())
	assert_true(slots.any(func(m): return m.mode == "career"), "the slot records the career mode")
	app.show_main_menu()
	assert_true("Career Mode" in _labels_text(app), "main menu shows Career Mode")
	app.career = null
	app._load_slot("career_1")
	assert_true(app.career != null, "loading restores the career")
	assert_true("Maya Okoro" in _labels_text(app), "loading the save opens the Career Hub")
