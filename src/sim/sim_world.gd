class_name SimWorld
extends RefCounted
## 決定論的なワールド。プレイヤー・敵・弾・拾い物をすべて持ち、1ティックずつ進める。
## ノードにも Godot の物理にも依存しない。ソロはこれを直接、サーバーも同じものを、クライアントは予測用に一部を使う。
## 起きたことは `events` に積まれるので、描画・音・通信は drain_events() で受け取る。

const KILL_SCORE: int = 50
const ORB_HEAL: float = 35.0
const ORB_ENERGY: float = 45.0
## 持っているパーツをもう一度拾ったときの回復量
const DUPLICATE_HEAL: float = 25.0

var rules: GameRules
var geometry: WorldGeometry
var arena_seed: int = 1
var tick: int = 0
var time: float = 0.0

## プレイヤーは接続ID、ほかは通し番号で引く
var players: Dictionary = {}
var enemies: Dictionary = {}
var projectiles: Dictionary = {}
var pickups: Dictionary = {}
var events: Array[SimEvent] = []

## ゲームプレイ用の乱数（権威側だけが使う）
var rng: DetRng
var spawn_enemies: bool = true

## ウェーブシステム
var wave_number: int = 1
var wave_kills: int = 0
var wave_target: int = 6
var wave_interval: float = 0.0
var boss_id: int = 0

var _next_id: int = 1
var _enemy_timer: float = 1.5
## 置き場所の番号 -> 再出現までの残り秒
var _spot_timers: Dictionary = {}


func _init(game_rules: GameRules = null, seed_value: int = 1) -> void:
	rules = game_rules if game_rules != null else GameRules.new()
	arena_seed = seed_value
	geometry = ArenaGenerator.generate(seed_value, rules)
	rng = DetRng.new(DetRng.mix(seed_value, 0x5EED))
	for spot in geometry.pickup_spots.size():
		_spawn_world_pickup(spot)


# --- プレイヤーの出入りと装備 ---

func add_player(id: int, display_name: String, loadout: Loadout = null, owned_part_ids: Array = []) -> SimPlayer:
	var p := SimPlayer.new()
	p.id = id
	p.player_name = display_name
	p.team = id
	for part in Content.starter_parts():
		p.inventory[part.id] = true
	for part_id in owned_part_ids:
		if Content.part(StringName(part_id)) != null:
			p.inventory[StringName(part_id)] = true
	# 渡されたロードアウトは所持品で検証する。足りない枠はスターターで埋める
	var valid := Loadout.new()
	for part in Content.starter_parts():
		valid.equip(part)
	if loadout != null:
		for part in loadout.parts():
			if p.inventory.has(part.id):
				valid.equip(part)
	p.set_loadout(valid)
	p.respawn(_pick_player_spawn(), rules.spawn_protection)
	players[id] = p
	return p


func remove_player(id: int) -> void:
	players.erase(id)


## 所持しているパーツだけ装備できる。成功したら true
func equip_part(player_id: int, part_id: StringName) -> bool:
	var p: SimPlayer = players.get(player_id)
	var part := Content.part(part_id)
	if p == null or part == null or not p.inventory.has(part_id):
		return false
	var next := p.loadout.duplicate_loadout()
	next.equip(part)
	p.set_loadout(next)
	return true


func unequip_slot(player_id: int, slot: RobotPart.Slot) -> bool:
	var p: SimPlayer = players.get(player_id)
	if p == null:
		return false
	var next := p.loadout.duplicate_loadout()
	next.unequip(slot)
	p.set_loadout(next)
	return true


## 所持品に加える（拾得・デバッグ用）。初めて手に入れたなら true
func grant_part(player_id: int, part_id: StringName) -> bool:
	var p: SimPlayer = players.get(player_id)
	if p == null or Content.part(part_id) == null:
		return false
	var is_new := not p.inventory.has(part_id)
	p.inventory[part_id] = true
	return is_new


