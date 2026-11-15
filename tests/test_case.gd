class_name FcTestCase
extends RefCounted
## Base class for all tests. A test file extends this and defines methods whose
## names start with "test_". The runner (tests/run_tests.gd) finds and runs them.

var failures: Array[String] = []


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		failures.append(message)


func assert_eq(actual, expected, message: String = "") -> void:
	if actual != expected:
		failures.append("%s expected <%s> but got <%s>" % [message, str(expected), str(actual)])


func assert_between(actual: float, low: float, high: float, message: String = "") -> void:
	if actual < low or actual > high:
		failures.append("%s expected %s in [%s, %s]" % [message, str(actual), str(low), str(high)])


## Runs before every test method. Override to set up fresh state.
func before_each() -> void:
	pass


## Runs after every test method (even failed ones). Override to clean up files.
func after_each() -> void:
	pass
