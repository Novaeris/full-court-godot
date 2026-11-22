class_name FcDynastyController
extends RefCounted
## The one API Dynasty screens use (like FcGameController for Owner Mode). It owns the open profile session and the
## Dynasty catalog, and every state change goes through a domain service inside `session.commit()`, so a screen can never
## edit a balance or grant a card directly.
##
## Methods that change things return an FcDynastyResult; screens show `message` on failure.

var content: FcContentService
var defs: FcDefinitionSet
var store: FcDynastyStore
var catalog: FcDynastyCatalog
var session: FcDynastySession
## What the last open_profile found about the collection and the loaded release (see FcDynastyOnboarding.sync_release).
var release_note: Dictionary = {}
## The most recent finished game ({summary, reward, ...}) for the result screen.
var last_game: Dictionary = {}


func _init(content_service: FcContentService, definitions: FcDefinitionSet, profile_store: FcDynastyStore = null) -> void:
	content = content_service
	defs = definitions
	store = profile_store if profile_store != null else FcDynastyStore.new()
	refresh_content()


## Rebuilds the catalog from the currently loaded content release (call after content changes).
func refresh_content() -> void:
	var loaded: FcContentCatalog = content.catalog() if content != null else null
	catalog = FcDynastyCatalog.build(loaded, defs)


func profile() -> FcDynastyProfile:
	return session.profile if session != null else null


func has_profile_open() -> bool:
	return session != null


# --- profiles ---------------------------------------------------------------------------------------------------

## One entry per saved Dynasty profile: {slot, team_name, abbreviation, cards, credits, readable}.
func profiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in store.list_slots():
		var r := store.load_slot(slot)
		if r.ok:
			var p: FcDynastyProfile = r.data["profile"]
			out.append({"slot": slot, "team_name": p.team_name, "abbreviation": p.abbreviation, "cards": p.unique_owned(),
				"credits": p.balance("credits"), "record": "%d-%d" % [p.record["wins"], p.record["losses"]], "readable": true})
		else:
			out.append({"slot": slot, "team_name": "(damaged: %s)" % r.message, "abbreviation": "", "cards": 0, "credits": 0, "record": "", "readable": false})
	return out


## Creates a profile in the next free slot, grants the published starter collection and sets a first lineup if possible.
func create_profile(team_name: String, abbreviation: String, color_hex: String = "f58c29", seed_value: int = -1) -> FcDynastyResult:
	var name := team_name.strip_edges()
	var abbr := abbreviation.strip_edges().to_upper()
	if name.is_empty() or name.length() > 40:
		return FcDynastyResult.failure("bad_name", "Give your team a name of 1 to 40 characters.")
	if abbr.length() < 2 or abbr.length() > 4:
		return FcDynastyResult.failure("bad_abbreviation", "The abbreviation needs 2 to 4 letters.")
	var seed := seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system()) * 7919 + Time.get_ticks_usec()
	var slot := ""
	for n in range(1, 100):
		if not store.has_slot("dynasty_%d" % n):
			slot = "dynasty_%d" % n
			break
	if slot == "":
		return FcDynastyResult.failure("no_slot", "There are too many Dynasty teams; delete one first.")
	var fresh := FcDynastyProfile.create(name, abbr, seed, catalog.release_id(), color_hex)
	var s := FcDynastySession.new(fresh, store, slot)
	var made := s.commit(func() -> FcDynastyResult:
		var granted := FcDynastyOnboarding.grant_starter(s.profile, catalog)
		if granted.ok:
			FcDynastyLineup.auto_fill(s.profile, catalog)
		return granted)
	if not made.ok:
		return made
	session = s
	release_note = FcDynastyOnboarding.sync_release(s.profile, catalog)
	return FcDynastyResult.success({"slot": slot})


func open_profile(slot: String) -> FcDynastyResult:
	var r := store.load_slot(slot)
	if not r.ok:
		return r
	var s := FcDynastySession.new(r.data["profile"], store, slot)
	session = s
	var before := s.profile.release_history.size()
	release_note = FcDynastyOnboarding.sync_release(s.profile, catalog)
	if s.profile.release_history.size() != before:
		s.commit(func() -> FcDynastyResult: return FcDynastyResult.success())
	return FcDynastyResult.success({"recovered_from": r.data["recovered_from"]})


