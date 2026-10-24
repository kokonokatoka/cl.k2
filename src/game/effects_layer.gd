class_name EffectsLayer
extends Node3D
## 一瞬だけ出る演出（火花・爆発・衝撃波・ダメージ数字）。使い捨てのノードを作り、終わったら片付ける。
## 同時に出しすぎないよう上限を持つ（Web でも重くならないように）。

const MAX_ACTIVE := 90

var _active: int = 0


func spark(at: Vector3, color: Color, count: int = 8, speed: float = 4.0, size: float = 0.07) -> void:
	_burst(at, color, count, 0.35, speed, size, Vector3(0, -9.0, 0))


func explosion(at: Vector3, color: Color, scale_factor: float = 1.0) -> void:
	_burst(at + Vector3(0, 0.8, 0), color.lightened(0.3), int(26 * scale_factor), 0.6, 6.0 * scale_factor, 0.14 * scale_factor, Vector3(0, -4.0, 0))
	_burst(at + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.6), int(10 * scale_factor), 0.35, 3.0 * scale_factor, 0.22 * scale_factor, Vector3.ZERO)
	shockwave(at + Vector3(0, 0.1, 0), color, 2.2 * scale_factor)


func muzzle_flash(at: Vector3, color: Color) -> void:
	_burst(at, color.lightened(0.4), 5, 0.12, 3.0, 0.09, Vector3.ZERO)


func dust(at: Vector3, count: int = 6) -> void:
	_burst(at + Vector3(0, 0.05, 0), Color(0.7, 0.72, 0.75, 0.6), count, 0.5, 1.6, 0.12, Vector3(0, 0.5, 0))


func pickup_burst(at: Vector3, color: Color) -> void:
	_burst(at + Vector3(0, 0.9, 0), color, 18, 0.7, 3.5, 0.08, Vector3(0, 2.0, 0))
	shockwave(at + Vector3(0, 0.1, 0), color, 1.6)


## 地面を広がる輪
func shockwave(at: Vector3, color: Color, radius: float, duration: float = 0.45) -> void:
	if _active >= MAX_ACTIVE:
		return
	_active += 1
	var ring := MeshInstance3D.new()
	ring.mesh = Mats.cylinder(1.0, 0.03, 28)
	ring.material_override = Mats.unshaded(Color(color.r, color.g, color.b, 0.55), true)
	ring.position = at
	ring.scale = Vector3(0.2, 1.0, 0.2)
	add_child(ring)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, duration)
	tween.chain().tween_callback(_release.bind(ring))


## ダメージの数字が浮かび上がる
func damage_number(at: Vector3, amount: float, color: Color) -> void:
	if _active >= MAX_ACTIVE:
		return
	_active += 1
	var label := Label3D.new()
	label.text = str(roundi(amount))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.012
	label.font_size = 48
	label.outline_size = 12
	label.modulate = color
	label.position = at + Vector3(randf_range(-0.2, 0.2), 0.8, randf_range(-0.2, 0.2))
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.4, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(_release.bind(label))


func _burst(at: Vector3, color: Color, count: int, lifetime: float, speed: float, size: float, gravity: Vector3) -> void:
	if _active >= MAX_ACTIVE or count <= 0:
		return
	_active += 1
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = lifetime
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.gravity = gravity
	particles.mesh = Mats.box(Vector3.ONE * size)
	particles.material_override = Mats.unshaded(color, true)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.3
	particles.position = at
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.15).timeout.connect(_release.bind(particles))


func _release(node: Node) -> void:
	_active = maxi(0, _active - 1)
	if is_instance_valid(node):
		node.queue_free()
