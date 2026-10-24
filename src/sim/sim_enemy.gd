class_name SimEnemy
extends RefCounted
## シミュレーション上の敵。

enum State { IDLE, WANDER, CHASE, WINDUP, CHARGE, STUN }

var id: int = 0
var def: EnemyDef
var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var health: float = 0.0
var state: State = State.IDLE
var state_time: float = 0.0
var target_id: int = 0

var attack_cd: float = 0.0
var retarget_cd: float = 0.0
var charge_dir: Vector3 = Vector3.ZERO
var charge_hit: bool = false
var wander_target: Vector3 = Vector3.ZERO
var wander_cd: float = 0.0
var stuck_time: float = 0.0
var avoid_sign: float = 1.0
var strafe_sign: float = 1.0
var strafe_cd: float = 0.0

## 被弾の表示用（描画側が読む。シミュレーションの結果には影響しない）
var hurt_flash: float = 0.0

var prev_pos: Vector3 = Vector3.ZERO
var prev_yaw: float = 0.0


func set_state(new_state: State) -> void:
	if state != new_state:
		state = new_state
		state_time = 0.0


func health_fraction() -> float:
	return clampf(health / def.max_health, 0.0, 1.0)
