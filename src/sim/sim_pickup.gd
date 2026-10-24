class_name SimPickup
extends RefCounted
## 床に落ちている拾い物。上を通ると拾える。

enum Kind { PART, HEALTH, ENERGY }

var id: int = 0
var kind: Kind = Kind.PART
var part_id: StringName = &""
var pos: Vector3 = Vector3.ZERO
## 残り時間[秒]。負の値は消えない（置き場所に固定された拾い物）
var life: float = -1.0
## 置き場所の番号（再出現に使う）。-1 は敵のドロップ
var spot: int = -1


static func make_part(part: RobotPart, at: Vector3, lifetime: float, spot_index: int = -1) -> SimPickup:
	var p := SimPickup.new()
	p.kind = Kind.PART
	p.part_id = part.id
	p.pos = at
	p.life = lifetime
	p.spot = spot_index
	return p


static func make_orb(orb_kind: Kind, at: Vector3, lifetime: float, spot_index: int = -1) -> SimPickup:
	var p := SimPickup.new()
	p.kind = orb_kind
	p.pos = at
	p.life = lifetime
	p.spot = spot_index
	return p