# --- 1ティック ---

## inputs: プレイヤーID -> PlayerInput。入力のないプレイヤーは何も押していない扱い
func step(inputs: Dictionary) -> void:
	var dt := SimConfig.DT
	for id in players:
		var p: SimPlayer = players[id]
		var input: PlayerInput = inputs.get(id)
		if input == null:
			input = PlayerInput.new()
			input.seq = p.last_seq
			input.aim_yaw = p.yaw
		var flags := PlayerSim.step(p, input, geometry, dt)
		_handle_player_flags(p, input, flags)
		if not p.alive:
			p.respawn_timer -= dt
			if p.respawn_timer <= 0.0:
				p.respawn(_pick_player_spawn(), rules.spawn_protection)
				add_event(SimEvent.make(SimEvent.Type.RESPAWN, p.pos, p.id))

	for id in enemies.keys():
		EnemySim.step(enemies[id], self, dt)
	_step_projectiles(dt)
	_step_pickups(dt)
	_step_spawners(dt)
	tick += 1
	time += dt


func add_event(event: SimEvent) -> void:
	if events.size() < SimConfig.MAX_EVENTS_PER_TICK * 8:
		events.append(event)


## たまったイベントを受け取って空にする
func drain_events() -> Array[SimEvent]:
	var drained := events
	events = []
	return drained


func spawn_projectile(projectile: SimProjectile) -> void:
	projectile.id = _allocate_id()
	projectiles[projectile.id] = projectile


# --- ダメージ ---

func damage_player(victim: SimPlayer, amount: float, attacker_kind: SimProjectile.Owner, attacker_id: int, at: Vector3) -> void:
	if not victim.alive or victim.invuln > 0.0:
		return
	var dealt := maxf(amount * 0.1, amount - victim.stats.armor)
	victim.health -= dealt
	var credited := attacker_id if attacker_kind == SimProjectile.Owner.PLAYER else 0
	add_event(SimEvent.make(SimEvent.Type.HIT, at, credited, victim.id, dealt, &"player"))
	if victim.health <= 0.0:
		victim.health = 0.0
		victim.alive = false
		victim.deaths += 1
		victim.respawn_timer = rules.respawn_delay
		victim.vel = Vector3.ZERO
		var killer: SimPlayer = players.get(attacker_id) if attacker_kind == SimProjectile.Owner.PLAYER else null
		if killer != null:
			killer.kills += 1
			killer.score += KILL_SCORE
		add_event(SimEvent.make(SimEvent.Type.KILL, victim.pos, credited, victim.id, KILL_SCORE if killer != null else 0.0, &"player"))


func damage_enemy(enemy: SimEnemy, amount: float, attacker_id: int, at: Vector3) -> void:
	enemy.health -= amount
	enemy.hurt_flash = 0.12
	add_event(SimEvent.make(SimEvent.Type.HIT, at, attacker_id, enemy.id, amount, enemy.def.id))
	if enemy.health > 0.0:
		return
	enemies.erase(enemy.id)
	if enemy.id == boss_id:
		boss_id = 0
	var killer: SimPlayer = players.get(attacker_id)
	if killer != null:
		killer.score += enemy.def.score
	add_event(SimEvent.make(SimEvent.Type.KILL, enemy.pos, attacker_id, enemy.id, enemy.def.score, enemy.def.id))
	_drop_loot(enemy)

	# ウェーブ進行
	wave_kills += 1
	if wave_kills >= wave_target:
		_advance_wave()


