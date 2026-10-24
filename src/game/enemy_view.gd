class_name EnemyView
extends Node3D
## 敵ドローンの見た目。EnemyDef の色・大きさ・挙動から手続き的に作る。

var _def: EnemyDef
var _body_root: Node3D
var _core_material: StandardMaterial3D
var _body_material: StandardMaterial3D
var _phase: float = 0.0
var _flash: float = 0.0


func setup(def: EnemyDef) -> void:
	_def = def
	_phase = randf() * TAU
	_body_root = Node3D.new()
	_body_root.scale = Vector3.ONE * def.scale
	add_child(_body_root)

	_body_material = Mats.solid(def.color.darkened(0.35), 0.6, 0.4).duplicate() as StandardMaterial3D
	_core_material = Mats.glow(def.color.lightened(0.15), 3.0).duplicate() as StandardMaterial3D
	var steel := Mats.solid(Color(0.14, 0.15, 0.18), 0.7, 0.4)

	# 浮遊する球体の胴体と、発光コア
	Mats.mesh(Mats.sphere(0.4), _body_material, _body_root, Vector3(0, EnemySim.HOVER_HEIGHT + 0.35, 0))
	var ring := Mats.mesh(Mats.cylinder(0.52, 0.06, 20), steel, _body_root, Vector3(0, EnemySim.HOVER_HEIGHT + 0.35, 0))
	ring.rotation_degrees.z = 8.0
	var eye := Mats.mesh(Mats.sphere(0.16, 12), _core_material, _body_root, Vector3(0, EnemySim.HOVER_HEIGHT + 0.4, -0.3))
	eye.scale = Vector3(1.0, 1.0, 0.6)

	match def.behavior:
		EnemyDef.Behavior.SHOOTER:
			var barrel := Mats.mesh(Mats.cylinder(0.06, 0.45), steel, _body_root, Vector3(0, EnemySim.HOVER_HEIGHT + 0.3, -0.5))
			barrel.rotation_degrees.x = 90.0
		EnemyDef.Behavior.CHARGER:
			for side in [-1.0, 1.0]:
				var horn := Mats.mesh(Mats.box(Vector3(0.1, 0.1, 0.5)), steel, _body_root, Vector3(side * 0.3, EnemySim.HOVER_HEIGHT + 0.55, -0.35))
				horn.rotation_degrees.y = side * -20.0
			Mats.mesh(Mats.box(Vector3(0.9, 0.3, 0.5)), _body_material, _body_root, Vector3(0, EnemySim.HOVER_HEIGHT + 0.2, 0.15))
		_:
			for side in [-1.0, 1.0]:
				Mats.mesh(Mats.box(Vector3(0.05, 0.3, 0.3)), steel, _body_root, Vector3(side * 0.48, EnemySim.HOVER_HEIGHT + 0.35, 0.1))


func apply(entity: RenderFrame.Entity, delta: float) -> void:
	position = Vector3(entity.pos.x, 0.0, entity.pos.z)
	rotation.y = entity.yaw
	var t := float(Time.get_ticks_msec()) / 1000.0 + _phase
	_body_root.position.y = sin(t * 3.0) * 0.06
	# 進行方向へ少し傾ける
	var speed := Vector2(entity.velocity.x, entity.velocity.z).length()
	_body_root.rotation.x = lerpf(_body_root.rotation.x, -clampf(speed * 0.04, 0.0, 0.25), minf(1.0, delta * 8.0))

	_flash = maxf(0.0, _flash - delta * 8.0)
	if entity.flags & RenderFrame.Entity.FLAG_HURT != 0:
		_flash = 1.0
	var warning := entity.state == SimEnemy.State.WINDUP
	var charging := entity.state == SimEnemy.State.CHARGE
	if _flash > 0.0:
		_core_material.emission = Color(1, 1, 1)
		_core_material.emission_energy_multiplier = 3.0 + 4.0 * _flash
	elif warning:
		# 突進の予兆: 赤白に激しく点滅
		var blink := 0.5 + 0.5 * sin(t * 40.0)
		_core_material.emission = Color(1, 0.2, 0.15).lerp(Color(1, 1, 1), blink)
		_core_material.emission_energy_multiplier = 4.0 + 4.0 * blink
	else:
		_core_material.emission = _def.color.lightened(0.15)
		_core_material.emission_energy_multiplier = 5.0 if charging else 3.0
	_body_root.scale = Vector3.ONE * _def.scale * (Vector3(1.0, 1.0, 1.25) if charging else Vector3.ONE)
