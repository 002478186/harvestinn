## The first 10 minutes, played by a simple greedy player against the real rules:
## walking between the field, the inn and the stall costs time, every action costs 5 s.
## Asserts there is never more than 60 s between rewards (harvest, cook, serve, sell,
## level up, goal claimed, tutorial gift).
extends TestCase

const WALK := 6.0     # field, inn and stall are 14-18 m apart; walking is 3.2 m/s
const ACT := 5.0
const REWARDS := ["harvest", "collect", "served", "sold", "level_up", "goal", "land"]

var m: GameModel
var t := 0.0
var at := "square"
var rewards: Array[float] = []

func _go(place: String) -> void:
	if at != place:
		t += WALK
		at = place

func _act() -> void:
	t += ACT
	m.tick(t)

func test_rewards_every_minute_in_the_first_ten() -> bool:
	m = GameModel.new_game(0.0)
	m.owns_building("kitchen")   # the inn kitchen exists from the start (created lazily)
	m.event.connect(func(name: String, d: Dictionary):
		if name in REWARDS or name == "tutorial" and not GameData.tutorial()[int(d.get("step", 1)) - 1].get("reward", {}).is_empty(): rewards.append(t))
	t = 25.0                       # character creator
	m.tutorial_tap()               # welcome
	_go("field"); m.buy_parcel(); _act()
	while t < 600.0:
		var did := _step()
		if not did: _act()      # nothing to do: idle 5 s (counts against the gaps)
	var gaps: Array[float] = []
	var last := 0.0
	for r in rewards:
		gaps.append(r - last)
		last = r
	gaps.append(600.0 - last)
	var worst: float = gaps.max()
	truthy(worst <= 60.0, "longest wait for a reward: %.0f s (rewards at %s)" % [worst, str(rewards.map(func(x): return int(x)))])
	truthy(m.tutorial_step().is_empty(), "tutorial finished in the first ten minutes")
	truthy(int(m.s["level"]) >= 3, "reached level 3+ (got %d)" % int(m.s["level"]))
	return true

## One greedy decision. Returns false when there is nothing useful to do.
func _step() -> bool:
	for i in m.daily_goals(t).size():
		if m.claim_goal(i, t) == "": return true
	if m.tutorial_step().get("goal", "") is String and not m.tutorial_step().is_empty():
		m.tutorial_tap(); return true
	var ripe := range(m.s["plots"].size()).filter(func(i): return m.s["plots"][i]["crop"] != "" and m.plot_remaining(i, t) <= 0.0)
	if not ripe.is_empty():
		_go("field")
		for i in ripe: m.harvest(i, t)
		_act(); return true
	if m.building_has_ready("kitchen", t):
		_go("inn"); m.collect_building("kitchen", t); _act(); return true
	for g in range(m.inn()["guests"].size()):
		if m.has_items(m.inn()["guests"][g]["order"]):
			_go("inn"); m.serve_guest(g); _act(); return true
	var stew: Dictionary = GameData.recipes()["carrot_stew"]["inputs"]
	if m.s["buildings"]["kitchen"]["queue"].is_empty() and m.has_items(stew) and (m.tutorial_step().is_empty() or m.tutorial_step()["goal"]["stat"] == "cooked"):
		_go("inn"); m.queue_recipe("kitchen", "carrot_stew", t); _act(); return true
	var tut := m.tutorial_step()
	var empty := range(m.s["plots"].size()).filter(func(i): return m.s["plots"][i]["crop"] == "")
	var can_sell: bool = m.count("wheat") > 6 or not tut.is_empty() and tut["goal"]["stat"] == "sold" and m.count("wheat") > 0
	if can_sell and (tut.is_empty() or tut["goal"]["stat"] == "sold"):
		_go("stall"); m.sell("wheat", mini(m.count("wheat") - (0 if not tut.is_empty() else 4), 10), t); _act(); return true
	if not empty.is_empty() and int(m.s["coins"]) >= 1:
		_go("field")
		var carrots_growing: bool = m.s["plots"].any(func(p): return p["crop"] == "carrot")
		for k in empty.size():
			var crop := "carrot" if k < 2 and not carrots_growing and m.count("carrot") < 2 and int(m.s["coins"]) >= 6 else "wheat"
			m.plant(empty[k], crop, t)
		_act(); return true
	return false