func spawn_enemy_at(def: EnemyDef, at: Vector3) -> SimEnemy:
	var enemy := SimEnemy.new()
	enemy.id = _allocate_id()
	enemy.def = def
	enemy.pos = Vector3(at.x, 0.0, at.z)
	enemy.prev_pos = enemy.pos
	enemy.health = def.max_health
	enemy.yaw = rng.range_float(0.0, TAU)
	enemy.prev_yaw = enemy.yaw
	enemy.strafe_sign = 1.0 if rng.chance(0.5) else -1.0
	enemy.avoid_sign = 1.0 if rng.chance(0.5) else -1.0
	enemy.retarget_cd = rng.range_float(0.0, SimConfig.DT * 18.0)
	enemies[enemy.id] = enemy
	add_event(SimEvent.make(SimEvent.Type.ENEMY_SPAWN, enemy.pos, enemy.id, 0, 0.0, def.id))
	return enemy


func alive_player_count() -> int:
	var count := 0
	for p: SimPlayer in players.values():
		if p.alive:
			count += 1
	return count


# --- 内部 ---

func _handle_player_flags(p: SimPlayer, input: PlayerInput, flags: int) -> void:
	if flags & PlayerSim.EV_JUMP:
		add_event(SimEvent.make(SimEvent.Type.JUMP, p.pos, p.id))
	if flags & PlayerSim.EV_LAND:
		add_event(SimEvent.make(SimEvent.Type.LAND, p.pos, p.id))
	if flags & PlayerSim.EV_DASH:
		add_event(SimEvent.make(SimEvent.Type.DASH, p.pos, p.id))
	if flags & PlayerSim.EV_FIRE:
		for shot in PlayerSim.build_shots(p, input.seq):
			spawn_projectile(shot)
		add_event(SimEvent.make(SimEvent.Type.SHOT, p.muzzle_position(), p.id, 0, 0.0, p.stats.weapon_kind))


func _step_projectiles(dt: float) -> void:
	for id in projectiles.keys():
		var pr: SimProjectile = projectiles[id]
		pr.prev_pos = pr.pos
		pr.life -= dt
		var from := pr.pos
		var to := from + pr.vel * dt
		var alive := true
		var guard := 0
		while alive and guard < 8:
			guard += 1
			var best_t := 2.0
			var best_key := -1
			var best_enemy: SimEnemy = null
			var best_player: SimPlayer = null
			var reach := from.distance_to(to) * 0.5
			var middle := (from + to) * 0.5

			if pr.owner_kind == SimProjectile.Owner.PLAYER:
				for e: SimEnemy in enemies.values():
					var key := 1000000000 + e.id
					if pr.hit_keys.has(key) or _too_far(middle, reach + e.def.radius, e.pos):
						continue
					var t := SimMath.segment_vs_cylinder(from, to, e.pos.x, e.pos.z, e.def.radius, e.pos.y, e.pos.y + e.def.height + EnemySim.HOVER_HEIGHT)
					if t >= 0.0 and t < best_t:
						best_t = t
						best_key = key
						best_enemy = e
						best_player = null
			if pr.owner_kind == SimProjectile.Owner.ENEMY or rules.pvp:
				for pl: SimPlayer in players.values():
					if not pl.alive or pr.hit_keys.has(pl.id):
						continue
					if pr.owner_kind == SimProjectile.Owner.PLAYER and pl.id == pr.owner_id:
						continue
					if _too_far(middle, reach + SimConfig.PLAYER_RADIUS, pl.pos):
						continue
					var t := SimMath.segment_vs_cylinder(from, to, pl.pos.x, pl.pos.z, SimConfig.PLAYER_RADIUS, pl.pos.y, pl.pos.y + pl.body_height())
					if t >= 0.0 and t < best_t:
						best_t = t
						best_key = pl.id
						best_player = pl
						best_enemy = null

			var t_world := Motion.segment_hit_geometry(geometry, from, to)
			if t_world >= 0.0 and t_world < best_t:
				add_event(SimEvent.make(SimEvent.Type.HIT_WORLD, from.lerp(to, t_world)))
				alive = false
			elif best_key >= 0:
				var hit_position := from.lerp(to, best_t)
				pr.hit_keys.append(best_key)
				if best_enemy != null:
					damage_enemy(best_enemy, pr.damage, pr.owner_id if pr.owner_kind == SimProjectile.Owner.PLAYER else 0, hit_position)
				elif best_player != null:
					damage_player(best_player, pr.damage, pr.owner_kind, pr.owner_id, hit_position)
				if pr.pierce_left > 0:
					pr.pierce_left -= 1
					from = hit_position
				else:
					alive = false
			else:
				break
		if alive and pr.life > 0.0:
			pr.pos = to
		else:
			projectiles.erase(id)


