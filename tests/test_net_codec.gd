extends TestCase
## ネットワークの部品: スナップショット/イベントの符号化、関連性、タグ番号、補間、時計の同期。


func _world() -> SimWorld:
	var rules := GameRules.new()
	rules.world_pickups = 0
	var world := SimWorld.new(rules, 9)
	world.spawn_enemies = false
	world.geometry = _open_geometry()
	return world


func _open_geometry() -> WorldGeometry:
	var geo := WorldGeometry.new(40.0)
	geo.finalize()
	return geo


func _entity(pos: Vector3, yaw: float = 0.0, kind: RenderFrame.Entity.Kind = RenderFrame.Entity.Kind.PLAYER) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = kind
	e.pos = pos
	e.yaw = yaw
	return e


# --- スナップショット ---

func test_snapshot_round_trip() -> void:
	var world := _world()
	var me := world.add_player(1, "A")
	me.pos = Vector3(2.0, 0.5, 3.0)
	me.vel = Vector3(1.0, 2.0, -2.5)
	me.yaw = 1.2
	me.energy = 55.5
	me.fire_cd = 0.1
	me.dash_time = 0.05
	me.dash_dir = Vector3(1, 0, 0)
	me.invuln = 0.0
	me.health = 77.7
	me.on_floor = false
	me.last_buttons = PlayerInput.BTN_FIRE
	var other := world.add_player(2, "B")
	other.pos = Vector3(5.0, 0.0, 3.0)
	other.yaw = 2.5
	other.health = other.stats.max_health * 0.5
	world.equip_part(2, &"eye_standard")
	var near_enemy := world.spawn_enemy_at(Content.enemy(&"gunner"), Vector3(4.0, 0, 5.0))
	near_enemy.yaw = 1.0
	near_enemy.health = near_enemy.def.max_health * 0.25
	near_enemy.state = SimEnemy.State.WINDUP
	world.spawn_enemy_at(Content.enemy(&"scout"), Vector3(-30.0, 0, -30.0))
	world.spawn_projectile(SimProjectile.make(SimProjectile.Owner.PLAYER, 2, &"rail", Vector3(3, 1.2, 3), Vector3(30, 0, 5), 1.0, 10.0, 0))
	world._add_pickup(SimPickup.make_part(Content.part(&"arms_rail"), Vector3(3, 0, 4), 30.0))
	world.tick = 777

	var snap := SnapshotCodec.decode(SnapshotCodec.encode(world, me, 1234))
	assert_not_null(snap)
	assert_eq(snap.tick, 777)
	assert_eq(snap.ack_seq, 1234)
	assert_not_null(snap.own)
	assert_vec3_near(snap.own.pos, me.pos, 1e-5)
	assert_vec3_near(snap.own.vel, me.vel, 1e-5)
	assert_near(snap.own.yaw, me.yaw, 1e-5)
	assert_near(snap.own.energy, 55.5, 1e-3)
	assert_near(snap.own.health, 77.7, 1e-3)
	assert_near(snap.own.dash_time, 0.05, 1e-6)
	assert_false(snap.own.on_floor)
	assert_true(snap.own.alive)
	assert_eq(snap.own.last_buttons, PlayerInput.BTN_FIRE)
	assert_eq(snap.own_loadout, me.loadout.to_indices())

	assert_eq(snap.players.size(), 1, "other player only")
	var p := snap.players[0]
	assert_eq(p.id, 2)
	assert_vec3_near(p.pos, other.pos, 1.0 / 64.0)
	assert_near(SimMath.wrap_angle(p.yaw - other.yaw), 0.0, 1e-3)
	assert_near(p.health_fraction, 0.5, 0.01)
	assert_eq(p.loadout, other.loadout.to_indices())

	assert_eq(snap.enemies.size(), 1, "the far enemy is not sent")
	var e := snap.enemies[0]
	assert_eq(e.type_id, &"gunner")
	assert_eq(e.state, SimEnemy.State.WINDUP)
	assert_near(e.pos.x, 4.0, 1.0 / 64.0)
	assert_near(e.health_fraction, 0.25, 0.01)

	assert_eq(snap.projectiles.size(), 1)
	assert_eq(snap.projectiles[0].type_id, &"rail")
	assert_eq(snap.projectiles[0].state, 2, "owner id")
	assert_near(snap.projectiles[0].velocity.x, 30.0, 0.2)

	assert_eq(snap.pickups.size(), 1)
	assert_eq(snap.pickups[0].type_id, &"arms_rail")


