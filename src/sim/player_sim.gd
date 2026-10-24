class_name PlayerSim
extends RefCounted
## プレイヤー1人分・1ティックの移動と行動。
## サーバー・ソロ・クライアント予測のすべてがこの関数を通る。ここが同じ結果を返すことがネットコードの前提。
## 弾の生成やダメージは扱わない（それは SimWorld の仕事）。撃ったことだけを EV_FIRE で返す。

const EV_JUMP: int = 1
const EV_LAND: int = 2
const EV_DASH: int = 4
const EV_FIRE: int = 8


static func step(p: SimPlayer, input: PlayerInput, geo: WorldGeometry, dt: float = SimConfig.DT) -> int:
	p.prev_pos = p.pos
	p.prev_yaw = p.yaw
	p.last_seq = input.seq
	if not p.alive:
		p.vel = Vector3.ZERO
		p.last_buttons = 0
		return 0

	var stats := p.stats
	var events := 0
	var pressed := input.buttons & ~p.last_buttons
	p.last_buttons = input.buttons

	p.invuln = maxf(0.0, p.invuln - dt)
	p.dash_cd = maxf(0.0, p.dash_cd - dt)
	# 発射間隔の端数を次に持ち越す（連射速度が正確になる）。溜め撃ちを防ぐため下限を -dt に抑える
	p.fire_cd = maxf(p.fire_cd - dt, -dt)
	p.energy = minf(stats.max_energy, p.energy + stats.energy_regen * dt)
	p.yaw = input.aim_yaw

	# 入力は信用しない（量子化の誤差・改ざんで長さが 1 を超えうる）
	var move := input.move.limit_length(1.0)
	var wish := Vector3(move.x, 0.0, move.y) * stats.move_speed

	# ダッシュ開始
	if pressed & PlayerInput.BTN_DASH and stats.can_dash() and p.dash_time <= 0.0 and p.dash_cd <= 0.0 and p.energy >= stats.dash_cost:
		p.dash_dir = wish.normalized() if wish.length_squared() > 0.0001 else SimMath.forward(p.yaw)
		p.dash_time = stats.dash_time
		p.dash_cd = stats.dash_cooldown + stats.dash_time
		p.energy -= stats.dash_cost
		events |= EV_DASH

	var horizontal := Vector3(p.vel.x, 0.0, p.vel.z)
	if p.dash_time > 0.0:
		horizontal = p.dash_dir * stats.dash_speed
		p.dash_time = maxf(0.0, p.dash_time - dt)
	else:
		horizontal = horizontal.move_toward(wish, stats.acceleration * dt)

	# ジャンプと重力
	if p.on_floor and pressed & PlayerInput.BTN_JUMP and stats.jump_velocity > 0.0:
		p.vel.y = stats.jump_velocity
		p.on_floor = false
		events |= EV_JUMP
	if not p.on_floor:
		p.vel.y -= SimConfig.GRAVITY * dt

	# 水平移動（壁でスライド）
	var intended := Vector2(horizontal.x, horizontal.z) * dt
	var moved := Motion.move_circle(geo, p.pos, intended, SimConfig.PLAYER_RADIUS)
	var actual := Vector2(moved.x - p.pos.x, moved.z - p.pos.z)
	if (actual - intended).length_squared() > 1e-8:
		# 壁にぶつかった分は速度からも落とす
		horizontal = Vector3(actual.x, 0.0, actual.y) / dt
	p.vel.x = horizontal.x
	p.vel.z = horizontal.z
	p.pos.x = moved.x
	p.pos.z = moved.z

	# 垂直移動と着地
	var ground := Motion.support_height(geo, p.pos, SimConfig.PLAYER_RADIUS)
	p.pos.y += p.vel.y * dt
	if p.pos.y <= ground + 0.0001 and p.vel.y <= 0.0:
		if not p.on_floor and p.vel.y < -4.0:
			events |= EV_LAND
		p.pos.y = ground
		p.vel.y = 0.0
		p.on_floor = true
	else:
		p.on_floor = false

	# 発射
	if input.buttons & PlayerInput.BTN_FIRE and stats.can_fire() and p.fire_cd <= 0.0 and p.energy >= stats.shot_cost:
		p.fire_cd += stats.fire_interval
		p.energy -= stats.shot_cost
		events |= EV_FIRE
	return events


## 1回の発射で出る弾。ばらつきは (プレイヤー, 入力番号, 弾の番号) だけで決まる
## ので、サーバーとクライアントが同じ弾を再現できる（クライアントが見た目だけ先に出せる）。
static func build_shots(p: SimPlayer, seq: int) -> Array[SimProjectile]:
	var stats := p.stats
	var shots: Array[SimProjectile] = []
	var origin := p.muzzle_position()
	for i in stats.pellets:
		var rng := DetRng.new(DetRng.mix(DetRng.mix(p.id, seq), i))
		var angle := p.yaw + rng.next_signed() * stats.spread
		shots.append(SimProjectile.make(
			SimProjectile.Owner.PLAYER, p.id, stats.weapon_kind, origin,
			SimMath.forward(angle) * stats.projectile_speed,
			stats.projectile_life, stats.weapon_damage, stats.pierce))
	return shots
