extends SceneTree
## Headless test runner. Run through tools/run_tests.ps1 (adds --import and a hard timeout).
## 1. Compile sweep: every .gd under res://src and res://tests must load.
## 2. Runs every func test_*() in res://tests/**/test_*.gd. A test fails by returning a non-empty String
##    or by calling fail(); a file that does not compile is reported and skipped, never fatal.

const SWEEP_ROOTS = ["res://src", "res://tests"]
const TEST_ROOT = "res://tests"

var _failures: Array = []


func _init() -> void:
	var compile_errors := _compile_sweep()
	var counts := _run_tests()
	print("")
	print("compile errors: %d" % compile_errors)
	print("tests: %d passed, %d failed" % [counts[0], counts[1]])
	for f in _failures:
		print("  FAIL %s" % f)
	quit(0 if compile_errors == 0 and counts[1] == 0 else 1)


func _collect(dir_path: String, out: Array, prefix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out, prefix)
	for file in dir.get_files():
		if file.ends_with(".gd") and file.begins_with(prefix):
			out.append(dir_path.path_join(file))


func _compile_sweep() -> int:
	var files: Array = []
	for root in SWEEP_ROOTS:
		_collect(root, files, "")
	var errors := 0
	for path in files:
		var script = load(path)
		if script == null or not script.can_instantiate():
			errors += 1
			print("COMPILE ERROR %s" % path)
	print("compile sweep: %d files" % files.size())
	return errors


func _run_tests() -> Array:
	var files: Array = []
	_collect(TEST_ROOT, files, "test_")
	var passed := 0
	var failed := 0
	for path in files:
		var script = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			_failures.append("%s (does not compile)" % path)
			continue
		var suite = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var result = suite.call(name)
			if suite.has_method("after_each"):
				suite.call("after_each")
			var err := ""
			if result is String:
				err = result
			if err.is_empty() and suite.has_method("take_failure"):
				err = suite.take_failure()
			if err.is_empty():
				passed += 1
			else:
				failed += 1
				_failures.append("%s:%s  %s" % [path.get_file(), name, err])
		if suite is Node:
			suite.free()
	return [passed, failed]
