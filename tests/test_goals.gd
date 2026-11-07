extends TestCase

var m: GameModel

func setup() -> void:
	m = new_farm(0.0)

func test_no_goals_during_the_tutorial() -> bool:
	eq(m.daily_goals(1000.0).size(), 0, "tutorial first")
	m.skip_tutorial()
	eq(m.daily_goals(1000.0).size(), 3, "three goals after it")
	return true

func test_goals_progress_claim_and_bonus_once() -> bool:
	m.skip_tutorial()
	var g := m.daily_goals(1000.0)
	eq(m.daily_goals(1000.0), g, "same goals all day")
	for x in g: truthy(x["stat"] in ["harvests", "planted", "served", "sold", "cooked"], "level 1: no animal goals (%s)" % x["stat"])
	eq(m.claim_goal(0, 1000.0), "not_ready", "nothing done yet")
	var gems: int = m.s["gems"]
	var coins: int = m.s["coins"]
	for i in 3: m.stat(g[i]["stat"], g[i]["n"])
	for i in 3: eq(m.claim_goal(i, 1000.0), "", "claim %d" % i)
	eq(m.claim_goal(0, 1000.0), "claimed", "only once")
	truthy(m.s["goals"]["bonus"] and m.s["gems"] - gems >= 3, "all-three bonus paid (level-up gems may add more)")
	truthy(m.s["coins"] > coins, "coins paid")
	return true

func test_new_day_new_goals_counted_from_then() -> bool:
	m.skip_tutorial()
	m.stat("harvests", 500)
	var tomorrow := 1000.0 + 86400.0
	for x in m.daily_goals(tomorrow): eq(x["progress"], 0, "yesterday's stats don't count")
	return true

func test_next_thing_follows_the_tutorial_then_priorities() -> bool:
	var W := preload("res://scripts/world/world.gd")
	var fresh := GameModel.new_game(0.0)
	eq(W.next_kind(fresh, 0.0), "", "welcome card: just read")
	fresh.tutorial_tap()
	eq(W.next_kind(fresh, 0.0), "parcel", "then: buy the field")
	m.skip_tutorial()
	eq(W.next_kind(m, 0.0), "plot_empty", "after: plant your empty plots")
	m.plant(0, "wheat", 0.0)
	eq(W.next_kind(m, 1000.0), "plot_ready", "ripe crops come first")
	return true
