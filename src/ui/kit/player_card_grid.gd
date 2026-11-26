class_name FcPlayerCardGrid
extends ScrollContainer
## A roster (or a prospect board, or a market) as player cards: FcPlayerTile per player in a wrapping grid, with one card selected at a
## time. Clicking a card selects it (`player_selected`); double-clicking or Enter activates it (`player_activated`, e.g. open the profile).
## The cards come from FcPlayerPresentation view models, so every look, number and rating is the same one the rest of the game shows.

signal player_selected(player_id: int)
signal player_activated(player_id: int)

var _flow := HFlowContainer.new()
var _tiles: Dictionary = {}
var selected_id: int = 0
var tile_size: Vector2 = FcPlayerTile.SIZE_MEDIUM


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # grows to show every card; the page around it scrolls (set AUTO for a fixed-height board)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", FcUiTokens.SPACE_3)
	_flow.add_theme_constant_override("v_separation", FcUiTokens.SPACE_3)
	add_child(_flow)


## `cards`: [{"id": int, "vm": Dictionary (FcPlayerPresentation, plus optional "number", "potential", "stat_line", "injury")}].
func set_cards(cards: Array, size_of_tile: Vector2 = FcPlayerTile.SIZE_MEDIUM) -> FcPlayerCardGrid:
	tile_size = size_of_tile
	for c in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	_tiles.clear()
	for card in cards:
		var id := int(card["id"])
		var tile := FcPlayerTile.new().setup(card["vm"], size_of_tile)
		tile.selected = id == selected_id
		tile.activated.connect(func() -> void: select(id))
		tile.opened.connect(func() -> void: player_activated.emit(id))
		_flow.add_child(tile)
		_tiles[id] = tile
	return self


func card_count() -> int:
	return _tiles.size()


func tile_of(player_id: int) -> FcPlayerTile:
	return _tiles.get(player_id)


func select(player_id: int, emit: bool = true) -> void:
	selected_id = player_id
	for id in _tiles:
		(_tiles[id] as FcPlayerTile).selected = id == player_id
	if emit:
		player_selected.emit(player_id)
