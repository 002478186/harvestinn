## Client-side mirror of the server's trade rules (backend/supabase/migrations/*trading.sql).
## Used for instant UI feedback only — the server re-checks everything.
class_name TradeRules
extends RefCounted

static func min_price(item: String) -> int:
	return maxi(1, int(floor(GameData.item_price(item) * float(GameData.economy()["trade"]["min_mult"]))))

static func max_price(item: String) -> int:
	return int(ceil(GameData.item_price(item) * float(GameData.economy()["trade"]["max_mult"])))

static func listing_error(item: String, qty: int, price_each: int, active_listings: int) -> String:
	if not GameData.items().has(item): return "unknown_item"
	if qty < 1 or qty > 999: return "bad_quantity"
	if price_each < min_price(item) or price_each > max_price(item): return "price_out_of_range"
	if active_listings >= int(GameData.economy()["trade"]["listing_slots"]): return "listing_slots_full"
	return ""

static func fee(total: int) -> int:
	return ceili(total * float(GameData.economy()["trade"]["listing_fee_pct"]))

## Random v4 UUID used as an idempotency key for device<->server moves.
static func uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
