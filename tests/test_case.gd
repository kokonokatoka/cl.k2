class_name TestCase
extends RefCounted
## テストの基底クラス。`test_` で始まるメソッドが1つずつ、新しいインスタンスで実行される。
## テストメソッドは await を使ってよい（結合テスト用）。

var failures: PackedStringArray = PackedStringArray()
var assertion_count: int = 0
## ランナーが渡す。await を使うテスト（結合テスト）で時間を待つのに使う
var tree: SceneTree


func before_each() -> void:
	pass


func after_each() -> void:
	pass


## seconds だけ待つ（呼び出しは wait wait(1.0)）
func wait(seconds: float) -> void:
	await tree.create_timer(seconds).timeout


func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "") -> void:
	assertion_count += 1
	if not condition:
		fail("expected true. %s" % message)


func assert_false(condition: bool, message: String = "") -> void:
	assertion_count += 1
	if condition:
		fail("expected false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertion_count += 1
	if typeof(actual) != typeof(expected) and not (_is_number(actual) and _is_number(expected)):
		fail("type mismatch: %s (%s) vs %s (%s). %s" % [actual, type_string(typeof(actual)), expected, type_string(typeof(expected)), message])
	elif actual != expected:
		fail("expected %s, got %s. %s" % [expected, actual, message])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertion_count += 1
	if actual == unexpected:
		fail("expected a value other than %s. %s" % [unexpected, message])


func assert_near(actual: float, expected: float, epsilon: float = 1e-4, message: String = "") -> void:
	assertion_count += 1
	if absf(actual - expected) > epsilon or is_nan(actual):
		fail("expected %s ± %s, got %s. %s" % [expected, epsilon, actual, message])


func assert_vec3_near(actual: Vector3, expected: Vector3, epsilon: float = 1e-3, message: String = "") -> void:
	assertion_count += 1
	if actual.distance_to(expected) > epsilon:
		fail("expected %s ± %s, got %s. %s" % [expected, epsilon, actual, message])


func assert_not_null(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value == null:
		fail("expected a non-null value. %s" % message)


func assert_null(value: Variant, message: String = "") -> void:
	assertion_count += 1
	if value != null:
		fail("expected null, got %s. %s" % [value, message])


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
