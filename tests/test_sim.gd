extends TestCase
## シミュレーション: 入力の量子化、衝突、アリーナ生成、プレイヤーの移動と戦闘、敵AI、拾い物。

const DT := SimConfig.DT


# --- 補助 ---

func _geo_with(boxes: Array = []) -> WorldGeometry:
	var geo := WorldGeometry.new(20.0)
	# 外周の壁（Motion は外へ出ないよう丸めるが、弾のテストのために壁も置く）
	for b in boxes:
		geo.add_box(b[0], b[1], b[2], b[3], b[4])
	geo.finalize()
	return geo


func _player(geo: WorldGeometry, parts: Array = []) -> SimPlayer:
	var p := SimPlayer.new()
	p.id = 1
	var loadout := Loadout.new()
	for part in Content.starter_parts():
		loadout.equip(part)
	for id in parts:
		loadout.equip(Content.part(id))
	p.set_loadout(loadout)
	p.respawn(Vector3.ZERO, 0.0)
	return p


func _input(seq: int, move: Vector2 = Vector2.ZERO, buttons: int = 0, yaw: float = 0.0) -> PlayerInput:
	var input := PlayerInput.new()
	input.seq = seq
	input.move = move
	input.buttons = buttons
	input.aim_yaw = yaw
	return input.quantize()


func _quiet_world(seed_value: int = 1) -> SimWorld:
	var rules := GameRules.new()
	rules.world_pickups = 0
	var world := SimWorld.new(rules, seed_value)
	world.spawn_enemies = false
	return world


func _run(world: SimWorld, ticks: int, inputs: Dictionary = {}) -> void:
	for i in ticks:
		world.step(inputs)


# --- PlayerInput ---

func test_input_quantize_is_idempotent() -> void:
	var input := PlayerInput.new()
	input.move = Vector2(0.7071, -0.7071)
	input.aim_yaw = 1.2345
	input.quantize()
	var once := input.duplicate_input()
	input.quantize()
	assert_eq(input.move, once.move)
	assert_eq(input.aim_yaw, once.aim_yaw)


func test_input_wire_roundtrip_is_exact_after_quantize() -> void:
	var input := _input(123456, Vector2(0.5, -1.0), PlayerInput.BTN_FIRE | PlayerInput.BTN_JUMP, 4.4)
	var buffer := StreamPeerBuffer.new()
	input.encode(buffer)
	assert_eq(buffer.get_size(), PlayerInput.WIRE_SIZE)
	buffer.seek(0)
	var decoded := PlayerInput.decode(buffer)
	assert_eq(decoded.seq, 123456)
	assert_eq(decoded.move, input.move)
	assert_eq(decoded.aim_yaw, input.aim_yaw, "client and server must see the same yaw")
	assert_eq(decoded.buttons, input.buttons)


func test_input_yaw_wraps() -> void:
	var a := _input(1, Vector2.ZERO, 0, -1.0)
	var b := _input(1, Vector2.ZERO, 0, TAU - 1.0)
	assert_near(a.aim_yaw, b.aim_yaw, 1e-3)


func test_sim_math_forward_and_yaw_are_inverse() -> void:
	for yaw in [0.0, 0.5, 2.0, -1.3, 3.0]:
		assert_near(SimMath.wrap_angle(SimMath.yaw_of(SimMath.forward(yaw)) - yaw), 0.0, 1e-5)
	assert_vec3_near(SimMath.forward(0.0), Vector3(0, 0, -1))


# --- 衝突 ---

func test_circle_is_stopped_by_tall_box() -> void:
	var geo := _geo_with([[2.0, -2.0, 3.0, 2.0, 3.0]])
	var pos := Motion.move_circle(geo, Vector3(0, 0, 0), Vector2(5.0, 0.0), 0.4)
	assert_near(pos.x, 2.0 - 0.4, 1e-3)


func test_circle_slides_along_wall() -> void:
	var geo := _geo_with([[2.0, -5.0, 3.0, 5.0, 3.0]])
	var pos := Motion.move_circle(geo, Vector3(1.0, 0, 0), Vector2(2.0, 1.5), 0.4)
	assert_near(pos.x, 2.0 - 0.4, 1e-3, "blocked in x")
	assert_near(pos.z, 1.5, 1e-3, "slides in z")


func test_circle_steps_over_low_ledge() -> void:
	var geo := _geo_with([[2.0, -2.0, 3.0, 2.0, 0.2]])
	var pos := Motion.move_circle(geo, Vector3(0, 0, 0), Vector2(4.0, 0.0), 0.4)
	assert_near(pos.x, 4.0, 1e-3, "0.2m ledge is walkable")


