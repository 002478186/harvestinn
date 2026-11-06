## Rewarded-ads facade. MOCK implementation; off unless data/monetization.json says otherwise.
## TODO(AdMob): replace _show_mock() with the AdMob plugin (poing-studios/godot-admob-plugin):
##   - init with your AdMob app id (Android: export preset, iOS: Info.plist GADApplicationIdentifier)
##   - load a RewardedAd per placement, call show(), resolve true only on `user_earned_reward`
##   - add the ATT prompt (iOS) and UMP consent form (EU) before the first ad request
extends Node

signal finished(placement: String, rewarded: bool)

var enabled := false
var _shown_today := {}

func _ready() -> void:
	enabled = bool(GameData.load_json("res://data/monetization.json").get("ads_enabled", false))

func can_show(placement: String) -> bool:
	if not enabled or Game.model.s["flags"].get("remove_ads", false) and placement == "interstitial": return false
	var cfg: Dictionary = GameData.load_json("res://data/monetization.json")["rewarded"].get(placement, {})
	var key := "%s:%d" % [placement, GameModel.local_day(Game.now())]
	return not cfg.is_empty() and int(_shown_today.get(key, 0)) < int(cfg["daily_limit"])

## Shows a rewarded ad; returns true only if the player earned the reward.
func show_rewarded(placement: String) -> bool:
	if not can_show(placement): return false
	var key := "%s:%d" % [placement, GameModel.local_day(Game.now())]
	_shown_today[key] = int(_shown_today.get(key, 0)) + 1
	var ok := await _show_mock()
	finished.emit(placement, ok)
	return ok

func _show_mock() -> bool:
	await get_tree().create_timer(1.0).timeout   # pretend an ad played
	return true
