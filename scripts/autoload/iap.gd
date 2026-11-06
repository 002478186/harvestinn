## In-app purchase facade. MOCK implementation; off unless data/monetization.json says otherwise.
## TODO(store billing):
##   - Android: Godot Google Play Billing plugin (godot-sdk-integrations/godot-google-play-billing),
##     query SKUs = product ids below, purchase(), then acknowledge/consume.
##   - iOS: Godot StoreKit plugin (godot-ios-plugins / StoreKit 2), product ids = same.
##   - Verify receipts server-side before granting (Supabase Edge Function + store APIs) to stop fraud.
extends Node

signal purchased(product_id: String)

var enabled := false

func _ready() -> void:
	enabled = bool(GameData.load_json("res://data/monetization.json").get("iap_enabled", false))

func products() -> Dictionary:
	return GameData.load_json("res://data/monetization.json")["products"]

func owned(id: String) -> bool:
	return id in Game.model.s["flags"].get("purchases", [])

## Returns "" on success or an error code. Rewards are granted by GameModel.grant_purchase().
func purchase(id: String) -> String:
	if not enabled: return "store_off"
	var p: Dictionary = products().get(id, {})
	if p.is_empty(): return "unknown"
	if p.get("once", false) and owned(id): return "owned"
	await get_tree().create_timer(0.5).timeout   # mock store dialog
	Game.model.grant_purchase(id, p)
	purchased.emit(id)
	return ""

## TODO(store billing): query the store for owned non-consumables (remove_ads, starter_pack).
func restore() -> void:
	pass
