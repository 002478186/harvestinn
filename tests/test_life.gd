extends TestCase

const Interiors := preload("res://scripts/world/interiors.gd")
const Villagers := preload("res://scripts/world/villagers.gd")

func test_guests_keep_their_table_when_others_leave() -> bool:
	var s := Interiors.assign_seats({}, ["a", "b", "c"], 4)
	eq(s, {"a": 0, "b": 1, "c": 2}, "first come, lowest table")
	s = Interiors.assign_seats(s, ["a", "c"], 4)
	eq(s["c"], 2, "c stays put after b leaves")
	s = Interiors.assign_seats(s, ["a", "c", "d"], 4)
	eq(s["d"], 1, "newcomer takes the freed table")
	return true

func test_more_villagers_by_day_than_night() -> bool:
	truthy(Villagers.wanted(12.0) > Villagers.wanted(20.0), "day busier than evening")
	truthy(Villagers.wanted(20.0) > Villagers.wanted(2.0), "evening busier than night")
	truthy(Villagers.wanted(2.0) > 0, "night owls")
	return true

func test_routes_walk_around_the_fountain() -> bool:
	var r := Villagers.route(Vector3(0, 0, -1), Vector3(0, 0, -10))
	eq(r.size(), 2, "detour point added")
	truthy(Vector3(r[0]).distance_to(Vector3(0, 0, -5.5)) > 3.0, "detour clears the basin")
	eq(Villagers.route(Vector3(-8, 0, -3), Vector3(-14, 0, -2.5)).size(), 1, "clear paths go straight")
	return true