static func _too_far(middle: Vector3, limit: float, target: Vector3) -> bool:
	var dx := middle.x - target.x
	var dz := middle.z - target.z
	return dx * dx + dz * dz > limit * limit


func _step_pickups(dt: float) -> void:
	for id in pickups.keys():
		var pk: SimPickup = pickups[id]
		if pk.life >= 0.0:
			pk.life -= dt
			if pk.life < 0.0:
				pickups.erase(id)
				continue
		for p: SimPlayer in players.values():
			if not p.alive:
				continue
			var dx := p.pos.x - pk.pos.x
			var dz := p.pos.z - pk.pos.z
			if dx * dx + dz * dz > SimConfig.PICKUP_RADIUS * SimConfig.PICKUP_RADIUS:
				continue
			if absf(p.pos.y - pk.pos.y) > SimConfig.PICKUP_HEIGHT:
				continue
			if _collect(pk, p):
				pickups.erase(id)
				if pk.spot >= 0:
					_spot_timers[pk.spot] = rules.world_pickup_respawn
				break


## 拾えたら true（拾い物が消える）。体力・エネルギーが満タンなら拾わない
func _collect(pk: SimPickup, p: SimPlayer) -> bool:
	match pk.kind:
		SimPickup.Kind.PART:
			var part := Content.part(pk.part_id)
			if part == null:
				return true
			var is_new := not p.inventory.has(pk.part_id)
			p.inventory[pk.part_id] = true
			if is_new and not p.loadout.has_slot(part.get_slot()):
				equip_part(p.id, pk.part_id)
			elif not is_new:
				p.health = minf(p.stats.max_health, p.health + DUPLICATE_HEAL)
			add_event(SimEvent.make(SimEvent.Type.PICKUP, pk.pos, p.id, 0, 1.0 if is_new else 0.0, pk.part_id))
			return true
		SimPickup.Kind.HEALTH:
			if p.health >= p.stats.max_health - 0.5:
				return false
			p.health = minf(p.stats.max_health, p.health + ORB_HEAL)
			add_event(SimEvent.make(SimEvent.Type.PICKUP, pk.pos, p.id, 0, 0.0, &"health"))
			return true
		SimPickup.Kind.ENERGY:
			if p.energy >= p.stats.max_energy - 0.5:
				return false
			p.energy = minf(p.stats.max_energy, p.energy + ORB_ENERGY)
			add_event(SimEvent.make(SimEvent.Type.PICKUP, pk.pos, p.id, 0, 0.0, &"energy"))
			return true
	return true


func _step_spawners(dt: float) -> void:
	if wave_interval > 0.0:
		wave_interval = maxf(0.0, wave_interval - dt)
	if spawn_enemies and not players.is_empty() and wave_interval <= 0.0:
		_enemy_timer -= dt
		var wanted := mini(rules.enemy_max, rules.enemy_base + rules.enemy_per_player * (players.size() - 1))
		if _enemy_timer <= 0.0 and enemies.size() < wanted:
			_enemy_timer = rules.enemy_spawn_interval
			_spawn_random_enemy()
	for spot in _spot_timers.keys():
		_spot_timers[spot] -= dt
		if _spot_timers[spot] <= 0.0:
			_spot_timers.erase(spot)
			_spawn_world_pickup(spot)


