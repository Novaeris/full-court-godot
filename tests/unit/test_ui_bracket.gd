extends FcTestCase
## The bracket (Phase H): rounds in columns, matches joined by connectors, winners marked, the user's match highlighted, everything also as text,
## and a stack of panels instead of a drawing on touch layouts.

func _rounds() -> Array:
	return [
		{"round_name": "Quarterfinal", "matches": [
			{"a": "Harbor", "b": "Sky", "score": "88-80", "winner": "Harbor", "played": true, "you": true},
			{"a": "Pine", "b": "Ridge", "score": "70-75", "winner": "Ridge", "played": true, "you": false},
			{"a": "Lake", "b": "Peak", "score": "", "winner": "", "played": false, "you": false},
			{"a": "Bay", "b": "Cove", "score": "", "winner": "", "played": false, "you": false}]},
		{"round_name": "Semifinal", "matches": [
			{"a": "Harbor", "b": "Ridge", "score": "", "winner": "", "played": false, "you": true},
			{"a": "TBD", "b": "TBD", "score": "", "winner": "", "played": false, "you": false}]},
		{"round_name": "Final", "matches": [{"a": "TBD", "b": "TBD", "score": "", "winner": "", "played": false, "you": false}]}]


func test_the_bracket_counts_every_match_and_sizes_itself_to_its_rounds() -> void:
	var b := FcBracket.new(_rounds())
	assert_eq(b.match_count(), 7)
	assert_eq(b.custom_minimum_size.x, 3.0 * (FcBracket.BOX_W + FcBracket.GAP_X) - FcBracket.GAP_X)
	assert_true(b.custom_minimum_size.y >= 4.0 * FcBracket.BOX_H, "tall enough for four first-round matches")
	b.free()


func test_a_later_match_sits_between_the_two_that_feed_it() -> void:
	var b := FcBracket.new(_rounds())
	var first: Array = b._centers[0]
	var second: Array = b._centers[1]
	assert_eq(second[0], (float(first[0]) + float(first[1])) / 2.0)
	assert_eq(second[1], (float(first[2]) + float(first[3])) / 2.0)
	assert_eq(b._centers[2][0], (float(second[0]) + float(second[1])) / 2.0, "the final sits between the semifinals")
	b.free()


func test_the_bracket_describes_every_match_in_words() -> void:
	var b := FcBracket.new(_rounds())
	var text := b.summary()
	assert_true("Quarterfinal: Harbor vs Sky (88-80), winner Harbor" in text)
	assert_true("Semifinal: Harbor vs Ridge" in text and "winner" not in text.split("\n")[4], "an unplayed match names no winner")
	assert_eq(b.tooltip_text, text, "the same words as the tooltip")
	b.free()


func test_an_empty_bracket_is_harmless() -> void:
	var b := FcBracket.new([])
	assert_eq(b.match_count(), 0)
	assert_eq(b.summary(), "")
	b.free()


func test_touch_layouts_get_a_stack_of_match_panels_not_a_drawing() -> void:
	var stack := FcBracket.build(_rounds(), true)
	assert_true(not (stack is FcBracket), "a phone gets panels")
	var panels := stack.find_children("*", "FcPanel", true, false)
	assert_eq(panels.size(), 7, "one panel per match")
	var wide := FcBracket.build(_rounds(), false)
	assert_true(wide is FcBracket)
	stack.free()
	wide.free()


func test_the_compact_stack_marks_the_winner_with_a_check_and_keeps_the_scores() -> void:
	var stack := FcBracket.build(_rounds(), true)
	var texts: Array = []
	for l in stack.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_true("✓ Harbor" in texts and "✓ Ridge" in texts, "winners carry a check")
	assert_true("88-80" in texts)
	stack.free()
