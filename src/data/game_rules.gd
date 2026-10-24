class_name GameRules
extends Resource
## 1試合分のルール。サーバーが決めて、接続時にクライアントへ送る。

## 倒されてから復活するまで[秒]
@export var respawn_delay: float = 3.0
## 復活直後の無敵時間[秒]
@export var spawn_protection: float = 2.0
## プレイヤー同士で撃ち合えるか
@export var pvp: bool = true
## 敵の目標数（1人のとき）。人数が増えると enemy_per_player ずつ増える
@export var enemy_base: int = 5
@export var enemy_per_player: int = 2
@export var enemy_max: int = 24
## 目標数に足りないときの補充間隔[秒]
@export var enemy_spawn_interval: float = 3.5
## 敵は最寄りのプレイヤーからこの距離より外に湧く
@export var enemy_spawn_min_distance: float = 14.0
## ドロップアイテムが消えるまで[秒]
@export var pickup_lifetime: float = 45.0
## 床に置いてある拾い物の数と再出現時間
@export var world_pickups: int = 6
@export var world_pickup_respawn: float = 25.0
## アリーナの半幅[m]（正方形）
@export var arena_half_size: float = 30.0
## 遮蔽物の数
@export var cover_count: int = 26
## ドロップ率の倍率
@export var drop_scale: float = 1.0


func to_dict() -> Dictionary:
	var d := {}
	for prop in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			d[prop["name"]] = get(prop["name"])
	return d


static func from_dict(d: Dictionary) -> GameRules:
	var rules := GameRules.new()
	for key in d:
		if key in rules:
			rules.set(key, d[key])
	return rules
