extends RefCounted
## Base class for test files: `extends "res://tests/test_case.gd"`, then write func test_*().

var _failure := ""


func fail(msg: String) -> void:
	if _failure.is_empty():
		_failure = msg


func check(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func check_eq(actual, expected, what: String) -> void:
	if actual != expected:
		fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])


func check_near(actual: float, expected: float, eps: float, what: String) -> void:
	if absf(actual - expected) > eps:
		fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])


## Runs after every test (override to free what the test created).
func after_each() -> void:
	pass


func take_failure() -> String:
	var f := _failure
	_failure = ""
	return f
