class_name FcTestData
extends RefCounted
## Builders for valid sample entities, used only by tests.
## Not real game content: real players/teams will come from procedural generation.


static func defs() -> FcDefinitionSet:
	return FcDefinitionSet.load_default()


static func player(id: int, definitions: FcDefinitionSet) -> FcPlayer:
	var p := FcPlayer.new(id, definitions)
	p.identity.first_name = "Test"
	p.identity.last_name = "Player%d" % id
	p.identity.country = "Testland"
	p.identity.birth_date = FcDate.new(2001, 5, 17)
	p.primary_position = FcPosition.Id.PG
	return p


static func city(id: int) -> FcCity:
	var c := FcCity.new(id)
	c.name = "Testville"
	c.country = "Testland"
	return c


static func arena(id: int, city_id: int) -> FcArena:
	var a := FcArena.new(id)
	a.name = "Test Arena"
	a.city_id = city_id
	return a


static func team(id: int, city_id: int, arena_id: int) -> FcTeam:
	var t := FcTeam.new(id)
	t.city_id = city_id
	t.arena_id = arena_id
	t.identity.nickname = "Testers"
	t.identity.abbreviation = "TST"
	return t


static func contract(id: int, player_id: int, team_id: int) -> FcContract:
	var c := FcContract.new(id)
	c.player_id = player_id
	c.team_id = team_id
	c.years.append(FcContractYear.new(2026, 1000000))
	c.years.append(FcContractYear.new(2027, 1200000))
	return c


## A valid playthrough state around the sample world, controlling team 1.
static func game_state() -> FcGameState:
	var s := FcGameState.new(world(), FcRng.new(424242))
	s.user_team_id = 1
	return s


## A small healthy world: 1 city, 1 arena, 1 team, 2 players on its roster with contracts.
static func world() -> FcWorld:
	var d := defs()
	var w := FcWorld.new(d)
	w.cities.add(city(w.ids.next_id(FcWorld.KIND_CITY)))
	w.arenas.add(arena(w.ids.next_id(FcWorld.KIND_ARENA), 1))
	var t := team(w.ids.next_id(FcWorld.KIND_TEAM), 1, 1)
	w.teams.add(t)
	for i in 2:
		var p := player(w.ids.next_id(FcWorld.KIND_PLAYER), d)
		w.players.add(p)
		t.roster.add(p.id)
		w.contracts.add(contract(w.ids.next_id(FcWorld.KIND_CONTRACT), p.id, t.id))
	return w
