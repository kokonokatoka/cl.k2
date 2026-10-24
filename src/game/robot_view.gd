class_name RobotView
extends Node3D
## プレイヤーのロボットの見た目。状態は持たず、RenderFrame.Entity を受けて合わせるだけ。
## 装備が変わったときだけソケットのパーツを付け替える。

const SLOT_COUNT := 4

var _model: Node3D
var _head: MeshInstance3D
var _body: MeshInstance3D
var _sockets: Array[Node3D] = []
var _body_material: StandardMaterial3D
var _dash_trail: CPUParticles3D
var _loadout: PackedInt32Array = PackedInt32Array()
var _ride_height: float = 0.0
var _flash: float = 0.0
var _alive: bool = true
var _tint: Color = Color(0.9, 0.55, 0.2)


func _init() -> void:
	_build()


func set_tint(color: Color) -> void:
	if color == _tint:
		return
	_tint = color
	_body_material.albedo_color = color


## 毎フレーム。entity: プレイヤー
func apply(entity: RenderFrame.Entity, delta: float) -> void:
	_set_loadout(entity.loadout)
	position = entity.pos
	_model.rotation.y = entity.yaw
	_model.position.y = _ride_height

	if entity.alive != _alive:
		_alive = entity.alive
		visible = _alive
	if not _alive:
		return

	var dashing := entity.flags & RenderFrame.Entity.FLAG_DASHING != 0
	_dash_trail.emitting = dashing
	# 無敵中は点滅
	var invulnerable := entity.flags & RenderFrame.Entity.FLAG_INVULN != 0
	_model.visible = not invulnerable or int(Time.get_ticks_msec() / 90.0) % 2 == 0
	# 被弾の閃光（外から hit_flash() で起動）
	_flash = maxf(0.0, _flash - delta * 5.0)
	_body_material.emission_enabled = _flash > 0.0
	if _flash > 0.0:
		_body_material.emission = Color(1, 1, 1) * _flash


func hit_flash() -> void:
	_flash = 1.0


## 見た目の高さ（頭上の名前表示の位置に使う）
func head_height() -> float:
	return _ride_height + 1.25


func _build() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	_body_material = Mats.solid(_tint, 0.4, 0.5).duplicate() as StandardMaterial3D
	_body = Mats.mesh(Mats.box(Vector3(0.8, 0.6, 0.6)), _body_material, _model, Vector3(0, 0.3, 0))
	var plate_material := Mats.solid(Color(0.8, 0.82, 0.85), 0.4, 0.5)
	_head = Mats.mesh(Mats.box(Vector3(0.5, 0.35, 0.45)), plate_material, _model, Vector3(0, 0.8, 0))
	# 肩のアクセント
	for side in [-1.0, 1.0]:
		Mats.mesh(Mats.box(Vector3(0.12, 0.16, 0.5)), plate_material, _model, Vector3(side * 0.46, 0.5, 0))

	_sockets.resize(SLOT_COUNT)
	_sockets[RobotPart.Slot.EYES] = _make_socket(_head, Vector3(0, 0.03, -0.225))
	_sockets[RobotPart.Slot.LEGS] = _make_socket(_model, Vector3.ZERO)
	_sockets[RobotPart.Slot.ARMS] = _make_socket(_model, Vector3(0, 0.3, -0.34))
	_sockets[RobotPart.Slot.CORE] = _make_socket(_model, Vector3(0, 0.35, 0.3))

	_dash_trail = CPUParticles3D.new()
	_dash_trail.amount = 24
	_dash_trail.lifetime = 0.35
	_dash_trail.emitting = false
	_dash_trail.local_coords = false
	_dash_trail.direction = Vector3.UP
	_dash_trail.spread = 25.0
	_dash_trail.initial_velocity_min = 0.2
	_dash_trail.initial_velocity_max = 1.0
	_dash_trail.gravity = Vector3.ZERO
	_dash_trail.scale_amount_min = 0.6
	_dash_trail.scale_amount_max = 1.2
	_dash_trail.mesh = Mats.sphere(0.1, 8)
	_dash_trail.material_override = Mats.unshaded(Color(0.6, 0.85, 1.0, 0.5), true)
	_dash_trail.position = Vector3(0, 0.4, 0)
	add_child(_dash_trail)


func _make_socket(parent: Node3D, at: Vector3) -> Node3D:
	var socket := Node3D.new()
	socket.position = at
	parent.add_child(socket)
	return socket


func _set_loadout(indices: PackedInt32Array) -> void:
	if indices == _loadout:
		return
	_loadout = indices
	_ride_height = 0.0
	for slot in SLOT_COUNT:
		for child in _sockets[slot].get_children():
			child.queue_free()
		var part := Content.part_at(indices[slot]) if slot < indices.size() else null
		if part == null:
			continue
		_sockets[slot].add_child(PartVisuals.build(part))
		if part is LegPart:
			_ride_height = part.ride_height