func close_profile() -> void:
	session = null


func delete_profile(slot: String) -> void:
	if session != null and session.slot == slot:
		session = null
	store.delete_slot(slot)


# --- collection ------------------------------------------------------------------------------------------------

func collection_rows(filters: Dictionary = {}, sort: String = "overall_desc") -> Array[Dictionary]:
	return FcCollectionQuery.rows(profile(), catalog, filters, sort)


func collection_progress() -> Dictionary:
	return FcCollectionQuery.progress(profile(), catalog)


## The detail view of one card (live release data, or the placeholder for an unavailable card), with ownership.
func card_detail(card_id: String) -> Dictionary:
	var rows := FcCollectionQuery.rows(profile(), catalog, {})
	for r in rows:
		if r["card_id"] == card_id:
			return r
	return {}


func convert_duplicate(card_id: String) -> FcDynastyResult:
	var rarity := str(card_detail(card_id).get("rarity", "common"))
	return session.commit(func() -> FcDynastyResult:
		return FcDynastyCollection.convert_duplicate(profile(), catalog.config, card_id, rarity, "conv:%s:%d" % [card_id, profile().txn_counter]))


func apply_mastery(card_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult:
		return FcDynastyCollection.apply_mastery(profile(), catalog.config, card_id, "mast:%s:%d" % [card_id, profile().txn_counter]))


# --- lineup ----------------------------------------------------------------------------------------------------

## The 13 roster slots for display: [{slot, name, card (view or {}), minutes}].
func roster_view() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var r := profile().roster
	for i in FcDynastyRoster.SIZE:
		var id := str(r.slots[i])
		var card := {}
		if id != "":
			card = card_detail(id) if catalog.has_card(id) or profile().cards.has(id) else {}
		out.append({"slot": i, "name": FcDynastyRoster.slot_name(i), "card": card, "minutes": int(r.minutes[i])})
	return out


func lineup_problems() -> Array[String]:
	return FcDynastyLineup.problems(profile(), catalog)


func team_overall() -> int:
	return roundi(FcDynastyLineup.team_overall(profile(), catalog))


func team_identity() -> Array[String]:
	return FcDynastyLineup.identity(profile(), catalog)


func candidates_for(slot: int) -> Array[Dictionary]:
	return FcDynastyLineup.candidates(profile(), catalog, slot)


func recommended_lineup() -> Array[String]:
	return FcDynastyLineup.recommend(profile(), catalog)


func assign_slot(slot: int, card_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyLineup.assign(profile(), catalog, slot, card_id))


func clear_slot(slot: int) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyLineup.clear_slot(profile(), slot))


func set_minutes(slot: int, value: int) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyLineup.set_minutes(profile(), slot, value))


func auto_fill_lineup() -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyLineup.auto_fill(profile(), catalog))


# --- packs and market ------------------------------------------------------------------------------------------

## Packs for sale with everything the player should see before buying (published odds included).
func pack_listing() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in catalog.buyable_packs():
		var def: Dictionary = catalog.packs()[id]
		var price: Dictionary = def["price"]
		out.append({"pack_id": id, "name": str(def.get("name", id)), "currency": str(price["currency"]), "amount": int(price["amount"]),
			"cards_per_pack": int(def.get("cards_per_pack", def.get("card_ids", []).size())), "odds": def.get("odds", {}),
			"guarantees": def.get("guarantees", []), "pity": def.get("pity", {}), "fixed": not def.has("odds"),
			"affordable": profile().balance(str(price["currency"])) >= int(price["amount"]),
			"pity_progress": int(profile().pity.get(id, 0))})
	return out


## Buys and opens a pack. The cards are already in the collection and recorded when this returns; the screen only reveals them.
func buy_pack(pack_id: String) -> FcDynastyResult:
	var request := "buy:%s:%d" % [pack_id, profile().opening_counter + 1]
	return session.commit(func() -> FcDynastyResult:
		var r := FcDynastyPacks.buy_and_open(profile(), catalog, pack_id, request)
		if r.ok:
			FcDynastyMarket.collection_changed(profile(), catalog)
		return r)


