class_name TestCase
extends RefCounted

var failures: Array[String] = []

func setup() -> void:
	pass

func eq(actual, expected, label: String = "") -> bool:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		if is_equal_approx(float(actual), float(expected)):
			return true
	elif actual == expected:
		return true
	failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
	return false

func truthy(v, label: String = "") -> bool:
	if v:
		return true
	failures.append("%s: expected truthy, got %s" % [label, str(v)])
	return false