func test_snapshot_without_recipient_includes_everything() -> void:
	var world := _world()
	world.add_player(1, "A").pos = Vector3(-30, 0, -30)
	world.spawn_enemy_at(Content.enemy(&"scout"), Vector3(30, 0, 30))
	var snap := SnapshotCodec.decode(SnapshotCodec.encode(world, null, 0))
	assert_null(snap.own)
	assert_eq(snap.players.size(), 1)
	assert_eq(snap.enemies.size(), 1)


func test_relevance_follows_the_eyes() -> void:
	var world := _world()
	var me := world.add_player(1, "A")
	me.pos = Vector3.ZERO
	var radius := Relevance.radius_for(me)
	assert_near(radius, 7.0 * 1.15 + Relevance.MARGIN, 1e-4, "standard eye: 7m")
	var def := Content.enemy(&"scout")
	world.spawn_enemy_at(def, Vector3(radius - 1.0, 0, 0))
	world.spawn_enemy_at(def, Vector3(radius + 3.0, 0, 0))
	assert_eq(SnapshotCodec.decode(SnapshotCodec.encode(world, me, 0)).enemies.size(), 1)

	world.unequip_slot(1, RobotPart.Slot.EYES)
	assert_near(Relevance.radius_for(me), Relevance.MIN_RADIUS * 1.15 + Relevance.MARGIN, 1e-4, "blind: minimum radius")
	assert_eq(SnapshotCodec.decode(SnapshotCodec.encode(world, me, 0)).enemies.size(), 0, "blind players see nothing far away")

	world.grant_part(1, &"eye_oracle")
	world.equip_part(1, &"eye_oracle")
	assert_eq(SnapshotCodec.decode(SnapshotCodec.encode(world, me, 0)).enemies.size(), 2, "oracle sees both")


func test_dead_and_invulnerable_flags_survive() -> void:
	var world := _world()
	var me := world.add_player(1, "A")
	var other := world.add_player(2, "B")
	other.pos = Vector3(3, 0, 0)
	other.alive = false
	other.invuln = 1.0
	other.dash_time = 0.1
	var p := SnapshotCodec.decode(SnapshotCodec.encode(world, me, 0)).players[0]
	assert_false(p.alive)
	assert_true(p.flags & RenderFrame.Entity.FLAG_INVULN != 0)
	assert_true(p.flags & RenderFrame.Entity.FLAG_DASHING != 0)


func test_snapshot_stays_small_for_a_busy_arena() -> void:
	var world := _world()
	var me := world.add_player(1, "A", null, ["eye_oracle"])
	world.equip_part(1, &"eye_oracle")
	me.pos = Vector3.ZERO
	for i in 15:
		world.add_player(2 + i, "P%d" % i).pos = Vector3(float(i % 5) - 2.0, 0, float(i / 5) - 1.0)
	for i in 24:
		world.spawn_enemy_at(Content.enemy(&"scout"), Vector3(float(i % 6) - 3.0, 0, float(i / 6) * 2.0 + 3.0))
	for i in 60:
		world.spawn_projectile(SimProjectile.make(SimProjectile.Owner.ENEMY, 1, &"enemy", Vector3(float(i % 10) * 0.3, 1, 2), Vector3(5, 0, 0), 1.0, 1.0, 0))
	var bytes := SnapshotCodec.encode(world, me, 0)
	var snap := SnapshotCodec.decode(bytes)
	assert_eq(snap.players.size(), 15)
	assert_eq(snap.enemies.size(), 24)
	assert_eq(snap.projectiles.size(), 60)
	print("    busy snapshot: %d bytes (%d players, %d enemies, %d projectiles)" % [bytes.size(), 15, 24, 60])
	assert_true(bytes.size() < 2200, "size %d" % bytes.size())


