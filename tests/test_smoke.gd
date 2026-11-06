extends TestCase

func test_data_files_load() -> bool:
	eq(GameData.items().has("wheat"), true, "items has wheat")
	eq(GameData.crops().size() >= 11, true, "11+ crops")
	return true
