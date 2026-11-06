extends TestCase

func test_decide() -> bool:
	eq(CloudSync.decide(0, 0, true), "push", "first upload")
	eq(CloudSync.decide(3, 3, false), "none", "in sync")
	eq(CloudSync.decide(3, 3, true), "push", "local changes")
	eq(CloudSync.decide(3, 5, false), "pull", "other device ahead, no local changes")
	eq(CloudSync.decide(3, 5, true), "conflict", "both changed")
	return true

func test_net_offline_without_config() -> bool:
	var net: Node = tree.root.get_node("Net")
	truthy(not net.online, "offline in tests")
	var r: Dictionary = await net.call_rpc("load_game")
	eq(r["code"], 0, "rpc refuses when offline")
	return true