func test_circle_does_not_tunnel_at_dash_speed() -> void:
	var geo := _geo_with([[3.0, -2.0, 3.8, 2.0, 3.0]])
	var pos := Vector3(0, 0, 0)
	for i in 60:
		pos = Motion.move_circle(geo, pos, Vector2(24.0 * DT, 0.0), 0.4)
	assert_true(pos.x < 3.0, "stayed on the near side (x=%.2f)" % pos.x)


func test_circle_inside_box_is_ejected() -> void:
	var geo := _geo_with([[0.0, 0.0, 4.0, 4.0, 3.0]])
	var pos := Motion.move_circle(geo, Vector3(0.5, 0, 2.0), Vector2.ZERO, 0.4)
	assert_true(pos.x < 0.0 or pos.x > 4.0 or pos.z < 0.0 or pos.z > 4.0, "ended outside the box: %s" % pos)


func test_circle_is_kept_inside_arena() -> void:
	var geo := _geo_with()
	var pos := Motion.move_circle(geo, Vector3(19, 0, 0), Vector2(10, 0), 0.4)
	assert_near(pos.x, 20.0 - 0.4, 1e-3)


func test_support_height_on_box_top() -> void:
	var geo := _geo_with([[0.0, 0.0, 4.0, 4.0, 0.25], [6.0, 0.0, 10.0, 4.0, 1.5]])
	assert_near(Motion.support_height(geo, Vector3(2, 0, 2), 0.4), 0.25, 1e-5, "step-high box is standable")
	assert_near(Motion.support_height(geo, Vector3(8, 0, 2), 0.4), 0.0, 1e-5, "tall box is not (feet too low)")
	assert_near(Motion.support_height(geo, Vector3(8, 1.5, 2), 0.4), 1.5, 1e-5, "standing at its top height")
	assert_near(Motion.support_height(geo, Vector3(-5, 0, -5), 0.4), 0.0, 1e-5)


func test_segment_hits_tall_box_and_passes_over_low_box() -> void:
	var geo := _geo_with([[4.0, -1.0, 5.0, 1.0, 3.0], [8.0, -1.0, 9.0, 1.0, 0.8]])
	var t := Motion.segment_hit_geometry(geo, Vector3(0, 1.4, 0), Vector3(6, 1.4, 0))
	assert_near(t, 4.0 / 6.0, 1e-4, "entry of the tall box")
	assert_true(Motion.segment_hit_geometry(geo, Vector3(6.5, 1.4, 0), Vector3(12, 1.4, 0)) < 0.0, "flies over the 0.8m box")
	assert_true(Motion.segment_hit_geometry(geo, Vector3(6.5, 0.5, 0), Vector3(12, 0.5, 0)) >= 0.0, "a low shot is blocked")
	assert_true(Motion.segment_hit_geometry(geo, Vector3(0, 1.4, 5), Vector3(10, 1.4, 5)) < 0.0, "misses to the side")


func test_segment_starting_inside_box_hits_at_zero() -> void:
	var geo := _geo_with([[0.0, 0.0, 4.0, 4.0, 3.0]])
	assert_near(Motion.segment_hit_geometry(geo, Vector3(2, 1, 2), Vector3(8, 1, 2)), 0.0, 1e-6)


func test_segment_vs_cylinder() -> void:
	assert_near(SimMath.segment_vs_cylinder(Vector3(-5, 1, 0), Vector3(5, 1, 0), 0, 0, 1.0, 0.0, 2.0), 0.4, 1e-4)
	assert_true(SimMath.segment_vs_cylinder(Vector3(-5, 3, 0), Vector3(5, 3, 0), 0, 0, 1.0, 0.0, 2.0) < 0.0, "above the cylinder")
	assert_true(SimMath.segment_vs_cylinder(Vector3(-5, 1, 3), Vector3(5, 1, 3), 0, 0, 1.0, 0.0, 2.0) < 0.0, "passes beside")
	assert_true(SimMath.segment_vs_cylinder(Vector3(-5, 1, 0), Vector3(-2, 1, 0), 0, 0, 1.0, 0.0, 2.0) < 0.0, "stops short")
	assert_near(SimMath.segment_vs_cylinder(Vector3(0, 1, 0), Vector3(5, 1, 0), 0, 0, 1.0, 0.0, 2.0), 0.0, 1e-6, "starts inside")


# --- アリーナ ---

func test_arena_is_deterministic() -> void:
	var rules := GameRules.new()
	var a := ArenaGenerator.generate(777, rules)
	var b := ArenaGenerator.generate(777, rules)
	assert_eq(a.box_count, b.box_count)
	assert_eq(a.box_data, b.box_data)
	assert_eq(a.player_spawns, b.player_spawns)
	assert_eq(a.pickup_spots, b.pickup_spots)


