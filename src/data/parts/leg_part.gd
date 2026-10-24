class_name LegPart
extends RobotPart
## 足パーツ: 移動速度・ジャンプ力・ダッシュ・胴体の高さを決める。

@export var move_speed: float = 5.0
@export var acceleration: float = 40.0
## 0 ならジャンプ不可
@export var jump_velocity: float = 8.0
## 足の長さ。胴体（Model）をこの高さに持ち上げる
@export var ride_height: float = 0.5
## 0 ならダッシュ不可
@export var dash_speed: float = 14.0
@export var dash_time: float = 0.18
@export var dash_cost: float = 25.0
@export var dash_cooldown: float = 0.45


func get_slot() -> Slot:
	return Slot.LEGS


func apply(stats: RobotStats) -> void:
	stats.move_speed = move_speed
	stats.acceleration = acceleration
	stats.jump_velocity = jump_velocity
	stats.ride_height = ride_height
	stats.dash_speed = dash_speed
	stats.dash_time = dash_time
	stats.dash_cost = dash_cost
	stats.dash_cooldown = dash_cooldown
