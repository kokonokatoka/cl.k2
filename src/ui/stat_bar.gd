class_name StatBar
extends Control
## 体力・エネルギーなどの横バー。減ったぶんは遅れて縮む「残像」が付く。

var fill_color: Color = UiTheme.HEALTH
var label_text: String = ""

var _value: float = 1.0
var _max_value: float = 1.0
var _ghost: float = 1.0


func _init() -> void:
	custom_minimum_size = Vector2(240, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(value: float, max_value: float) -> void:
	_value = value
	_max_value = maxf(max_value, 0.001)
	queue_redraw()


func _process(delta: float) -> void:
	var target := _value / _max_value
	# 増えるときは即座に、減るときはゆっくり追従
	_ghost = target if target >= _ghost else lerpf(_ghost, target, 1.0 - exp(-3.5 * delta))
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.03, 0.04, 0.06, 0.85))
	var ratio := clampf(_value / _max_value, 0.0, 1.0)
	var inner := rect.grow(-2.0)
	if _ghost > ratio:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * _ghost, inner.size.y)), Color(1, 1, 1, 0.35))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * ratio, inner.size.y)), fill_color)
	draw_rect(rect, Color(0.25, 0.28, 0.35), false, 1.0)
	var font := get_theme_default_font()
	var font_size := 13
	var text := "%s  %d / %d" % [label_text, ceili(_value), roundi(_max_value)]
	draw_string(font, Vector2(8, size.y * 0.5 + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))
