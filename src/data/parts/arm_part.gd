class_name ArmPart
extends RobotPart
## 腕パーツ（武器）: 弾の種類・威力・連射を決める。長押しで連射する。

## 見た目・効果音の識別子（"blaster" など）
@export var weapon_kind: StringName = &"blaster"
@export var damage: float = 12.0
## 発射間隔[秒]
@export var fire_interval: float = 0.28
@export var projectile_speed: float = 26.0
## 弾の寿命[秒]。速度との積が射程
@export var projectile_life: float = 0.9
## 1回の発射で出る弾の数（散弾）
@export_range(1, 12) var pellets: int = 1
## 弾のばらつき（片側の度数）
@export_range(0.0, 45.0, 0.1) var spread_degrees: float = 1.5
## 1発あたりのエネルギー消費
@export var shot_cost: float = 4.0
## 貫通する敵の数
@export_range(0, 8) var pierce: int = 0


func get_slot() -> Slot:
	return Slot.ARMS


func apply(stats: RobotStats) -> void:
	stats.weapon_kind = weapon_kind
	stats.weapon_damage = damage
	stats.fire_interval = fire_interval
	stats.projectile_speed = projectile_speed
	stats.projectile_life = projectile_life
	stats.pellets = pellets
	stats.spread = deg_to_rad(spread_degrees)
	stats.shot_cost = shot_cost
	stats.pierce = pierce
