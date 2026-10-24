class_name PickupView
extends Node3D
## 拾い物の見た目。回りながら浮かぶ。パーツはレア度の色の光の柱が立ち、暗くても見つけやすい。

var _spinner: Node3D
var _expiring: bool = false
var _phase: float = 0.0


func setup(type_id: StringName) -> void:
	_phase = randf() * TAU
	_spinner = Node3D.new()
	_spinner.position.y = 0.9
	add_child(_spinner)

	var part := Content.part(type_id)
	var color := Color(1, 0.4, 0.45)
	if part != null:
		color = part.get_rarity_color()
		_build_part_icon(part, color)
		_add_beam(color, 3.0 + float(part.rarity))
	elif type_id == &"energy":
		color = Color(0.3, 0.9, 1.0)
		Mats.mesh(Mats.sphere(0.2, 12), Mats.glow(color, 3.0), _spinner)
		_add_beam(color, 1.6)
	else:
		color = Color(1.0, 0.35, 0.45)
		Mats.mesh(Mats.box(Vector3(0.38, 0.12, 0.12)), Mats.glow(color, 3.0), _spinner)
		Mats.mesh(Mats.box(Vector3(0.12, 0.38, 0.12)), Mats.glow(color, 3.0), _spinner)
		_add_beam(color, 1.6)
	# 足元の輪
	var ring := Mats.mesh(Mats.cylinder(0.5, 0.03, 24), Mats.unshaded(Color(color.r, color.g, color.b, 0.5), true), self, Vector3(0, 0.03, 0))
	ring.name = "Ring"


func apply(entity: RenderFrame.Entity, _delta: float) -> void:
	position = entity.pos
	var t := float(Time.get_ticks_msec()) / 1000.0 + _phase
	_spinner.rotation.y = t * 1.6
	_spinner.position.y = 0.9 + sin(t * 2.4) * 0.12
	_expiring = entity.state == 1
	# 消える直前は点滅
	visible = not _expiring or int(t * 8.0) % 2 == 0


func _build_part_icon(part: RobotPart, color: Color) -> void:
	var accent := part.accent
	match part.get_slot():
		RobotPart.Slot.EYES:
			Mats.mesh(Mats.sphere(0.2, 12), Mats.glow(accent, 3.0), _spinner)
			var ring := Mats.mesh(Mats.cylinder(0.3, 0.04, 20), Mats.glow(color, 2.0), _spinner)
			ring.rotation_degrees.x = 90.0
		RobotPart.Slot.LEGS:
			Mats.mesh(Mats.box(Vector3(0.16, 0.4, 0.16)), Mats.glow(accent, 2.5), _spinner, Vector3(-0.14, 0, 0))
			Mats.mesh(Mats.box(Vector3(0.16, 0.4, 0.16)), Mats.glow(accent, 2.5), _spinner, Vector3(0.14, 0, 0))
		RobotPart.Slot.ARMS:
			var barrel := Mats.mesh(Mats.cylinder(0.06, 0.6), Mats.glow(accent, 2.5), _spinner)
			barrel.rotation_degrees.z = 90.0
			Mats.mesh(Mats.box(Vector3(0.18, 0.28, 0.14)), Mats.glow(color, 2.0), _spinner, Vector3(-0.2, -0.12, 0))
		RobotPart.Slot.CORE:
			Mats.mesh(Mats.box(Vector3(0.32, 0.32, 0.32)), Mats.glow(accent, 3.0), _spinner)
			var frame := Mats.mesh(Mats.box(Vector3(0.46, 0.46, 0.46)), Mats.unshaded(Color(color.r, color.g, color.b, 0.3), true), _spinner)
			frame.rotation_degrees = Vector3(30, 30, 0)


func _add_beam(color: Color, height: float) -> void:
	var beam := Mats.mesh(Mats.cylinder(0.1, height, 8), Mats.unshaded(Color(color.r, color.g, color.b, 0.22), true), self, Vector3(0, height * 0.5, 0))
	beam.name = "Beam"
