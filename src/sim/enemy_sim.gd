class_name EnemySim
extends RefCounted
## 敵 1 体・1 ティックの思考と移動。乱数は world.rng（サーバー権威）だけを使う。
## 挙動は EnemyDef.Behavior で切り替える: 追跡 / 射撃 / 溜めて突進。

const ACCELERATION: float = 22.0
const RETARGET_INTERVAL: float = 0.3
## 体当たりが届く余白（半径の合計に足す）
const MELEE_MARGIN: float = 0.35
const SEPARATION_PUSH: float = 3.5
## ドローンが浮いている高さ（被弾判定・見た目）
const HOVER_HEIGHT: float = 0.5


static func step(e: SimEnemy, world: SimWorld, dt: float) -> void:
	e.prev_pos = e.pos
	e.prev_yaw = e.yaw
	e.state_time += dt
	e.attack_cd = maxf(0.0, e.attack_cd - dt)
	e.hurt_flash = maxf(0.0, e.hurt_flash - dt)
	e.retarget_cd -= dt
	if e.retarget_cd <= 0.0:
		e.retarget_cd = RETARGET_INTERVAL
		e.target_id = _find_target(e, world)

	var target: SimPlayer = world.players.get(e.target_id)
	if target != null and not target.alive:
		target = null
		e.target_id = 0

	var desired := Vector3.ZERO
	match e.def.behavior:
		EnemyDef.Behavior.CHASER:
			desired = _chaser(e, target, world)
		EnemyDef.Behavior.SHOOTER:
			desired = _shooter(e, target, world, dt)
		EnemyDef.Behavior.CHARGER:
			desired = _charger(e, target, world)
	_move(e, desired, target, world, dt)


static func _find_target(e: SimEnemy, world: SimWorld) -> int:
	var best_id := 0
	var best_d2 := e.def.aggro_range * e.def.aggro_range
	for p: SimPlayer in world.players.values():
		if not p.alive:
			continue
		var d2 := p.pos.distance_squared_to(e.pos)
		if d2 < best_d2:
			best_d2 = d2
			best_id = p.id
	# いまの標的は少し遠くまで追い続ける（別の標的がよほど近くない限り乗り換えない）
	var current: SimPlayer = world.players.get(e.target_id)
	if current != null and current.alive:
		var keep := e.def.aggro_range * 1.5
		var current_d2 := current.pos.distance_squared_to(e.pos)
		if current_d2 <= keep * keep and (best_id == 0 or best_d2 > current_d2 * 0.5):
			return current.id
	return best_id


static func _wander(e: SimEnemy, world: SimWorld) -> Vector3:
	e.wander_cd -= SimConfig.DT
	if e.wander_cd <= 0.0 or e.pos.distance_to(e.wander_target) < 1.0:
		e.wander_cd = world.rng.range_float(2.0, 4.5)
		var angle := world.rng.range_float(0.0, TAU)
		var distance := world.rng.range_float(3.0, 8.0)
		var limit := world.geometry.half_size - 2.0
		e.wander_target = Vector3(
			clampf(e.pos.x + cos(angle) * distance, -limit, limit), 0.0,
			clampf(e.pos.z + sin(angle) * distance, -limit, limit))
	e.set_state(SimEnemy.State.WANDER)
	var to := e.wander_target - e.pos
	to.y = 0.0
	return to.normalized() * e.def.move_speed * 0.4 if to.length() > 0.5 else Vector3.ZERO


static func _chaser(e: SimEnemy, target: SimPlayer, world: SimWorld) -> Vector3:
	if target == null:
		return _wander(e, world)
	e.set_state(SimEnemy.State.CHASE)
	var to := _flat(target.pos - e.pos)
	var distance := to.length()
	_try_contact_damage(e, target, world, distance)
	return to / distance * e.def.move_speed if distance > 0.3 else Vector3.ZERO


static func _shooter(e: SimEnemy, target: SimPlayer, world: SimWorld, dt: float) -> Vector3:
	if target == null:
		return _wander(e, world)
	e.set_state(SimEnemy.State.CHASE)
	var def := e.def
	var to := _flat(target.pos - e.pos)
	var distance := maxf(to.length(), 0.001)
	var direction := to / distance
	var desired := Vector3.ZERO
	if distance > def.preferred_distance + 1.5:
		desired = direction * def.move_speed
	elif distance < def.preferred_distance - 2.0:
		desired = -direction * def.move_speed
	else:
		e.strafe_cd -= dt
		if e.strafe_cd <= 0.0:
			e.strafe_cd = world.rng.range_float(1.2, 2.6)
			e.strafe_sign = -e.strafe_sign
		desired = Vector3(-direction.z, 0.0, direction.x) * e.strafe_sign * def.move_speed * 0.6
	_try_contact_damage(e, target, world, distance)

	if e.attack_cd <= 0.0 and distance <= def.aggro_range:
		var muzzle := e.pos + Vector3(0.0, HOVER_HEIGHT + def.height * 0.5, 0.0) + direction * (def.radius + 0.2)
		var lead := target.vel * (distance / def.projectile_speed) * 0.5
		var aim_point := target.pos + lead + Vector3(0.0, target.body_height() * 0.5, 0.0)
		if Motion.has_line_of_sight(world.geometry, muzzle, aim_point):
			var shot_direction := (aim_point - muzzle).normalized()
			shot_direction = shot_direction.rotated(Vector3.UP, world.rng.next_signed() * deg_to_rad(4.0))
			world.spawn_projectile(SimProjectile.make(
				SimProjectile.Owner.ENEMY, e.id, &"enemy", muzzle,
				shot_direction * def.projectile_speed, 2.4, def.projectile_damage, 0))
			world.add_event(SimEvent.make(SimEvent.Type.ENEMY_SHOT, muzzle, e.id))
			e.attack_cd = def.fire_interval
	return desired


