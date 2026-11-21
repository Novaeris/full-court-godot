extends FcTestCase
## FcTabPages (the kit's tab container used by the Owner and Career screens) and the ultrawide content-width cap on the screen host.


func _pages() -> FcTabPages:
	var pages := FcTabPages.new()
	for title in ["One", "Two", "Three"]:
		var page := Label.new()
		page.text = title
		pages.add_page(page, title)
	return pages


func test_only_the_open_page_is_visible() -> void:
	var pages := _pages()
	assert_eq(pages.get_tab_count(), 3)
	assert_eq(pages.current_tab, 0)
	assert_true(pages.get_current_tab_control().visible)
	pages.current_tab = 2
	assert_eq(pages.get_tab_title(pages.current_tab), "Three")
	var visible := 0
	for i in pages.get_tab_count():
		pages.current_tab = i
		if pages.get_current_tab_control().visible:
			visible += 1
	assert_eq(visible, 3, "each page is visible when it is the open one")
	pages.current_tab = 1
	assert_true(not (pages.get_child(1).get_child(0).get_child(0) as Control).visible, "and hidden when it is not")
	pages.free()


func test_an_out_of_range_page_is_clamped() -> void:
	var pages := _pages()
	pages.current_tab = 99
	assert_eq(pages.current_tab, 2)
	pages.current_tab = -4
	assert_eq(pages.current_tab, 0)
	pages.free()


func test_picking_a_tab_emits_but_setting_it_in_code_does_not() -> void:
	var pages := _pages()
	var seen: Array = []
	pages.tab_changed.connect(func(i: int) -> void: seen.append(i))
	pages.current_tab = 1
	assert_eq(seen, [], "code that sets the page stays quiet")
	pages.tab_button(2).pressed.emit()
	assert_eq(seen, [2], "a player's pick is announced")
	assert_eq(pages.current_tab, 2)
	pages.free()


func test_an_empty_set_of_pages_is_safe() -> void:
	var pages := FcTabPages.new()
	pages.current_tab = 3
	assert_eq(pages.get_tab_count(), 0)
	assert_true(pages.get_current_tab_control() == null)
	assert_eq(pages.get_tab_title(0), "")
	pages.free()


func test_content_is_capped_on_ultrawide_windows_only() -> void:
	assert_eq(FcScreenHost.side_padding(800), 0)
	assert_eq(FcScreenHost.side_padding(1920), 160, "1920 wide: 160 px on each side leaves 1600")
	assert_eq(FcScreenHost.side_padding(1600), 0)
	assert_eq(FcScreenHost.side_padding(3440), 920, "21:9 gets wide margins, the content stays 1600")
	assert_eq(FcScreenHost.side_padding(0), 0)


func test_long_sentences_wrap_and_short_ones_do_not() -> void:
	var page := VBoxContainer.new()
	var long_label := Label.new()
	long_label.text = "This is a very long sentence that would otherwise push the whole screen wider than a small window."
	var short_label := Label.new()
	short_label.text = "Payroll"
	page.add_child(long_label)
	page.add_child(short_label)
	FcTabPages.wrap_long_labels(page)
	assert_eq(long_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(long_label.custom_minimum_size.x >= FcTabPages.WRAP_MIN_WIDTH)
	assert_eq(short_label.autowrap_mode, TextServer.AUTOWRAP_OFF)
	page.free()