func test_arena_differs_by_seed_and_has_cover() -> void:
	var rules := GameRules.new()
	var a := ArenaGenerator.generate(1, rules)
	var b := ArenaGenerator.generate(2, rules)
	assert_ne(a.box_data, b.box_data)
	assert_true(a.box_count >= 4 + rules.cover_count / 2, "walls + a reasonable amount of cover (%d)" % a.box_count)


func test_arena_spawn_points_are_free_and_inside() -> void:
	for seed_value in [1, 2, 3, 99, 12345]:
		var geo := ArenaGenerator.generate(seed_value, GameRules.new())
		assert_eq(geo.player_spawns.size(), 8)
		assert_eq(geo.enemy_spawns.size(), 12)
		for point in geo.player_spawns:
			assert_true(geo.is_free(point.x, point.z, SimConfig.PLAYER_RADIUS), "player spawn %s (seed %d)" % [point, seed_value])
		for point in geo.enemy_spawns:
			assert_true(geo.is_free(point.x, point.z, 0.7), "enemy spawn %s (seed %d)" % [point, seed_value])
		for point in geo.pickup_spots:
			assert_true(geo.is_free(point.x, point.z, 0.5), "pickup spot %s" % point)


func test_arena_center_is_clear() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		assert_true(ArenaGenerator.generate(seed_value, GameRules.new()).is_free(0, 0, 2.0))


# --- プレイヤーの移動 ---

func test_player_accelerates_to_move_speed() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	for i in 120:
		PlayerSim.step(p, _input(i, Vector2(0, -1)), geo)
	assert_near(p.vel.z, -p.stats.move_speed, 1e-3)
	assert_true(p.pos.z < -3.0)


func test_diagonal_is_not_faster_than_straight() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	for i in 120:
		PlayerSim.step(p, _input(i, Vector2(1, -1).normalized()), geo)
	assert_near(Vector2(p.vel.x, p.vel.z).length(), p.stats.move_speed, 0.05)


func test_oversized_input_is_clamped() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	var cheat := PlayerInput.new()
	cheat.move = Vector2(127.0 / 127.0, 127.0 / 127.0) * 5.0  # 改ざんされた入力
	for i in 120:
		cheat.seq = i
		PlayerSim.step(p, cheat, geo)
	assert_true(Vector2(p.vel.x, p.vel.z).length() <= p.stats.move_speed + 0.01, "speed %f" % Vector2(p.vel.x, p.vel.z).length())


func test_player_stops_without_input() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	for i in 60:
		PlayerSim.step(p, _input(i, Vector2(1, 0)), geo)
	for i in 60:
		PlayerSim.step(p, _input(100 + i), geo)
	assert_near(p.vel.length(), 0.0, 1e-3)


func test_jump_reaches_expected_height_and_lands() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	var peak := 0.0
	var landed := false
	for i in 120:
		var flags := PlayerSim.step(p, _input(i, Vector2.ZERO, PlayerInput.BTN_JUMP if i == 0 else 0), geo)
		peak = maxf(peak, p.pos.y)
		landed = landed or flags & PlayerSim.EV_LAND != 0
	var expected := p.stats.jump_velocity * p.stats.jump_velocity / (2.0 * SimConfig.GRAVITY)
	assert_near(peak, expected, 0.1)
	assert_true(landed)
	assert_true(p.on_floor)
	assert_near(p.pos.y, 0.0, 1e-4)


func test_no_jump_with_roller_legs() -> void:
	var geo := _geo_with()
	var p := _player(geo, [&"legs_roller"])
	PlayerSim.step(p, _input(0, Vector2.ZERO, PlayerInput.BTN_JUMP), geo)
	assert_true(p.on_floor)
	assert_near(p.pos.y, 0.0)


func test_jump_requires_a_fresh_press() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	var jumps := 0
	for i in 240:
		if PlayerSim.step(p, _input(i, Vector2.ZERO, PlayerInput.BTN_JUMP), geo) & PlayerSim.EV_JUMP:
			jumps += 1
	assert_eq(jumps, 1, "holding the button does not bunny-hop")