func test_decode_rejects_wrong_format_and_empty() -> void:
	assert_null(SnapshotCodec.decode(PackedByteArray()))
	var bytes := PackedByteArray([99, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	assert_null(SnapshotCodec.decode(bytes))


# --- イベント ---

func test_events_round_trip() -> void:
	var events: Array[SimEvent] = [
		SimEvent.make(SimEvent.Type.SHOT, Vector3(1.5, 1.0, -2.0), 7, 0, 0.0, &"rail"),
		SimEvent.make(SimEvent.Type.HIT, Vector3(3.0, 1.0, 3.0), 7, 9, 12.5, &"scout"),
		SimEvent.make(SimEvent.Type.KILL, Vector3(0, 0, 0), 7, 3, 50.0, &"player"),
		SimEvent.make(SimEvent.Type.PICKUP, Vector3(-4, 0, 4), 7, 0, 1.0, &"core_singularity"),
	]
	var decoded := SnapshotCodec.decode_events(SnapshotCodec.encode_events(events))
	assert_eq(decoded.size(), 4)
	for i in events.size():
		assert_eq(decoded[i].type, events[i].type)
		assert_eq(decoded[i].a, events[i].a)
		assert_eq(decoded[i].b, events[i].b)
		assert_eq(decoded[i].tag, events[i].tag)
		assert_near(decoded[i].value, events[i].value, 1e-5)
		assert_vec3_near(decoded[i].pos, events[i].pos, 1.0 / 64.0)


func test_event_relevance() -> void:
	var world := _world()
	var me := world.add_player(1, "A")
	me.pos = Vector3.ZERO
	var near := SimEvent.make(SimEvent.Type.SHOT, Vector3(4, 0, 0), 2)
	var far := SimEvent.make(SimEvent.Type.SHOT, Vector3(35, 0, 0), 2)
	var far_but_mine := SimEvent.make(SimEvent.Type.HIT, Vector3(35, 0, 0), 2, 1)
	var far_kill := SimEvent.make(SimEvent.Type.KILL, Vector3(35, 0, 0), 2, 3)
	assert_true(SnapshotCodec.event_is_relevant(near, me))
	assert_false(SnapshotCodec.event_is_relevant(far, me))
	assert_true(SnapshotCodec.event_is_relevant(far_but_mine, me), "events about me always arrive")
	assert_true(SnapshotCodec.event_is_relevant(far_kill, me), "kills are announced to everyone")
	assert_true(SnapshotCodec.event_is_relevant(far, null))


func test_tag_table_covers_content_and_is_unique() -> void:
	var seen := {}
	for part in Content.all_parts():
		var index := TagTable.index_of(part.id)
		assert_ne(index, 0, "part %s has a tag" % part.id)
		assert_false(seen.has(index), "duplicate tag index")
		seen[index] = true
		assert_eq(TagTable.at(index), part.id)
		if part is ArmPart:
			assert_ne(TagTable.index_of(part.weapon_kind), 0, "weapon %s" % part.weapon_kind)
	for enemy in Content.all_enemies():
		assert_eq(TagTable.at(TagTable.index_of(enemy.id)), enemy.id)
	for tag in [&"player", &"health", &"energy", &"enemy"]:
		assert_eq(TagTable.at(TagTable.index_of(tag)), tag)
	assert_eq(TagTable.index_of(&"no_such_tag"), 0)
	assert_eq(TagTable.at(250), &"")


# --- 補間 ---

func test_interpolation_midpoint_and_yaw_wrap() -> void:
	var buffer := InterpolationBuffer.new()
	buffer.push(1.0, _entity(Vector3(0, 0, 0), deg_to_rad(350.0)))
	buffer.push(2.0, _entity(Vector3(10, 0, 0), deg_to_rad(10.0)))
	var mid := buffer.sample_at(1.5)
	assert_vec3_near(mid.pos, Vector3(5, 0, 0), 1e-4)
	assert_near(absf(SimMath.wrap_angle(mid.yaw)), 0.0, 1e-3, "350° → 10° goes through 0°, not 180°")
	assert_vec3_near(buffer.sample_at(1.25).pos, Vector3(2.5, 0, 0), 1e-4)


func test_interpolation_clamps_before_and_extrapolates_after() -> void:
	var buffer := InterpolationBuffer.new()
	buffer.push(1.0, _entity(Vector3(0, 0, 0)))
	buffer.push(2.0, _entity(Vector3(10, 0, 0)))
	assert_vec3_near(buffer.sample_at(0.0).pos, Vector3(0, 0, 0), 1e-4, "before the first sample")
	# 最後の速度（10 m/s）で外挿。上限を超えて先へは進まない
	assert_vec3_near(buffer.sample_at(2.1).pos, Vector3(11, 0, 0), 1e-3)
	assert_vec3_near(buffer.sample_at(9.0).pos, Vector3(10.0 + 10.0 * InterpolationBuffer.MAX_EXTRAPOLATION, 0, 0), 1e-3)


func test_interpolation_ignores_old_and_duplicate_samples() -> void:
	var buffer := InterpolationBuffer.new()
	buffer.push(2.0, _entity(Vector3(10, 0, 0)))
	buffer.push(1.0, _entity(Vector3(0, 0, 0)))
	buffer.push(2.0, _entity(Vector3(99, 0, 0)))
	assert_eq(buffer.count(), 1)
	assert_vec3_near(buffer.sample_at(2.0).pos, Vector3(10, 0, 0))
	assert_null(InterpolationBuffer.new().sample_at(1.0))


func test_interpolation_keeps_discrete_values_from_the_newer_sample() -> void:
	var buffer := InterpolationBuffer.new()
	var a := _entity(Vector3.ZERO)
	a.alive = true
	var b := _entity(Vector3(1, 0, 0))
	b.alive = false
	buffer.push(0.0, a)
	buffer.push(1.0, b)
	assert_true(buffer.sample_at(0.3).alive)
	assert_false(buffer.sample_at(0.7).alive)


func test_interpolation_uses_projectile_velocity_for_extrapolation() -> void:
	var buffer := InterpolationBuffer.new()
	var e := _entity(Vector3(0, 1, 0), 0.0, RenderFrame.Entity.Kind.PROJECTILE)
	e.velocity = Vector3(20, 0, 0)
	buffer.push(1.0, e)
	assert_vec3_near(buffer.sample_at(1.1).pos, Vector3(2, 1, 0), 1e-3)


func test_interpolation_buffer_is_bounded() -> void:
	var buffer := InterpolationBuffer.new()
	for i in 100:
		buffer.push(float(i), _entity(Vector3.ZERO))
	assert_true(buffer.count() <= InterpolationBuffer.MAX_SAMPLES)


# --- 時計 ---

func test_clock_sync_tracks_the_lowest_latency() -> void:
	var clock := ClockSync.new()
	assert_false(clock.is_ready())
	# 本当のオフセットは 100。通信の遅れは 30〜80ms で揺れる → 観測値は 100 - 遅れ
	var delays := [0.08, 0.05, 0.03, 0.06, 0.08, 0.04, 0.03, 0.07, 0.05, 0.03]
	for round in 20:
		for delay in delays:
			var local := float(round) * 0.5
			clock.observe(local + 100.0 - delay, local)
	assert_true(clock.is_ready())
	assert_near(clock.offset, 100.0 - 0.03, 0.02, "converges near the fastest packets")
	assert_near(clock.server_time(5.0), 105.0 - 0.03, 0.02)
