class_name SimProjectile
extends RefCounted
## 飛んでいる弾。物理ボディではなく、毎ティック「前の位置→今の位置」の線分で当たり判定をする。

enum Owner { PLAYER, ENEMY }

var id: int = 0
var owner_kind: Owner = Owner.PLAYER
var owner_id: int = 0
var weapon_kind: StringName = &"blaster"
var pos: Vector3 = Vector3.ZERO
var vel: Vector3 = Vector3.ZERO
var life: float = 1.0
var damage: float = 10.0
var pierce_left: int = 0
## すでに当てた相手（貫通弾の二重ヒット防止）。種類×1e9 + id
var hit_keys: Array[int] = []

var prev_pos: Vector3 = Vector3.ZERO


static func make(owner_type: Owner, owner: int, kind: StringName, at: Vector3, velocity: Vector3, lifetime: float, dmg: float, pierce: int) -> SimProjectile:
	var p := SimProjectile.new()
	p.owner_kind = owner_type
	p.owner_id = owner
	p.weapon_kind = kind
	p.pos = at
	p.prev_pos = at
	p.vel = velocity
	p.life = lifetime
	p.damage = dmg
	p.pierce_left = pierce
	return p
