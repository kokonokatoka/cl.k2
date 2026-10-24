class_name StatBar
extends Control
## AAAタクティカル・スラント（傾斜）セグメントゲージ。
## アーマード・コアやサイバーパンク調のミリタリーHUD仕様。
## セグメント分割、ゴースト残像、ネオングロー、低残量時パルス警告を搭載。

@export var fill_color: Color = Color(0.15, 0.85, 1.0)
@export var label_text: String = "STATUS"
@export var sub_label: String = "SYS.OK"
@export var is_health: bool = false

var _value: float = 100.0
var _max_value: float = 100.0
var _ghost: float = 1.0
var _pulse_time: float = 0.0

const SLANT_OFFSET := 12.0 # 傾斜角オフセット(px)
const SEGMENTS := 20       # セグメント目盛り分割数

func _init() -> void:
	custom_minimum_size = Vector2(320, 26)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(value: float, max_value: float) -> void:
	_value = maxf(value, 0.0)
	_max_value = maxf(max_value, 0.001)
	queue_redraw()


func _process(delta: float) -> void:
	var target := clampf(_value / _max_value, 0.0, 1.0)
	# ゴーストバーの追従: 回復時は即座、減少時は指数減衰で引く
	if target >= _ghost:
		_ghost = target
	else:
		_ghost = lerpf(_ghost, target, 1.0 - exp(-3.8 * delta))
	
	_pulse_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var ratio := clampf(_value / _max_value, 0.0, 1.0)
	var is_critical := is_health and ratio <= 0.25
	
	# パルス係数（瀕死時）
	var pulse := 1.0
	if is_critical:
		pulse = 0.65 + 0.35 * sin(_pulse_time * 9.0)

	# 1. 外枠バックプレート（半透明スモークブラックの斜角プレート）
	var bg_poly := PackedVector2Array([
		Vector2(SLANT_OFFSET, 0),
		Vector2(w, 0),
		Vector2(w - SLANT_OFFSET, h),
		Vector2(0, h)
	])
	draw_colored_polygon(bg_poly, Color(0.02, 0.035, 0.06, 0.85))
	
	# 外枠境界線（ハイテクミリタリーライン）
	var border_color := Color(0.18, 0.3, 0.45, 0.8)
	if is_critical:
		border_color = Color(1.0, 0.25, 0.3, pulse)
	draw_polyline(bg_poly, border_color, 1.2)

	# 2. ゲージ内寸
	var pad := 3.0
	var inner_w := w - (pad * 2.0)
	var inner_h := h - (pad * 2.0)
	
	# 3. ゴーストバー（被弾ダメージ残像）
	if _ghost > ratio:
		var ghost_w := inner_w * _ghost
		var ghost_poly := PackedVector2Array([
			Vector2(pad + SLANT_OFFSET, pad),
			Vector2(pad + ghost_w + SLANT_OFFSET * (1.0 - pad / h), pad),
			Vector2(pad + ghost_w, pad + inner_h),
			Vector2(pad, pad + inner_h)
		])
		draw_colored_polygon(ghost_poly, Color(1.0, 0.9, 0.7, 0.35))

	# 4. メインゲージ（グラデーション風塗り）
	if ratio > 0.001:
		var fill_w := inner_w * ratio
		var main_color := fill_color
		if is_critical:
			main_color = Color(1.0, 0.2, 0.3, pulse)
		
		var main_poly := PackedVector2Array([
			Vector2(pad + SLANT_OFFSET, pad),
			Vector2(pad + fill_w + SLANT_OFFSET * (1.0 - pad / h), pad),
			Vector2(pad + fill_w, pad + inner_h),
			Vector2(pad, pad + inner_h)
		])
		draw_colored_polygon(main_poly, main_color)
		
		# トップエッジのネオンハイライトライン
		draw_line(
			Vector2(pad + SLANT_OFFSET, pad + 1.0),
			Vector2(pad + fill_w + SLANT_OFFSET * (1.0 - pad / h), pad + 1.0),
			Color(1.0, 1.0, 1.0, 0.75 * pulse),
			1.5
		)

	# 5. セグメント目盛りスリット（縦ラインでゲージを精密機械のように分割）
	var seg_color := Color(0.01, 0.02, 0.04, 0.75)
	for i in range(1, SEGMENTS):
		var seg_x := pad + (inner_w / float(SEGMENTS)) * float(i)
		var p1 := Vector2(seg_x + SLANT_OFFSET * (1.0 - pad / h), pad)
		var p2 := Vector2(seg_x, pad + inner_h)
		draw_line(p1, p2, seg_color, 1.5)

	# 6. コーナーアクセントブラケット（左端・右端の装飾ピン）
	draw_line(Vector2(0, h), Vector2(6, h), border_color, 2.0)
	draw_line(Vector2(w - 6, 0), Vector2(w, 0), border_color, 2.0)

	# 7. タイポグラフィ（ミリタリーフォント配置）
	var font := get_theme_default_font()
	var font_size := 11
	
	# 左側: システムコード // ラベル名
	var left_label := "%s" % [label_text]
	var text_color := Color(1.0, 1.0, 1.0, 0.95)
	if is_critical:
		text_color = Color(1.0, 0.8, 0.8, pulse)
		left_label = "! CRITICAL !  " + left_label

	draw_string(font, Vector2(SLANT_OFFSET + 8, h * 0.5 + font_size * 0.35), left_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# 右側: 3桁デジタル値 / 最大値
	var val_str := "%03d" % [ceili(_value)]
	var max_str := " / %d" % [roundi(_max_value)]
	var full_text := val_str + max_str
	draw_string(font, Vector2(w - SLANT_OFFSET - 80, h * 0.5 + font_size * 0.35), full_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, text_color)