func test_can_jump_onto_low_cover_and_walk_off() -> void:
	var geo := _geo_with([[2.0, -2.0, 4.0, 2.0, 1.0]])
	var p := _player(geo)
	var seq := 0
	# 歩いて近づく → ジャンプ → 前進を続けて乗る
	for i in 40:
		seq += 1
		PlayerSim.step(p, _input(seq, Vector2(1, 0)), geo)
	for i in 80:
		seq += 1
		PlayerSim.step(p, _input(seq, Vector2(1, 0), PlayerInput.BTN_JUMP if i == 0 else 0), geo)
		if p.pos.y > 0.9 and p.on_floor:
			break
	assert_true(p.on_floor and absf(p.pos.y - 1.0) < 1e-3, "standing on top (y=%.2f, x=%.2f)" % [p.pos.y, p.pos.x])
	for i in 120:
		seq += 1
		PlayerSim.step(p, _input(seq, Vector2(1, 0)), geo)
	assert_near(p.pos.y, 0.0, 1e-3, "walked off and fell back to the floor")


func test_cannot_walk_through_tall_cover() -> void:
	var geo := _geo_with([[2.0, -2.0, 4.0, 2.0, 3.0]])
	var p := _player(geo)
	for i in 240:
		PlayerSim.step(p, _input(i, Vector2(1, 0)), geo)
	assert_true(p.pos.x < 2.0)
	assert_near(p.vel.x, 0.0, 1e-3, "velocity into the wall is dropped")


func test_dash_costs_energy_has_cooldown_and_moves_fast() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	var energy_before := p.energy
	var flags := PlayerSim.step(p, _input(1, Vector2(1, 0), PlayerInput.BTN_DASH), geo)
	assert_true(flags & PlayerSim.EV_DASH != 0)
	assert_true(p.energy < energy_before - p.stats.dash_cost + 1.0)
	assert_near(p.vel.x, p.stats.dash_speed, 1e-3)
	# 押しっぱなしでは連続ダッシュしない
	var dashes := 0
	for i in 30:
		if PlayerSim.step(p, _input(2 + i, Vector2(1, 0), PlayerInput.BTN_DASH), geo) & PlayerSim.EV_DASH:
			dashes += 1
	assert_eq(dashes, 0)


func test_dash_blocked_without_energy_or_legs() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	p.energy = 1.0
	p.stats.energy_regen = 0.0
	assert_eq(PlayerSim.step(p, _input(1, Vector2(1, 0), PlayerInput.BTN_DASH), geo) & PlayerSim.EV_DASH, 0)
	var legless := _player(geo)
	legless.loadout.unequip(RobotPart.Slot.LEGS)
	legless.recompute_stats()
	assert_eq(PlayerSim.step(legless, _input(1, Vector2(1, 0), PlayerInput.BTN_DASH), geo) & PlayerSim.EV_DASH, 0)


func test_fire_rate_matches_interval() -> void:
	var geo := _geo_with()
	var p := _player(geo, [&"arms_blaster"])
	p.stats.shot_cost = 0.0
	var shots := 0
	for i in 600:
		if PlayerSim.step(p, _input(i, Vector2.ZERO, PlayerInput.BTN_FIRE), geo) & PlayerSim.EV_FIRE:
			shots += 1
	var expected := 10.0 / p.stats.fire_interval
	assert_true(absf(float(shots) - expected) <= 1.5, "%d shots in 10s, expected ~%.1f" % [shots, expected])


func test_fire_is_limited_by_energy() -> void:
	var geo := _geo_with()
	var p := _player(geo, [&"arms_pulse"])
	p.stats.energy_regen = 0.0
	var shots := 0
	for i in 600:
		if PlayerSim.step(p, _input(i, Vector2.ZERO, PlayerInput.BTN_FIRE), geo) & PlayerSim.EV_FIRE:
			shots += 1
	assert_eq(shots, int(p.stats.max_energy / p.stats.shot_cost), "ran dry")


func test_no_arms_cannot_fire() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	p.loadout.unequip(RobotPart.Slot.ARMS)
	p.recompute_stats()
	assert_eq(PlayerSim.step(p, _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE), geo) & PlayerSim.EV_FIRE, 0)


func test_shots_are_reproducible_from_seq() -> void:
	var geo := _geo_with()
	var p := _player(geo, [&"arms_scatter"])
	var a := PlayerSim.build_shots(p, 77)
	var b := PlayerSim.build_shots(p, 77)
	var c := PlayerSim.build_shots(p, 78)
	assert_eq(a.size(), 6)
	for i in a.size():
		assert_eq(a[i].vel, b[i].vel)
	assert_ne(a[0].vel, c[0].vel)


func test_scatter_pellets_spread_within_cone() -> void:
	var geo := _geo_with()
	var p := _player(geo, [&"arms_scatter"])
	p.yaw = 0.0
	for shot in PlayerSim.build_shots(p, 5):
		var angle := absf(SimMath.wrap_angle(SimMath.yaw_of(shot.vel)))
		assert_true(angle <= p.stats.spread + 1e-4)
		assert_near(shot.vel.length(), p.stats.projectile_speed, 1e-3)


