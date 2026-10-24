class_name TopDownCamera
extends Camera3D
## 斜め上から見下ろして追従するカメラ。向きは固定で位置だけ動く。
## マウス方向への先読みと、トラウマ式の画面揺れ（ヒット・発砲・爆発）を持つ。

@export var offset: Vector3 = Vector3(0.0, 9.0, 6.0)
@export var follow_rate: float = 9.0
## 画面揺れの最大の平行移動[m]と傾き[rad]
@export var shake_offset: float = 0.35
@export var shake_roll: float = 0.035

var _trauma: float = 0.0
var _time: float = 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	# 真下に近い向きから、offset の方向を見る
	rotation = Vector3(-atan2(offset.y, offset.z), 0.0, 0.0)
	_noise.seed = 7
	_noise.frequency = 1.0
	current = true


## 画面揺れを足す（0〜1。重なると加算されて上限1）。設定の「画面揺れ」倍率が掛かる
func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount * Settings.get_float("game/screen_shake"))


## target: 追う地面の位置。look: 先読みの目標（カーソルが指す地面の位置。無ければ null）
func follow(target: Vector3, look: Variant, delta: float) -> void:
	var focus := Vector3(target.x, 0.0, target.z)
	if look is Vector3:
		var lead: Vector3 = (look as Vector3 - focus)
		lead.y = 0.0
		focus += lead.limit_length(6.0) * 0.28 * Settings.get_float("game/camera_lookahead")
	var desired := focus + offset
	global_position = global_position.lerp(desired, 1.0 - exp(-follow_rate * delta))

	_time += delta
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var power := _trauma * _trauma
	h_offset = _noise.get_noise_2d(_time * 55.0, 0.0) * shake_offset * power
	v_offset = _noise.get_noise_2d(0.0, _time * 55.0) * shake_offset * power
	rotation.z = _noise.get_noise_2d(_time * 40.0, 100.0) * shake_roll * power


## 一気に目標の位置へ移す（開始時・リスポーン時）
func snap_to(target: Vector3) -> void:
	global_position = Vector3(target.x, 0.0, target.z) + offset
	_trauma = 0.0
