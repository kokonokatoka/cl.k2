class_name EnemyDef
extends Resource
## 敵の種類。挙動（Behavior）とパラメーターだけで、新しい敵をデータとして増やせる。

enum Behavior {
	CHASER,   ## 追いかけて体当たり
	SHOOTER,  ## 距離を保って撃つ
	CHARGER,  ## 溜めてから突進
}

@export var id: StringName = &""
@export var display_name: String = "Drone"
@export var behavior: Behavior = Behavior.CHASER
@export var max_health: float = 30.0
@export var move_speed: float = 4.0
@export var radius: float = 0.45
@export var height: float = 1.1
## この距離内のプレイヤーに気づく
@export var aggro_range: float = 14.0
@export var contact_damage: float = 10.0
@export var contact_interval: float = 0.8

@export_group("Shooter")
@export var preferred_distance: float = 8.0
@export var fire_interval: float = 1.4
@export var projectile_damage: float = 8.0
@export var projectile_speed: float = 15.0

@export_group("Charger")
@export var charge_windup: float = 0.7
@export var charge_speed: float = 14.0
@export var charge_time: float = 0.6
@export var charge_cooldown: float = 1.5

@export_group("Spawn")
## 湧きやすさ（重み）
@export var spawn_weight: float = 1.0
## 試合開始からこの秒数が経つまでは湧かない
@export var min_time: float = 0.0

@export_group("Reward")
@export var score: int = 10
## パーツを落とす確率（GameRules.drop_scale が掛かる）
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.25
## 大きいほどレアが出やすい
@export_range(0, 6) var rarity_bias: int = 0

@export_group("Look")
@export var color: Color = Color(0.85, 0.3, 0.25)
@export var scale: float = 1.0


func get_title() -> String:
	var key := "enemy.%s.name" % id
	var translated := String(TranslationServer.translate(key))
	return display_name if translated == key else translated


func signature() -> String:
	return "%s|%d|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [
		id, behavior, max_health, move_speed, radius, height, contact_damage,
		fire_interval, projectile_damage, projectile_speed, charge_speed,
	]