func _advance_wave() -> void:
	wave_number += 1
	wave_kills = 0
	wave_target = 6 + wave_number * 3
	wave_interval = 4.0
	for p: SimPlayer in players.values():
		if p.alive:
			p.health = minf(p.stats.max_health, p.health + 35.0)
			p.energy = minf(p.stats.max_energy, p.energy + 45.0)
	# Wave 3 または 3 の倍数でボス出現
	if wave_number % 3 == 0:
		_spawn_boss()


func _spawn_boss() -> void:
	var def := Content.enemy(&"brute")
	if def == null:
		return
	var point := geometry.enemy_spawns[0] if not geometry.enemy_spawns.is_empty() else Vector3(0, 0, 8.0)
	var boss := spawn_enemy_at(def, point)
	boss.health = def.max_health * 3.0
	boss_id = boss.id


func _spawn_random_enemy() -> void:
	var def := _roll_enemy_def()
	if def == null:
		return
	# 生きているプレイヤーから十分離れた出現位置だけを候補にする
	var candidates: Array[Vector3] = []
	for point in geometry.enemy_spawns:
		var far_enough := true
		for p: SimPlayer in players.values():
			if p.alive and p.pos.distance_to(point) < rules.enemy_spawn_min_distance:
				far_enough = false
				break
		if far_enough:
			candidates.append(point)
	if candidates.is_empty():
		_enemy_timer = 0.5
		return
	spawn_enemy_at(def, rng.pick(candidates))


func _roll_enemy_def() -> EnemyDef:
	var total := 0.0
	var eligible: Array[EnemyDef] = []
	for def in Content.all_enemies():
		if time >= def.min_time and def.spawn_weight > 0.0:
			eligible.append(def)
			total += def.spawn_weight
	if eligible.is_empty():
		return null
	var roll := rng.next_float() * total
	for def in eligible:
		roll -= def.spawn_weight
		if roll <= 0.0:
			return def
	return eligible[eligible.size() - 1]


func _drop_loot(enemy: SimEnemy) -> void:
	var at := Vector3(enemy.pos.x, 0.0, enemy.pos.z)
	if rng.chance(enemy.def.drop_chance * rules.drop_scale):
		var part := Content.roll_part_drop(rng, enemy.def.rarity_bias)
		if part != null:
			_add_pickup(SimPickup.make_part(part, at, rules.pickup_lifetime))
			return
	if rng.chance(0.3):
		var orb_kind := SimPickup.Kind.HEALTH if rng.chance(0.5) else SimPickup.Kind.ENERGY
		_add_pickup(SimPickup.make_orb(orb_kind, at, rules.pickup_lifetime))


func _spawn_world_pickup(spot: int) -> void:
	var at := geometry.pickup_spots[spot]
	if rng.chance(0.25):
		var orb := SimPickup.Kind.HEALTH if rng.chance(0.5) else SimPickup.Kind.ENERGY
		_add_pickup(SimPickup.make_orb(orb, at, -1.0, spot))
		return
	var part := Content.roll_part_drop(rng, 1)
	if part == null:
		return
	_add_pickup(SimPickup.make_part(part, at, -1.0, spot))


func _add_pickup(pk: SimPickup) -> void:
	pk.id = _allocate_id()
	pickups[pk.id] = pk


## 他のプレイヤー・敵から最も遠い出現位置（同点は乱数で決める）
func _pick_player_spawn() -> Vector3:
	var best := geometry.player_spawns[0] if not geometry.player_spawns.is_empty() else Vector3.ZERO
	var best_score := -1.0
	for point in geometry.player_spawns:
		var nearest := 1000.0
		for p: SimPlayer in players.values():
			if p.alive:
				nearest = minf(nearest, p.pos.distance_to(point))
		for e: SimEnemy in enemies.values():
			nearest = minf(nearest, e.pos.distance_to(point))
		var score := nearest + rng.next_float() * 2.0
		if score > best_score:
			best_score = score
			best = point
	return best


func _allocate_id() -> int:
	var id := _next_id
	_next_id += 1
	return id
