class_name RenderFrame
extends RefCounted
## 1フレーム分の「見える世界」。セッション（ソロ/オンライン）が作り、ビューが読む。
## ビューは SimWorld もネットワークも知らず、これだけを見て描画する。

class Entity:
	extends RefCounted

	enum Kind { PLAYER, ENEMY, PROJECTILE, PICKUP }
	const FLAG_DASHING := 1
	const FLAG_INVULN := 2
	const FLAG_HURT := 4

	var kind: Kind = Kind.PLAYER
	var id: int = 0
	var pos: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var velocity: Vector3 = Vector3.ZERO
	var health_fraction: float = 1.0
	var alive: bool = true
	## 敵の種類ID / 弾の武器 / 拾い物の中身（パーツID・"health"・"energy"）
	var type_id: StringName = &""
	var state: int = 0
	var flags: int = 0
	var display_name: String = ""
	var is_local: bool = false
	## プレイヤーの装備（スロット順のパーツ番号。-1 = なし）
	var loadout: PackedInt32Array = PackedInt32Array()
	## 自分が撃った弾か（自分の弾は予測側で描くので、権威の弾は描かない、などに使う）
	var owned_by_local: bool = false

var players: Array[Entity] = []
var enemies: Array[Entity] = []
var projectiles: Array[Entity] = []
var pickups: Array[Entity] = []
var local: Entity = null