func pending_openings() -> Array:
	return FcDynastyPacks.pending_openings(profile())


func acknowledge_opening(opening_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyPacks.acknowledge(profile(), opening_id))


func market_listing() -> Array[Dictionary]:
	return FcDynastyMarket.listing(profile(), catalog)


func acquire_card(card_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult:
		return FcDynastyMarket.acquire(profile(), catalog, card_id, "acq:%s:%d" % [card_id, profile().txn_counter]))


# --- games, challenges, season, tournament ----------------------------------------------------------------------




func opponent_levels() -> Array:
	return catalog.config.opponent_levels()


## Collection goals with their progress, and the claim for a finished one.
func goal_listing() -> Array:
	return FcDynastyGoals.listing(profile(), catalog)


func claim_goal(goal_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyGoals.claim(profile(), catalog, goal_id))


## The ranked ladder for the ladder panel: rating, tier, rank among the computer field, the top of the standings and past seasons.
func ladder_view() -> Dictionary:
	return FcDynastyLadder.view(profile())


func play_quick_game(level_id: String) -> FcDynastyResult:
	var r := session.commit(func() -> FcDynastyResult: return FcDynastyPlay.quick_game(profile(), catalog, level_id))
	if r.ok:
		last_game = r.data
	return r


func challenge_listing() -> Array[Dictionary]:
	return FcDynastyChallenges.listing(profile(), catalog)


func claim_challenge(challenge_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyChallenges.claim(profile(), catalog, challenge_id))


func season_overview() -> Dictionary:
	return FcDynastySeason.overview(profile(), catalog)


func claim_milestone(milestone_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult:
		return FcDynastySeason.claim_milestone(profile(), catalog, catalog.active_season_id(), milestone_id))


## Tournaments the active season offers: [{tournament_id, name, fee_currency, fee_amount, rewards}].
func tournament_listing() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in catalog.season(catalog.active_season_id()).get("tournaments", []):
		var fee: Dictionary = t.get("entry_fee", {})
		out.append({"tournament_id": str(t["tournament_id"]), "name": str(t["name"]), "fee_currency": str(fee.get("currency", "credits")),
			"fee_amount": int(fee.get("amount", 0)), "rewards": t.get("rewards", {})})
	return out


func active_tournament() -> Dictionary:
	return FcDynastyTournament.active(profile())


func tournament_history() -> Array:
	return profile().tournament.get("history", [])


func enter_tournament(tournament_id: String) -> FcDynastyResult:
	return session.commit(func() -> FcDynastyResult: return FcDynastyTournament.enter(profile(), catalog, tournament_id))


func play_tournament_match() -> FcDynastyResult:
	var r := session.commit(func() -> FcDynastyResult: return FcDynastyTournament.play_next(profile(), catalog))
	if r.ok and not r.data["summary"].is_empty():
		last_game = {"summary": r.data["summary"], "reward": 0}
		last_game.merge(r.data.get("shown", {}))   # the box score for the post-game screen (transient, never saved)
	return r


## The numbers the hub shows at a glance.
func hub_summary() -> Dictionary:
	var p := profile()
	var season := season_overview()
	var open_challenges := 0
	var claimable := 0
	for c in challenge_listing():
		if c["completed"] and not c["claimed"]:
			claimable += 1
		elif not c["completed"]:
			open_challenges += 1
	return {"team_name": p.team_name, "abbreviation": p.abbreviation, "overall": team_overall(), "identity": team_identity(),
		"balances": p.balances.duplicate(), "collection": collection_progress(), "record": p.record.duplicate(),
		"season": season, "claimable": claimable, "open_challenges": open_challenges,
		"pending_openings": pending_openings().size(), "lineup_ready": lineup_problems().is_empty(),
		"playable": catalog.is_playable(), "problem": catalog.playable_problem(), "tournament": active_tournament(),
		"recent": p.ledger.slice(maxi(0, p.ledger.size() - 5)), "release_id": catalog.release_id()}
