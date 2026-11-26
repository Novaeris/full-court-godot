class_name FcOwnerNews
extends RefCounted
## The News tab: the league's news feed and the Full Court Tonight show.
## Moved out of FcApp unchanged in behaviour (Franchise Experience Overhaul M1, D-077); built from a FcOwnerContext like the other Owner tabs.


static func build(ctx: FcOwnerContext) -> Control:
	var controller := ctx.controller
	var w := controller.state.world
	var rows: Array = []
	var items: Array = w.news.duplicate()
	items.reverse()
	var mine := controller.state.user_team_id
	for item in items.slice(0, 80):
		var tag: String = {"injury": "Injury", "milestone": "Milestone", "champion": "Champions", "award": "Award", "signing": "Signing", "retirement": "Retirement", "draft": "Draft", "staff": "Staff"}.get(item["kind"], "News")
		rows.append([item["date"], tag, ("* " if item["team"] == mine else "") + item["text"]])
	var box := VBoxContainer.new()
	var bar := HBoxContainer.new()
	var show := FcButton.make("Full Court Tonight", FcButton.Variant.PRIMARY, func() -> void: ctx.open_tonight.call())
	show.name = "TonightButton"
	bar.add_child(show)
	box.add_child(bar)
	var table := FcTable.from_strings(["Date", "Type", "Headline"], rows, [100, 90, 0])
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(table)
	return box
