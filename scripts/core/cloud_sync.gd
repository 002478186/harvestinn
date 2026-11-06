## Pure decision rule for cloud saves (tested; used by the Net autoload).
## base_rev = server revision this device last synced; dirty = local changes since then.
class_name CloudSync
extends RefCounted

static func decide(base_rev: int, server_rev: int, dirty: bool) -> String:
	if server_rev == 0: return "push"                       # nothing in the cloud yet
	if server_rev == base_rev: return "push" if dirty else "none"
	if server_rev > base_rev and not dirty: return "pull"   # another device moved ahead
	return "conflict"                                       # both changed: ask the player

## Short summary shown on the "which save do you keep?" card.
static func summary(s: Dictionary) -> String:
	return "Level %d · %d coins · %d gems" % [int(s.get("level", 1)), int(s.get("coins", 0)), int(s.get("gems", 0))]
