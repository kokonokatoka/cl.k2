class_name BotBrain
extends RefCounted
## 簡単な自動操縦。見えている敵・プレイヤーに近づいて撃つ。
## 見た目の確認（--autoplay）と、オンラインの結合テストの「ボット」に使う。人間の代わりに PlayerInput を作るだけ。

var session: GameSession
## 撃ちはじめる距離[m]と、保ちたい距離
var fire_range: float = 14.0
var preferred_distance: float = 6.5

var _rng := DetRng.new(1)
var _wander_dir: Vector2 = Vector2.ZERO
var _wander_time: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_time: float = 0.0
var _aim_yaw: float = 0.0


func _init(game_session: GameSession = null, seed_value: int = 1) -> void:
	session = game_session
	_rng = DetRng.new(seed_value)


func sample(seq: int) -> PlayerInput:
	var input := PlayerInput.new()
	input.seq = seq
	var player := session.local_player
	if player == null or not player.alive:
		input.aim_yaw = _aim_yaw
		return input.quantize()

	var dt := SimConfig.DT
	# 詰まったら向きを変える
	if player.pos.distance_to(_last_position) < 0.01:
		_stuck_time += dt
	else:
		_stuck_time = 0.0
	_last_position = player.pos
	_strafe_time -= dt
	if _strafe_time <= 0.0:
		_strafe_time = _rng.range_float(1.0, 2.5)
		_strafe_sign = -_strafe_sign

	var frame := session.sample(1.0)
	var target: RenderFrame.Entity = _nearest_target(frame, player.pos)
	var move := Vector2.ZERO
	if target != null:
		var to := Vector2(target.pos.x - player.pos.x, target.pos.z - player.pos.z)
		var distance := to.length()
		var direction := to / maxf(distance, 0.001)
		_aim_yaw = SimMath.yaw_of(Vector3(direction.x, 0.0, direction.y))
		if distance > preferred_distance + 1.5:
			move = direction
		elif distance < preferred_distance - 2.0:
			move = -direction
		move += Vector2(-direction.y, direction.x) * _strafe_sign * 0.8
		if distance <= fire_range and player.stats.can_fire():
			input.buttons |= PlayerInput.BTN_FIRE
		if distance < 3.5 and player.energy > player.stats.dash_cost:
			input.buttons |= PlayerInput.BTN_DASH
	else:
		_wander_time -= dt
		if _wander_time <= 0.0 or _stuck_time > 0.3:
			_wander_time = _rng.range_float(1.5, 3.5)
			# 中央へ向かいがちにして、壁際に張り付かないようにする
			var toward_center := Vector2(-player.pos.x, -player.pos.z).normalized()
			_wander_dir = (toward_center * 0.6 + Vector2.from_angle(_rng.range_float(0.0, TAU)) * 0.9).normalized()
		move = _wander_dir
		if move.length() > 0.01:
			_aim_yaw = SimMath.yaw_of(Vector3(move.x, 0.0, move.y))
	if _stuck_time > 0.4 and player.stats.jump_velocity > 0.0:
		input.buttons |= PlayerInput.BTN_JUMP
	input.move = move.limit_length(1.0)
	input.aim_yaw = _aim_yaw
	return input.quantize()


func _nearest_target(frame: RenderFrame, from: Vector3) -> RenderFrame.Entity:
	var best: RenderFrame.Entity = null
	var best_distance := INF
	for enemy in frame.enemies:
		var d := enemy.pos.distance_to(from)
		if d < best_distance:
			best_distance = d
			best = enemy
	for other in frame.players:
		if other.is_local or not other.alive:
			continue
		var d := other.pos.distance_to(from)
		if d < best_distance:
			best_distance = d
			best = other
	return best if best_distance < 30.0 else null