static func _charger(e: SimEnemy, target: SimPlayer, world: SimWorld) -> Vector3:
	var def := e.def
	var to := _flat(target.pos - e.pos) if target != null else Vector3.ZERO
	var distance := to.length()
	match e.state:
		SimEnemy.State.WINDUP:
			if e.state_time >= def.charge_windup:
				e.charge_dir = to / distance if distance > 0.01 else SimMath.forward(e.yaw)
				e.charge_hit = false
				e.set_state(SimEnemy.State.CHARGE)
			return Vector3.ZERO
		SimEnemy.State.CHARGE:
			if e.state_time >= def.charge_time or e.stuck_time > 0.12:
				e.attack_cd = def.charge_cooldown
				e.set_state(SimEnemy.State.STUN)
				return Vector3.ZERO
			if target != null and not e.charge_hit and distance <= def.radius + SimConfig.PLAYER_RADIUS + MELEE_MARGIN:
				e.charge_hit = true
				world.damage_player(target, def.contact_damage * 1.5, SimProjectile.Owner.ENEMY, e.id, target.pos)
			return e.charge_dir * def.charge_speed
		SimEnemy.State.STUN:
			if e.state_time >= def.charge_cooldown:
				e.set_state(SimEnemy.State.CHASE)
			return Vector3.ZERO
	# 通常時: 追いかけて、距離が合えば溜めに入る
	if target == null:
		return _wander(e, world)
	e.set_state(SimEnemy.State.CHASE)
	_try_contact_damage(e, target, world, distance)
	if distance < 10.0 and distance > 2.5 and e.attack_cd <= 0.0 and Motion.has_line_of_sight(
			world.geometry, e.pos + Vector3.UP, target.pos + Vector3.UP):
		e.set_state(SimEnemy.State.WINDUP)
		world.add_event(SimEvent.make(SimEvent.Type.ENEMY_WINDUP, e.pos, e.id))
		return Vector3.ZERO
	return to / distance * def.move_speed if distance > 0.3 else Vector3.ZERO


static func _try_contact_damage(e: SimEnemy, target: SimPlayer, world: SimWorld, distance: float) -> void:
	var reach := e.def.radius + SimConfig.PLAYER_RADIUS + MELEE_MARGIN
	# ジャンプで頭上を越えれば当たらない
	if distance <= reach and e.attack_cd <= 0.0 and target.pos.y < e.def.height + HOVER_HEIGHT:
		world.damage_player(target, e.def.contact_damage, SimProjectile.Owner.ENEMY, e.id, target.pos)
		e.attack_cd = e.def.contact_interval


static func _move(e: SimEnemy, desired_velocity: Vector3, target: SimPlayer, world: SimWorld, dt: float) -> void:
	var def := e.def
	var desired := desired_velocity
	# 味方どうしの重なりを避ける
	for other: SimEnemy in world.enemies.values():
		if other == e:
			continue
		var apart := _flat(e.pos - other.pos)
		var min_distance := def.radius + other.def.radius
		var distance := apart.length()
		if distance < min_distance and distance > 0.0001:
			desired += apart / distance * (min_distance - distance) * SEPARATION_PUSH * def.move_speed
	# 壁に詰まったら横へ回り込む
	if e.stuck_time > 0.25 and e.state != SimEnemy.State.CHARGE:
		desired = desired.rotated(Vector3.UP, e.avoid_sign * 1.2)

	var horizontal := Vector3(e.vel.x, 0.0, e.vel.z)
	if e.state == SimEnemy.State.CHARGE:
		horizontal = desired
	else:
		horizontal = horizontal.move_toward(desired, ACCELERATION * dt)

	var intended := Vector2(horizontal.x, horizontal.z) * dt
	var moved := Motion.move_circle(world.geometry, e.pos, intended, def.radius, 0.0)
	var actual := Vector2(moved.x - e.pos.x, moved.z - e.pos.z)
	if intended.length() > 0.001:
		if actual.length() < intended.length() * 0.3:
			e.stuck_time += dt
			if e.stuck_time > 0.9:
				e.avoid_sign = -e.avoid_sign
				e.stuck_time = 0.3
		else:
			e.stuck_time = maxf(0.0, e.stuck_time - dt * 2.0)
	else:
		e.stuck_time = maxf(0.0, e.stuck_time - dt * 2.0)
	e.pos = Vector3(moved.x, 0.0, moved.z)
	e.vel = Vector3(actual.x, 0.0, actual.y) / dt if actual.length() < intended.length() * 0.9 else horizontal

	# 向き: 標的を見る（突進中は進行方向）。それ以外は進行方向
	var face := horizontal
	if target != null and e.state in [SimEnemy.State.CHASE, SimEnemy.State.WINDUP, SimEnemy.State.STUN]:
		face = _flat(target.pos - e.pos)
	if face.length_squared() > 0.01:
		e.yaw = SimMath.lerp_angle_short(e.yaw, SimMath.yaw_of(face), minf(1.0, 10.0 * dt))


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
