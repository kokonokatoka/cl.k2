class_name PartVisuals
extends RefCounted
## パーツの見た目。RobotPart.visual（シーン）があればそれを使い、なければスロットごとの手続き的なメッシュを作る。
## 新しいパーツは .tres を足すだけで見た目も付く（アクセント色と武器の種類から決まる）。


static func build(part: RobotPart) -> Node3D:
	if part.visual != null:
		return part.visual.instantiate() as Node3D
	match part.get_slot():
		RobotPart.Slot.EYES:
			return _eye(part)
		RobotPart.Slot.LEGS:
			return _legs(part)
		RobotPart.Slot.ARMS:
			return _arm(part)
		RobotPart.Slot.CORE:
			return _core(part)
	return Node3D.new()


static func _eye(part: RobotPart) -> Node3D:
	var root := Node3D.new()
	var housing := Mats.mesh(Mats.cylinder(0.12, 0.14), Mats.solid(Color(0.16, 0.17, 0.2), 0.6, 0.4), root, Vector3(0, 0, -0.05))
	housing.rotation_degrees.x = 90.0
	Mats.mesh(Mats.sphere(0.085), Mats.glow(part.accent, 3.0), root, Vector3(0, 0, -0.12))
	return root


static func _legs(part: RobotPart) -> Node3D:
	var root := Node3D.new()
	var dark := Mats.solid(Color(0.2, 0.22, 0.2), 0.5, 0.7)
	var trim := Mats.glow(part.accent, 1.2)
	# 履帯: 左右に平たい箱を置く
	for side in [-1.0, 1.0]:
		Mats.mesh(Mats.box(Vector3(0.22, 0.26, 0.75)), dark, root, Vector3(side * 0.34, -0.13, 0.0))
		Mats.mesh(Mats.box(Vector3(0.24, 0.04, 0.6)), trim, root, Vector3(side * 0.34, -0.02, 0.0))
	return root


static func _arm(part: RobotPart) -> Node3D:
	var root := Node3D.new()
	var steel := Mats.solid(Color(0.17, 0.18, 0.21), 0.7, 0.35)
	var glow := Mats.glow(part.accent, 2.5)
	var kind: StringName = part.weapon_kind if "weapon_kind" in part else &"blaster"
	match kind:
		&"scatter":
			# 太く短い砲身が2本
			for side in [-0.07, 0.07]:
				var barrel := Mats.mesh(Mats.cylinder(0.075, 0.42), steel, root, Vector3(side, 0, -0.21))
				barrel.rotation_degrees.x = 90.0
			Mats.mesh(Mats.box(Vector3(0.3, 0.2, 0.18)), steel, root, Vector3(0, 0, -0.02))
			Mats.mesh(Mats.box(Vector3(0.12, 0.04, 0.08)), glow, root, Vector3(0, 0.11, -0.05))
		&"pulse":
			var barrel := Mats.mesh(Mats.cylinder(0.045, 0.72), steel, root, Vector3(0, 0, -0.36))
			barrel.rotation_degrees.x = 90.0
			for z in [-0.18, -0.34, -0.5]:
				var ring := Mats.mesh(Mats.cylinder(0.07, 0.03), glow, root, Vector3(0, 0, z))
				ring.rotation_degrees.x = 90.0
			Mats.mesh(Mats.box(Vector3(0.18, 0.18, 0.2)), steel, root, Vector3(0, 0, -0.02))
		&"rail":
			for side in [-0.06, 0.06]:
				Mats.mesh(Mats.box(Vector3(0.035, 0.07, 0.95)), steel, root, Vector3(side, 0, -0.475))
			Mats.mesh(Mats.box(Vector3(0.05, 0.05, 0.8)), glow, root, Vector3(0, 0, -0.45))
			Mats.mesh(Mats.box(Vector3(0.24, 0.2, 0.2)), steel, root, Vector3(0, 0, -0.02))
		_:
			var barrel := Mats.mesh(Mats.cylinder(0.055, 0.48), steel, root, Vector3(0, 0, -0.24))
			barrel.rotation_degrees.x = 90.0
			Mats.mesh(Mats.box(Vector3(0.2, 0.17, 0.2)), steel, root, Vector3(0, 0, -0.02))
			Mats.mesh(Mats.box(Vector3(0.1, 0.03, 0.12)), glow, root, Vector3(0, 0.1, -0.04))
	return root


static func _core(part: RobotPart) -> Node3D:
	var root := Node3D.new()
	var steel := Mats.solid(Color(0.17, 0.18, 0.21), 0.7, 0.35)
	var glow := Mats.glow(part.accent, 3.0)
	match part.id:
		&"core_reactor":
			for side in [-0.14, 0.14]:
				Mats.mesh(Mats.cylinder(0.08, 0.44), glow, root, Vector3(side, 0, 0.08))
			Mats.mesh(Mats.box(Vector3(0.5, 0.1, 0.12)), steel, root, Vector3(0, 0.25, 0.08))
		&"core_plate":
			Mats.mesh(Mats.box(Vector3(0.74, 0.62, 0.1)), Mats.solid(part.accent.darkened(0.45), 0.6, 0.5), root, Vector3(0, 0, 0.05))
			Mats.mesh(Mats.box(Vector3(0.5, 0.06, 0.12)), glow, root, Vector3(0, 0.1, 0.06))
		&"core_glass":
			Mats.mesh(Mats.sphere(0.22), Mats.glass(Color(part.accent.r, part.accent.g, part.accent.b, 0.55)), root, Vector3(0, 0, 0.12))
			Mats.mesh(Mats.sphere(0.09), glow, root, Vector3(0, 0, 0.12))
		&"core_singularity":
			Mats.mesh(Mats.sphere(0.12), glow, root, Vector3(0, 0, 0.14))
			var ring := Mats.mesh(Mats.cylinder(0.24, 0.025, 24), Mats.glow(part.accent.lightened(0.3), 2.0), root, Vector3(0, 0, 0.14))
			ring.rotation_degrees.x = 90.0
		_:
			Mats.mesh(Mats.box(Vector3(0.46, 0.4, 0.14)), steel, root, Vector3(0, 0, 0.06))
			Mats.mesh(Mats.box(Vector3(0.2, 0.2, 0.06)), glow, root, Vector3(0, 0, 0.15))
	return root
