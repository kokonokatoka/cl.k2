class_name Reconciler
extends RefCounted
## クライアント予測の補正。
## 自分のロボットは入力を受けた瞬間に動かす（予測）。サーバーから「入力 N までを処理した結果」が届いたら、
## その状態に置き換えて、まだ確認されていない入力を再生し直す。ずれた分は見た目だけ滑らかに寄せる。

## これ以上ずれたら滑らかに寄せず、その場に移す[m]
const SNAP_DISTANCE := 3.0
## 見た目のずれが消える速さ
const SMOOTH_RATE := 12.0
## 確認待ちの入力の上限（サーバーが応答しないときに無限に溜めない）
const MAX_PENDING := 240

var player: SimPlayer
var geometry: WorldGeometry
var pending: Array[PlayerInput] = []
## 描画の位置 = player.pos + view_offset
var view_offset: Vector3 = Vector3.ZERO

var corrections: int = 0
var snaps: int = 0
var last_error: float = 0.0
var max_error: float = 0.0


func _init(local_player: SimPlayer = null, world_geometry: WorldGeometry = null) -> void:
	player = local_player
	geometry = world_geometry


## 予測の 1 ティック。入力を適用して、確認待ちに積む。戻り値は PlayerSim のイベントフラグ
func predict(input: PlayerInput) -> int:
	var flags := PlayerSim.step(player, input, geometry)
	pending.append(input)
	if pending.size() > MAX_PENDING:
		pending.pop_front()
	return flags


## サーバーの状態（authoritative）を受け取って補正する。auth は自分の状態、ack_seq は処理済みの入力番号
func apply_authoritative(auth: SimPlayer, ack_seq: int) -> void:
	while not pending.is_empty() and pending[0].seq <= ack_seq:
		pending.pop_front()

	var displayed_before := player.pos + view_offset
	player.copy_predicted_state_from(auth)
	player.health = auth.health
	player.alive = auth.alive
	player.respawn_timer = auth.respawn_timer
	# 確認されていない入力を、サーバーの状態の上で再生する
	for input in pending:
		PlayerSim.step(player, input, geometry)

	var error := displayed_before.distance_to(player.pos)
	last_error = error
	max_error = maxf(max_error, error)
	if error > SNAP_DISTANCE or not player.alive:
		view_offset = Vector3.ZERO
		player.prev_pos = player.pos
		snaps += 1
	else:
		if error > 0.001:
			corrections += 1
		view_offset = displayed_before - player.pos


## 毎フレーム。見た目のずれを減らす
func smooth(delta: float) -> void:
	view_offset = view_offset.lerp(Vector3.ZERO, 1.0 - exp(-SMOOTH_RATE * delta))
	if view_offset.length_squared() < 1e-6:
		view_offset = Vector3.ZERO


func displayed_position() -> Vector3:
	return player.pos + view_offset
