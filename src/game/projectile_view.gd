class_name ProjectileView
extends Node3D
## 弾の見た目。進行方向に伸びた発光体。武器の種類で色と長さが変わる。

const STYLES := {
	&"blaster": {"color": Color(1.0, 0.75, 0.25), "length": 0.9, "width": 0.09},
	&"scatter": {"color": Color(1.0, 0.5, 0.2), "length": 0.5, "width": 0.07},
	&"pulse": {"color": Color(0.45, 0.95, 1.0), "length": 0.8, "width": 0.07},
	&"rail": {"color": Color(0.9, 0.55, 1.0), "length": 2.6, "width": 0.07},
	&"enemy": {"color": Color(1.0, 0.3, 0.45), "length": 0.7, "width": 0.14},
}

var _mesh: MeshInstance3D
var _glow: MeshInstance3D


func setup(weapon_kind: StringName) -> void:
	var style: Dictionary = STYLES.get(weapon_kind, STYLES[&"blaster"])
	var color: Color = style["color"]
	var length: float = style["length"]
	var width: float = style["width"]
	_mesh = Mats.mesh(Mats.box(Vector3(width, width, length)), Mats.unshaded(color.lightened(0.5)), self)
	_glow = Mats.mesh(Mats.box(Vector3(width * 3.0, width * 3.0, length * 1.15)), Mats.unshaded(Color(color.r, color.g, color.b, 0.35), true), self)


func apply(entity: RenderFrame.Entity, _delta: float) -> void:
	position = entity.pos
	rotation.y = entity.yaw