func test_player_sim_is_deterministic() -> void:
	var geo := ArenaGenerator.generate(5, GameRules.new())
	var rng := DetRng.new(3)
	var script: Array[PlayerInput] = []
	for i in 600:
		script.append(_input(i, Vector2(rng.next_signed(), rng.next_signed()).limit_length(1.0),
			int(rng.next_u32() % 8), rng.range_float(0.0, TAU)))
	var results: Array[Vector3] = []
	for run in 2:
		var p := _player(geo, [&"arms_pulse"])
		for input in script:
			PlayerSim.step(p, input, geo)
		results.append(p.pos)
	assert_eq(results[0], results[1])


func test_dead_player_does_nothing() -> void:
	var geo := _geo_with()
	var p := _player(geo)
	p.alive = false
	PlayerSim.step(p, _input(1, Vector2(1, 0), PlayerInput.BTN_FIRE | PlayerInput.BTN_DASH), geo)
	assert_vec3_near(p.pos, Vector3.ZERO)


# --- ワールド ---

func test_add_player_validates_loadout_against_inventory() -> void:
	var world := _quiet_world()
	var greedy := Loadout.new()
	greedy.equip(Content.part(&"arms_rail"))  # 持っていない
	var p := world.add_player(1, "A", greedy)
	assert_eq(p.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_blaster", "falls back to the starter")
	var q := world.add_player(2, "B", greedy, ["arms_rail"])
	assert_eq(q.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_rail", "owned part is kept")
	assert_eq(p.loadout.parts().size(), RobotPart.Slot.size(), "every slot is filled")


func test_equip_requires_ownership() -> void:
	var world := _quiet_world()
	world.add_player(1, "A")
	assert_false(world.equip_part(1, &"arms_rail"))
	assert_false(world.equip_part(1, &"no_such_part"))
	assert_false(world.equip_part(99, &"arms_blaster"))
	assert_true(world.grant_part(1, &"arms_rail"))
	assert_false(world.grant_part(1, &"arms_rail"), "already owned")
	assert_true(world.equip_part(1, &"arms_rail"))
	assert_eq(world.players[1].stats.pierce, 3)


func test_swapping_keeps_health_and_energy_ratio() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A", null, ["core_plate"])
	p.health = p.stats.max_health * 0.5
	world.equip_part(1, &"core_plate")
	assert_near(p.health / p.stats.max_health, 0.5, 0.01)


func test_player_projectile_damages_enemy_and_kills_for_score() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	p.pos = Vector3.ZERO
	world.geometry = _geo_with()
	var def := Content.enemy(&"scout")
	var enemy := world.spawn_enemy_at(def, Vector3(0, 0, -6))
	world.drain_events()
	var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE, 0.0)
	p.stats.weapon_damage = 100.0
	for i in 60:
		input.seq = i + 1
		world.step({1: input})
		if not world.enemies.has(enemy.id):
			break
	assert_false(world.enemies.has(enemy.id), "enemy died")
	assert_eq(p.score, def.score)
	var saw_kill := false
	for e in world.drain_events():
		saw_kill = saw_kill or (e.type == SimEvent.Type.KILL and e.a == 1 and e.tag == &"scout")
	assert_true(saw_kill, "kill event emitted")


func test_projectile_is_stopped_by_wall() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with([[-2.0, -8.0, 2.0, -7.0, 3.0]])
	var p := world.add_player(1, "A")
	p.pos = Vector3.ZERO
	var enemy := world.spawn_enemy_at(Content.enemy(&"brute"), Vector3(0, 0, -12))
	var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE, 0.0)
	for i in 90:
		input.seq = i + 1
		world.step({1: input})
	assert_near(enemy.health, enemy.def.max_health, 1e-4, "the wall absorbed everything")


func test_low_cover_does_not_stop_projectiles() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with([[-2.0, -8.0, 2.0, -7.0, 0.8]])
	var p := world.add_player(1, "A")
	p.pos = Vector3.ZERO
	var enemy := world.spawn_enemy_at(Content.enemy(&"brute"), Vector3(0, 0, -12))
	enemy.def = enemy.def.duplicate()
	var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE, 0.0)
	for i in 90:
		input.seq = i + 1
		world.step({1: input})
	assert_true(enemy.health < enemy.def.max_health, "shots flew over the low cover")


