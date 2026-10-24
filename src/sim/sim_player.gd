class_name SimPlayer
extends RefCounted
## シミュレーション上のプレイヤー。ノードではなく純粋なデータ。

var id: int = 0
var player_name: String = "Player"
var color_hex: String = "e8913a"
var team: int = 0

var loadout: Loadout = Loadout.new()
var stats: RobotStats = RobotStats.new()
## 所持しているパーツ（換装の候補）。StringName -> true
var inventory: Dictionary = {}

# --- クライアント予測の対象（PlayerSim.step が読み書きする） ---
var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var on_floor: bool = true
var energy: float = 0.0
var fire_cd: float = 0.0
var dash_time: float = 0.0
var dash_cd: float = 0.0
var dash_dir: Vector3 = Vector3.ZERO
var last_buttons: int = 0
var invuln: float = 0.0

# --- サーバーが決める状態 ---
var health: float = 0.0
var alive: bool = true
var respawn_timer: float = 0.0
var kills: int = 0
var deaths: int = 0
var score: int = 0
## 最後に処理した入力の番号（確認応答）
var last_seq: int = 0

# --- 描画の補間用（直前のティックの値） ---
var prev_pos: Vector3 = Vector3.ZERO
var prev_yaw: float = 0.0


func _init() -> void:
	recompute_stats()
	health = stats.max_health
	energy = stats.max_energy


## ロードアウトを変えて性能値を作り直す。体力・エネルギーは割合を保つ
func set_loadout(new_loadout: Loadout) -> void:
	var health_ratio := health / maxf(stats.max_health, 1.0)
	var energy_ratio := energy / maxf(stats.max_energy, 1.0)
	loadout = new_loadout
	recompute_stats()
	health = clampf(stats.max_health * health_ratio, 1.0 if alive else 0.0, stats.max_health)
	energy = clampf(stats.max_energy * energy_ratio, 0.0, stats.max_energy)


func recompute_stats() -> void:
	stats = loadout.build_stats()


func body_height() -> float:
	return SimConfig.PLAYER_HEIGHT + stats.ride_height


func muzzle_position() -> Vector3:
	return pos + Vector3(0.0, stats.ride_height + SimConfig.MUZZLE_HEIGHT, 0.0) + SimMath.forward(yaw) * SimConfig.MUZZLE_FORWARD


## 復活・出現
func respawn(at: Vector3, protection: float) -> void:
	pos = at
	prev_pos = at
	vel = Vector3.ZERO
	on_floor = true
	alive = true
	respawn_timer = 0.0
	health = stats.max_health
	energy = stats.max_energy
	fire_cd = 0.0
	dash_time = 0.0
	dash_cd = 0.0
	invuln = protection


## 予測の対象になっている状態だけをコピーする（サーバーの確定状態にそろえる）
func copy_predicted_state_from(other: SimPlayer) -> void:
	pos = other.pos
	vel = other.vel
	yaw = other.yaw
	on_floor = other.on_floor
	energy = other.energy
	fire_cd = other.fire_cd
	dash_time = other.dash_time
	dash_cd = other.dash_cd
	dash_dir = other.dash_dir
	last_buttons = other.last_buttons
	invuln = other.invuln
