class_name InputSampler
extends Node
## キーボード/マウス/ゲームパッドから PlayerInput を作る。
## 狙う向きはマウスなら「カーソルの下の地面」、パッドなら右スティック。どちらも無ければ前回の向きを保つ。

const STICK_AIM_DEADZONE := 0.35
## カーソルが自分の真上にあるときは向きを更新しない距離[m]
const MIN_AIM_DISTANCE := 0.25

## 入力を受け付けるか。チャット入力中・ポーズ中・死亡中の UI などで false にする
var enabled: bool = true
## () -> SimPlayer。狙う高さと基準位置に使う
var local_player_getter: Callable

var using_gamepad: bool = false

var _last_yaw: float = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) > 0.3:
			using_gamepad = true
	elif event is InputEventJoypadButton:
		using_gamepad = true
	elif event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		using_gamepad = false


func sample(seq: int) -> PlayerInput:
	var input := PlayerInput.new()
	input.seq = seq
	var player: SimPlayer = local_player_getter.call() if local_player_getter.is_valid() else null
	if player != null:
		_last_yaw = player.yaw
	if not enabled:
		input.aim_yaw = _last_yaw
		return input.quantize()

	input.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.is_action_pressed("jump"):
		input.buttons |= PlayerInput.BTN_JUMP
	if Input.is_action_pressed("dash"):
		input.buttons |= PlayerInput.BTN_DASH
	if Input.is_action_pressed("fire"):
		input.buttons |= PlayerInput.BTN_FIRE
	input.aim_yaw = _compute_aim(player)
	_last_yaw = input.aim_yaw
	return input.quantize()


func _compute_aim(player: SimPlayer) -> float:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > STICK_AIM_DEADZONE:
		return SimMath.yaw_of(Vector3(stick.x, 0.0, stick.y))
	if using_gamepad or player == null:
		return _last_yaw
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return _last_yaw
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.001:
		return _last_yaw
	# 銃口の高さの水平面とカーソルの視線が交わる点を狙う
	var plane_y := player.pos.y + player.stats.ride_height + SimConfig.MUZZLE_HEIGHT
	var t := (plane_y - origin.y) / direction.y
	if t <= 0.0:
		return _last_yaw
	var hit := origin + direction * t
	var to_target := Vector3(hit.x - player.pos.x, 0.0, hit.z - player.pos.z)
	if to_target.length() < MIN_AIM_DISTANCE:
		return _last_yaw
	return SimMath.yaw_of(to_target)


## カーソルが指している地面の位置（カメラの先読み用）。取れなければ null
func aim_point_on_ground() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.001:
		return null
	var t := -origin.y / direction.y
	return origin + direction * t if t > 0.0 else null