func test_pierce_hits_multiple_enemies_once_each() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var p := world.add_player(1, "A", null, ["arms_rail"])
	world.equip_part(1, &"arms_rail")
	p.pos = Vector3.ZERO
	var def := Content.enemy(&"brute")
	var first := world.spawn_enemy_at(def, Vector3(0, 0, -5))
	var second := world.spawn_enemy_at(def, Vector3(0, 0, -9))
	var third := world.spawn_enemy_at(def, Vector3(0, 0, -13))
	for e in [first, second, third]:
		e.retarget_cd = 99.0
	var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE, 0.0)
	world.step({1: input})
	for i in 20:
		world.step({})
	for e in [first, second, third]:
		assert_near(e.health, e.def.max_health - p.stats.weapon_damage, 1e-3, "hit exactly once")


func test_player_death_respawn_and_protection() -> void:
	var world := _quiet_world()
	world.rules.respawn_delay = 1.0
	world.rules.spawn_protection = 2.0
	var p := world.add_player(1, "A")
	world.damage_player(p, 9999.0, SimProjectile.Owner.ENEMY, 5, p.pos)
	assert_true(p.alive, "spawn protection absorbs the first hit")
	p.invuln = 0.0
	world.damage_player(p, 9999.0, SimProjectile.Owner.ENEMY, 5, p.pos)
	assert_false(p.alive)
	assert_eq(p.deaths, 1)
	_run(world, 70)
	assert_true(p.alive, "respawned after the delay")
	assert_near(p.health, p.stats.max_health)
	assert_true(p.invuln > 0.0, "spawn protection")
	var health := p.health
	world.damage_player(p, 50.0, SimProjectile.Owner.ENEMY, 5, p.pos)
	assert_near(p.health, health, 1e-6, "invulnerable right after respawn")


func test_armor_reduces_damage_but_not_below_ten_percent() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	p.invuln = 0.0
	p.stats.armor = 4.0
	var before := p.health
	world.damage_player(p, 10.0, SimProjectile.Owner.ENEMY, 0, p.pos)
	assert_near(before - p.health, 6.0, 1e-4)
	p.stats.armor = 999.0
	before = p.health
	world.damage_player(p, 10.0, SimProjectile.Owner.ENEMY, 0, p.pos)
	assert_near(before - p.health, 1.0, 1e-4, "10% floor")


func test_pvp_flag_controls_player_vs_player_hits() -> void:
	for pvp in [true, false]:
		var world := _quiet_world()
		world.rules.pvp = pvp
		world.geometry = _geo_with()
		var a := world.add_player(1, "A")
		var b := world.add_player(2, "B")
		a.pos = Vector3(0, 0, 0)
		b.pos = Vector3(0, 0, -6)
		a.invuln = 0.0
		b.invuln = 0.0
		var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE, 0.0)
		for i in 40:
			input.seq = i + 1
			world.step({1: input})
		assert_eq(b.health < b.stats.max_health, pvp, "pvp=%s" % pvp)
		assert_near(a.health, a.stats.max_health, 1e-6, "no self damage")


func test_killing_a_player_credits_the_killer() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var a := world.add_player(1, "A")
	var b := world.add_player(2, "B")
	a.pos = Vector3.ZERO
	b.pos = Vector3(0, 0, -5)
	a.invuln = 0.0
	b.invuln = 0.0
	b.health = 1.0
	var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE, 0.0)
	for i in 30:
		input.seq = i + 1
		world.step({1: input})
	assert_false(b.alive)
	assert_eq(a.kills, 1)
	assert_eq(a.score, SimWorld.KILL_SCORE)


