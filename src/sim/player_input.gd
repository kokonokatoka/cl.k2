class_name PlayerInput
extends RefCounted
## 1ティック分のプレイヤー入力。ネットワークでは 9 バイトに量子化して送る。
## 予測側（クライアント）も必ず quantize() 済みの値でシミュレートする。さもないとサーバーと結果がずれる。

const BTN_JUMP: int = 1
const BTN_DASH: int = 2
const BTN_FIRE: int = 4

const WIRE_SIZE: int = 9
const AXIS_SCALE: float = 127.0
const YAW_STEPS: float = 65536.0

## 入力の通し番号（クライアントが1ティックごとに増やす）。サーバーの確認応答と再生に使う
var seq: int = 0
## 移動入力。画面の上 = y が負（Input.get_vector と同じ）
var move: Vector2 = Vector2.ZERO
## 狙っている向き（yaw）。0 = -Z
var aim_yaw: float = 0.0
var buttons: int = 0


func is_down(button: int) -> bool:
	return buttons & button != 0


## ネットワークで運べる精度に丸める（自分自身を返す）
func quantize() -> PlayerInput:
	move = Vector2(_dequantize_axis(_quantize_axis(move.x)), _dequantize_axis(_quantize_axis(move.y)))
	aim_yaw = _dequantize_yaw(_quantize_yaw(aim_yaw))
	return self


func encode(buffer: StreamPeerBuffer) -> void:
	buffer.put_u32(seq)
	buffer.put_8(_quantize_axis(move.x))
	buffer.put_8(_quantize_axis(move.y))
	buffer.put_u16(_quantize_yaw(aim_yaw))
	buffer.put_u8(buttons & 0xFF)


static func decode(buffer: StreamPeerBuffer) -> PlayerInput:
	var input := PlayerInput.new()
	input.seq = buffer.get_u32()
	input.move = Vector2(float(buffer.get_8()) / AXIS_SCALE, float(buffer.get_8()) / AXIS_SCALE)
	input.aim_yaw = _dequantize_yaw(buffer.get_u16())
	input.buttons = buffer.get_u8()
	return input


func duplicate_input() -> PlayerInput:
	var copy := PlayerInput.new()
	copy.seq = seq
	copy.move = move
	copy.aim_yaw = aim_yaw
	copy.buttons = buttons
	return copy


static func _quantize_axis(value: float) -> int:
	return clampi(roundi(clampf(value, -1.0, 1.0) * AXIS_SCALE), -127, 127)


static func _dequantize_axis(quantized: int) -> float:
	return float(quantized) / AXIS_SCALE


static func _quantize_yaw(yaw: float) -> int:
	return roundi(wrapf(yaw, 0.0, TAU) / TAU * YAW_STEPS) & 0xFFFF


static func _dequantize_yaw(quantized: int) -> float:
	return float(quantized) / YAW_STEPS * TAU
