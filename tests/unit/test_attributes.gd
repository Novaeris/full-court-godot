extends FcTestCase


func _small_catalog() -> FcAttributeCatalog:
	return FcAttributeCatalog.from_dict({
		"kind": "test",
		"definitions": [
			{"key": "a_one", "name": "A One", "category": "x", "min": 0, "max": 100, "default": 40},
			{"key": "b_two", "name": "B Two", "category": "y", "min": 10, "max": 20, "default": 15},
		],
	})


func test_shipped_definition_files_are_valid() -> void:
	var d := FcDefinitionSet.load_default()
	assert_eq(d.validate(), [] as Array[String], "definition problems")
	assert_eq(d.attributes.size(), 28, "attribute count")
	assert_eq(d.attributes.categories(), ["offensive", "defensive", "physical", "mental"] as Array[String])
	assert_eq(d.attributes.keys_in_category("offensive").size(), 10)
	assert_eq(d.attributes.keys_in_category("defensive").size(), 6)
	assert_eq(d.attributes.keys_in_category("physical").size(), 6)
	assert_eq(d.attributes.keys_in_category("mental").size(), 6)
	assert_true(d.personality.size() > 0)
	assert_true(d.tendencies.size() > 0)


func test_catalog_rejects_duplicates_and_bad_definitions() -> void:
	var c := FcAttributeCatalog.from_dict({"definitions": [
		{"key": "dup", "name": "Dup", "category": "x"},
		{"key": "dup", "name": "Dup again", "category": "x"},
		{"key": "Bad Key", "name": "Bad", "category": "x"},
		{"key": "range_bad", "name": "R", "category": "x", "min": 50, "max": 10, "default": 20},
		{"key": "default_bad", "name": "D", "category": "x", "min": 0, "max": 10, "default": 99},
	]})
	assert_eq(c.size(), 1, "only the first valid definition is kept")
	assert_true(not c.is_valid(), "catalog reports problems")
	assert_true(c.load_errors.size() >= 4, "each bad entry reported")


func test_catalog_missing_file_and_missing_list() -> void:
	var c := FcAttributeCatalog.from_file("res://data/definitions/does_not_exist.json")
	assert_true(not c.is_valid())
	var c2 := FcAttributeCatalog.from_dict({})
	assert_true(not c2.is_valid())


func test_attribute_set_defaults_and_validation() -> void:
	var s := FcAttributeSet.new(_small_catalog())
	assert_eq(s.get_value("a_one"), 40, "default value")
	assert_eq(s.set_value("a_one", 77), OK)
	assert_eq(s.get_value("a_one"), 77)
	assert_eq(s.set_value("a_one", 101), ERR_PARAMETER_RANGE_ERROR)
	assert_eq(s.set_value("b_two", 9), ERR_PARAMETER_RANGE_ERROR, "below custom min")
	assert_eq(s.set_value("nope", 5), ERR_DOES_NOT_EXIST)
	assert_eq(s.get_value("a_one"), 77, "failed set changes nothing")
	assert_eq(s.get_value("nope"), -1, "unknown key")


func test_attribute_set_clamped() -> void:
	var s := FcAttributeSet.new(_small_catalog())
	assert_eq(s.set_clamped("b_two", 999), OK)
	assert_eq(s.get_value("b_two"), 20)
	assert_eq(s.set_clamped("b_two", -5), OK)
	assert_eq(s.get_value("b_two"), 10)
	assert_eq(s.set_clamped("nope", 1), ERR_DOES_NOT_EXIST)


func test_attribute_set_save_compatibility() -> void:
	# Save written when the catalog had a removed key and lacked "b_two".
	var s := FcAttributeSet.from_dict(_small_catalog(), {"a_one": 60, "retired_key": 5, "b_two": 500})
	assert_eq(s.get_value("a_one"), 60)
	assert_eq(s.get_value("b_two"), 15, "out-of-range value rejected, default used")
	assert_eq(s.load_warnings.size(), 2, "unknown key + bad value reported")
	var out := s.to_dict()
	assert_eq(out.size(), 2, "only catalog keys are written")
	assert_eq(out["a_one"], 60)


func test_adding_attribute_to_catalog_needs_no_code_change() -> void:
	var c := _small_catalog()
	var s := FcAttributeSet.new(c)
	assert_eq(c.add_def(FcAttributeDef.from_dict({"key": "c_three", "name": "C", "category": "x", "default": 33})), OK)
	assert_eq(s.get_value("c_three"), 33, "new attribute appears with its default")