func test_part_pickup_adds_to_inventory_and_equips_into_empty_slot() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	world.unequip_slot(1, RobotPart.Slot.ARMS)
	var part := Content.part(&"arms_scatter")
	var pk := SimPickup.make_part(part, p.pos, 30.0)
	world._add_pickup(pk)
	world.step({})
	assert_false(world.pickups.has(pk.id), "collected")
	assert_true(p.inventory.has(&"arms_scatter"))
	assert_eq(p.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_scatter", "auto-equipped into the empty slot")


func test_part_pickup_does_not_replace_a_filled_slot() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	world._add_pickup(SimPickup.make_part(Content.part(&"arms_scatter"), p.pos, 30.0))
	world.step({})
	assert_true(p.inventory.has(&"arms_scatter"))
	assert_eq(p.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_blaster")


func test_duplicate_part_heals_instead() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	p.health = 10.0
	world._add_pickup(SimPickup.make_part(Content.part(&"arms_blaster"), p.pos, 30.0))
	world.step({})
	assert_near(p.health, 10.0 + SimWorld.DUPLICATE_HEAL)


func test_orbs_are_left_alone_when_full() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	var orb := SimPickup.make_orb(SimPickup.Kind.HEALTH, p.pos, 30.0)
	world._add_pickup(orb)
	world.step({})
	assert_true(world.pickups.has(orb.id), "full health: not consumed")
	p.health = 20.0
	world.step({})
	assert_false(world.pickups.has(orb.id))
	assert_near(p.health, 20.0 + SimWorld.ORB_HEAL)


func test_pickups_expire() -> void:
	var world := _quiet_world()
	var pk := SimPickup.make_orb(SimPickup.Kind.ENERGY, Vector3(10, 0, 10), 0.5)
	world._add_pickup(pk)
	_run(world, 20)
	assert_true(world.pickups.has(pk.id), "still there after 0.33s")
	_run(world, 20)
	assert_false(world.pickups.has(pk.id), "gone after 0.67s")


func test_world_pickups_respawn_at_their_spot() -> void:
	var rules := GameRules.new()
	rules.world_pickup_respawn = 1.0
	var world := SimWorld.new(rules, 4)
	world.spawn_enemies = false
	var initial := world.pickups.size()
	assert_eq(initial, world.geometry.pickup_spots.size(), "one per spot")
	var p := world.add_player(1, "A")
	var victim: SimPickup = world.pickups.values()[0]
	p.pos = victim.pos
	p.health = 1.0
	p.energy = 0.0
	world.step({})
	assert_false(world.pickups.has(victim.id), "collected (parts always, orbs because we are hurt)")
	p.pos = Vector3(500, 0, 500)
	_run(world, 80)
	assert_eq(world.pickups.size(), initial, "respawned")


# --- 敵 ---

func test_chaser_closes_in_and_hurts_a_player() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var p := world.add_player(1, "A")
	p.pos = Vector3.ZERO
	p.invuln = 0.0
	var e := world.spawn_enemy_at(Content.enemy(&"scout"), Vector3(8, 0, 0))
	var start := e.pos.distance_to(p.pos)
	_run(world, 60)
	assert_true(e.pos.distance_to(p.pos) < start - 2.0, "approached")
	_run(world, 240)
	assert_true(p.health < p.stats.max_health, "took contact damage")


func test_enemies_ignore_players_out_of_aggro_range() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var p := world.add_player(1, "A")
	p.pos = Vector3(-18, 0, 0)
	var e := world.spawn_enemy_at(Content.enemy(&"scout"), Vector3(18, 0, 0))
	_run(world, 30)
	assert_eq(e.target_id, 0)
	assert_true(e.state in [SimEnemy.State.WANDER, SimEnemy.State.IDLE])


func test_shooter_fires_with_line_of_sight_and_not_through_walls() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var p := world.add_player(1, "A")
	p.pos = Vector3.ZERO
	p.invuln = 0.0
	world.spawn_enemy_at(Content.enemy(&"gunner"), Vector3(0, 0, -9))
	_run(world, 180)
	assert_true(p.health < p.stats.max_health, "gunner hit us in the open")

	var walled := _quiet_world()
	walled.geometry = _geo_with([[-6.0, -5.0, 6.0, -4.0, 4.0]])
	var q := walled.add_player(1, "A")
	q.pos = Vector3.ZERO
	q.invuln = 0.0
	var shooter := walled.spawn_enemy_at(Content.enemy(&"gunner"), Vector3(0, 0, -9))
	shooter.def = shooter.def.duplicate()
	shooter.def.move_speed = 0.0
	_run(walled, 180)
	assert_near(q.health, q.stats.max_health, 1e-6, "wall blocks the line of sight")


func test_charger_winds_up_then_charges_then_stuns() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var p := world.add_player(1, "A")
	p.pos = Vector3.ZERO
	p.invuln = 99.0
	var e := world.spawn_enemy_at(Content.enemy(&"brute"), Vector3(0, 0, -8))
	var seen: Dictionary = {}
	for i in 400:
		world.step({})
		seen[e.state] = true
	assert_true(seen.has(SimEnemy.State.WINDUP), "telegraphed")
	assert_true(seen.has(SimEnemy.State.CHARGE), "charged")
	assert_true(seen.has(SimEnemy.State.STUN), "recovered")


func test_enemy_dies_and_may_drop_loot() -> void:
	var world := _quiet_world()
	world.rules.drop_scale = 100.0
	var e := world.spawn_enemy_at(Content.enemy(&"brute"), Vector3(5, 0, 5))
	world.damage_enemy(e, 9999.0, 0, e.pos)
	assert_eq(world.enemies.size(), 0)
	assert_eq(world.pickups.size(), 1)
	assert_eq((world.pickups.values()[0] as SimPickup).kind, SimPickup.Kind.PART)


func test_enemy_spawner_respects_target_count_and_distance() -> void:
	var world := _quiet_world(8)
	world.spawn_enemies = true
	world.rules.enemy_base = 4
	world.rules.enemy_spawn_interval = 0.5
	var p := world.add_player(1, "A")
	p.invuln = 99.0
	_run(world, 60 * 12)
	assert_true(world.enemies.size() <= 4, "never more than the target (%d)" % world.enemies.size())
	assert_true(world.enemies.size() >= 3, "fills up over time (%d)" % world.enemies.size())
	world.add_player(2, "B")
	world.rules.enemy_per_player = 3
	_run(world, 60 * 12)
	assert_true(world.enemies.size() <= 7)
	assert_true(world.enemies.size() > 4, "more players, more enemies (%d)" % world.enemies.size())


func test_enemies_do_not_stack_on_each_other() -> void:
	var world := _quiet_world()
	world.geometry = _geo_with()
	var p := world.add_player(1, "A")
	p.pos = Vector3(10, 0, 0)
	p.invuln = 99.0
	var def := Content.enemy(&"scout")
	for i in 6:
		world.spawn_enemy_at(def, Vector3(-5.0 + 0.01 * i, 0, 0.01 * i))
	_run(world, 300)
	var list: Array = world.enemies.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			assert_true(list[i].pos.distance_to(list[j].pos) > def.radius * 1.2, "enemies %d and %d overlap" % [i, j])


func test_events_are_drained() -> void:
	var world := _quiet_world()
	var p := world.add_player(1, "A")
	var input := _input(1, Vector2.ZERO, PlayerInput.BTN_FIRE | PlayerInput.BTN_JUMP, 0.0)
	world.step({1: input})
	var drained := world.drain_events()
	var types: Dictionary = {}
	for e in drained:
		types[e.type] = true
	assert_true(types.has(SimEvent.Type.SHOT))
	assert_true(types.has(SimEvent.Type.JUMP))
	assert_eq(world.drain_events().size(), 0)
	assert_not_null(p)


# --- 通しのテスト ---

func test_soak_many_players_and_enemies_stays_sane() -> void:
	var rules := GameRules.new()
	rules.enemy_base = 12
	rules.enemy_spawn_interval = 0.3
	var world := SimWorld.new(rules, 21)
	var rng := DetRng.new(5)
	var ids := [1, 2, 3, 4, 5, 6]
	for id in ids:
		world.add_player(id, "P%d" % id, null, ["arms_pulse", "arms_scatter", "legs_roller"])
		world.equip_part(id, [&"arms_pulse", &"arms_scatter", &"arms_blaster"][id % 3])
	var started := Time.get_ticks_usec()
	var ticks := 60 * 30
	var seq := 0
	var held: Dictionary = {}
	for tick in ticks:
		seq += 1
		var inputs := {}
		for id in ids:
			if tick % 20 == 0 or not held.has(id):
				held[id] = _input(seq, Vector2(rng.next_signed(), rng.next_signed()).limit_length(1.0),
					int(rng.next_u32() % 8), rng.range_float(0.0, TAU))
			var input: PlayerInput = held[id].duplicate_input()
			input.seq = seq
			inputs[id] = input
		world.step(inputs)
		world.drain_events()
	var per_tick_ms := float(Time.get_ticks_usec() - started) / 1000.0 / float(ticks)
	print("    soak: %.2f ms/tick avg (%d enemies, %d projectiles at end)" % [per_tick_ms, world.enemies.size(), world.projectiles.size()])
	assert_true(per_tick_ms < 8.0, "the simulation must fit in the 16.7ms tick budget (%.2f ms)" % per_tick_ms)
	var limit := rules.arena_half_size + 0.001
	for p: SimPlayer in world.players.values():
		assert_true(is_finite(p.pos.x) and is_finite(p.pos.y) and is_finite(p.pos.z), "player position finite")
		assert_true(absf(p.pos.x) <= limit and absf(p.pos.z) <= limit, "player inside the arena")
		assert_true(p.health <= p.stats.max_health + 0.001 and p.energy <= p.stats.max_energy + 0.001)
		assert_true(p.energy >= -0.001)
	for e: SimEnemy in world.enemies.values():
		assert_true(is_finite(e.pos.x) and is_finite(e.pos.z))
		assert_true(absf(e.pos.x) <= limit and absf(e.pos.z) <= limit, "enemy inside the arena")
		assert_true(e.health > 0.0)
	assert_true(world.projectiles.size() < 400, "projectiles are cleaned up")
