class_name VisionOverlay
extends CanvasLayer
## 目パーツの視界に応じて画面を暗くする。ロボットの周りだけ見える。
## 視界はワールドの半径[m]で決まり、カメラで投影して画面上の楕円にする（シェーダーは楕円で暗くする）。

## 視界が切り替わるときの変化の速さ（大きいほど速い）
const TRANSITION_RATE := 7.0
const EYE_HEIGHT := 0.9

var _darkness: ColorRect
var _no_signal: Label
var _hit_flash: ColorRect
var _material: ShaderMaterial

var _range: float = 7.0
var _tint: Color = Color(0, 0, 0, 0)
var _flash: float = 0.0


func _ready() -> void:
	layer = 5
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/vision.gdshader")

	_darkness = ColorRect.new()
	_darkness.material = _material
	_darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darkness.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_darkness)

	_hit_flash = ColorRect.new()
	_hit_flash.color = Color(1, 0.1, 0.1, 0.0)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_hit_flash)

	_no_signal = Label.new()
	_no_signal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_no_signal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_signal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_no_signal.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2))
	_no_signal.add_theme_font_size_override("font_size", 26)
	_no_signal.visible = false
	add_child(_no_signal)
	_retranslate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _no_signal != null:
		_retranslate()


## 毎フレーム。world_position: 視界の中心（ロボットの位置）、target_range: 視界の半径[m]
func update_vision(camera: Camera3D, world_position: Vector3, target_range: float, tint: Color, delta: float) -> void:
	if camera == null:
		return
	_range = lerpf(_range, target_range, 1.0 - exp(-TRANSITION_RATE * delta))
	if absf(_range - target_range) < 0.01:
		_range = target_range
	_tint = _tint.lerp(tint, 1.0 - exp(-TRANSITION_RATE * delta))

	var size := get_viewport().get_visible_rect().size
	var eye := world_position + Vector3.UP * EYE_HEIGHT
	var center := camera.unproject_position(eye)
	# 地面の円の「横の端」と「奥の端」を投影して、画面上の楕円の半径を求める
	var right_edge := camera.unproject_position(eye + Vector3(_range, 0.0, 0.0))
	var far_edge := camera.unproject_position(eye + Vector3(0.0, 0.0, _range))
	var radii := Vector2(absf(right_edge.x - center.x), absf(far_edge.y - center.y)) / size.y
	_material.set_shader_parameter("center", center / size)
	_material.set_shader_parameter("aspect", size.x / size.y)
	_material.set_shader_parameter("radii", radii if _range > 0.05 else Vector2(0.0001, 0.0001))
	_material.set_shader_parameter("tint", _tint)
	_no_signal.visible = target_range <= 0.05

	_flash = maxf(0.0, _flash - delta * 2.5)
	_hit_flash.color.a = _flash * 0.35


## 被弾の赤い閃光
func flash_hit(strength: float = 1.0) -> void:
	_flash = minf(1.0, _flash + strength)


func _retranslate() -> void:
	_no_signal.text = tr("hud.no_signal")
