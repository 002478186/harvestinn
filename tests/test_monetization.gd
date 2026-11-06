extends TestCase

func test_off_by_default_and_game_never_needs_it() -> bool:
	var cfg: Dictionary = GameData.load_json("res://data/monetization.json")
	eq(cfg["ads_enabled"], false, "ads off")
	eq(cfg["iap_enabled"], false, "iap off")
	var ads: Node = tree.root.get_node("Ads")
	truthy(not ads.can_show("speedup"), "no ad offered")
	eq(await tree.root.get_node("IAP").purchase("gems_small"), "store_off", "store off")
	return true

func test_rewards_when_enabled() -> bool:
	var m := new_farm(0.0)
	m.plant(0, "carrot", 0.0)
	eq(m.ad_finish_plot(0, 0.0), "", "ad finishes timer")
	eq(m.harvest(0, 0.0), "", "harvest now")
	m.grant_purchase("starter_pack", GameData.load_json("res://data/monetization.json")["products"]["starter_pack"])
	eq(m.s["gems"], 110, "100 gems granted")
	eq(m.count("animal_feed"), 20, "feed granted")
	truthy("starter_pack" in m.s["flags"]["purchases"], "recorded")
	return true
