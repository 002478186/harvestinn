extends TestCase

const DAY := 86400.0

func test_daily_streak_and_reset() -> bool:
	var m := GameModel.new_game(0.0)
	var t := 1_700_000_000.0
	eq(m.daily_index(t), 0, "day 1")
	eq(m.claim_daily(t)["coins"], 50, "day 1 reward")
	eq(m.daily_index(t + 60), -1, "once per day")
	for d in range(1, 7): m.claim_daily(t + d * DAY)
	eq(m.s["daily"]["streak"], 7, "7-day streak")
	truthy(m.achievement_done("streak"), "streak achievement")
	eq(m.daily_index(t + 7 * DAY), 0, "loops after day 7")
	m.claim_daily(t + 7 * DAY)
	eq(m.daily_index(t + 9 * DAY), 0, "missed a day -> restart")
	return true

func test_achievements_unlock_and_claim_once() -> bool:
	var m := GameModel.new_game(0.0)
	var got := []
	m.event.connect(func(n, d): if n == "achievement": got.append(d["id"]))
	m.plant(0, "wheat", 0.0)
	m.harvest(0, 100.0)
	eq(got, ["first_harvest"], "event fired once")
	eq(m.unclaimed_achievements(), 1, "1 to claim")
	var coins: int = m.s["coins"]
	eq(m.claim_achievement("first_harvest"), "", "claim")
	eq(m.s["coins"] - coins, 20, "reward")
	eq(m.claim_achievement("first_harvest"), "owned", "once")
	eq(m.claim_achievement("master_grower"), "not_ready", "not yet")
	return true

func test_events_by_date_including_new_year_wrap() -> bool:
	var oct := Time.get_unix_time_from_datetime_string("2026-10-15T12:00:00")
	var jan := Time.get_unix_time_from_datetime_string("2027-01-03T12:00:00")
	var aug := Time.get_unix_time_from_datetime_string("2026-08-15T12:00:00")
	truthy(GameModel.active_events(oct).any(func(e): return e["id"] == "harvest_moon"), "harvest moon in October")
	truthy(GameModel.active_events(jan).any(func(e): return e["id"] == "winter_cozy"), "winter wraps into January")
	eq(GameModel.active_events(aug).size(), 0, "nothing in mid-August")
	truthy(GameModel.market_price("pumpkin", oct) >= int(round(45 * 0.8 * 1.5)), "featured sell bonus")
	return true

func test_event_contribution_and_reward() -> bool:
	var m := GameModel.new_game(0.0)
	var oct := Time.get_unix_time_from_datetime_string("2026-10-15T12:00:00")
	m.add_items({"pumpkin": 30, "corn": 40}, true)
	eq(m.claim_event("harvest_moon", oct), "not_ready", "goal not met")
	eq(m.contribute_event("harvest_moon", "pumpkin", 30, oct), "", "give pumpkins")
	eq(m.count("pumpkin"), 5, "only 25 needed taken")
	m.contribute_event("harvest_moon", "corn", 40, oct)
	var gems: int = m.s["gems"]
	eq(m.claim_event("harvest_moon", oct), "", "claim")
	eq(m.s["gems"] - gems, 15, "gems")
	eq(m.s["decor"][-1]["id"], "decor_scarecrow", "decor reward")
	eq(m.claim_event("harvest_moon", oct), "owned", "once per year")
	return true
