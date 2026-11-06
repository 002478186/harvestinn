## Player-name moderation: blocks offensive words, including l33t-speak and spacing tricks.
## The same rule runs on the server (backend/supabase/migrations) because the client can't be trusted.
class_name NameFilter
extends RefCounted

## Kept short and generic on purpose; extend data/blocked_words.json for production lists.
static func words() -> Array:
	return GameData.load_json("res://data/blocked_words.json").get("words", [])

static func normalize(s: String) -> String:
	var t := s.to_lower()
	for pair in [["0", "o"], ["1", "i"], ["3", "e"], ["4", "a"], ["5", "s"], ["7", "t"], ["@", "a"], ["$", "s"], ["!", "i"]]:
		t = t.replace(pair[0], pair[1])
	var out := ""
	for ch in t:
		if ch >= "a" and ch <= "z":
			out += ch
	return out

static func is_clean(s: String) -> bool:
	var n := normalize(s)
	for w in words():
		if n.contains(str(w)):
			return false
	return true
