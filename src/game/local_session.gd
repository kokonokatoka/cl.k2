class_name LocalSession
extends GameSession
## ソロ。ローカルの SimWorld が権威で、毎物理ティックに 1 ティック進める。
## 進行（拾ったパーツ・戦績）はプロフィール（Save）に反映する。

var world: SimWorld

var _seq: int = 0
var _god: bool = false


func start(seed_value: int, game_rules: GameRules, display_name: String) -> void:
	rules = game_rules
	world = SimWorld.new(rules, seed_value)
	geometry = world.geometry
	local_id = 1
	var owned: Array = []
	for part in Save.unlocked_parts():
		owned.append(part.id)
	local_player = world.add_player(local_id, display_name, Save.last_loadout(), owned)
	Save.add_stat("matches")
	Log.info("session", "solo started (seed %d, %d parts owned)" % [seed_value, local_player.inventory.size()])
	ready_to_play.emit()


func _physics_process(_delta: float) -> void:
	if paused or world == null:
		return
	_seq += 1
	var input: PlayerInput = null
	if input_provider.is_valid():
		input = input_provider.call(_seq)
	if input == null:
		input = PlayerInput.new()
	input.seq = _seq
	input.quantize()
	world.step({local_id: input})
	if _god:
		local_player.health = local_player.stats.max_health
		local_player.energy = local_player.stats.max_energy
	for event in world.drain_events():
		_track_progress(event)
		sim_event.emit(event)
	Save.add_stat("playtime", SimConfig.DT)
	Save.record_best("best_score", local_player.score)


func sample(alpha: float) -> RenderFrame:
	var frame := RenderFrame.new()
	if world == null:
		return frame
	for p: SimPlayer in world.players.values():
		var entity := make_player_entity(p, alpha, local_id)
		frame.players.append(entity)
		if entity.is_local:
			frame.local = entity
	for e: SimEnemy in world.enemies.values():
		var entity := RenderFrame.Entity.new()
		entity.kind = RenderFrame.Entity.Kind.ENEMY
		entity.id = e.id
		entity.pos = e.prev_pos.lerp(e.pos, alpha)
		entity.yaw = lerp_angle(e.prev_yaw, e.yaw, alpha)
		entity.velocity = e.vel
		entity.type_id = e.def.id
		entity.state = e.state
		entity.health_fraction = e.health_fraction()
		if e.hurt_flash > 0.0:
			entity.flags |= RenderFrame.Entity.FLAG_HURT
		frame.enemies.append(entity)
	for pr: SimProjectile in world.projectiles.values():
		var entity := RenderFrame.Entity.new()
		entity.kind = RenderFrame.Entity.Kind.PROJECTILE
		entity.id = pr.id
		entity.pos = pr.prev_pos.lerp(pr.pos, alpha)
		entity.velocity = pr.vel
		entity.yaw = SimMath.yaw_of(pr.vel)
		entity.type_id = pr.weapon_kind
		entity.owned_by_local = pr.owner_kind == SimProjectile.Owner.PLAYER and pr.owner_id == local_id
		frame.projectiles.append(entity)
	for pk: SimPickup in world.pickups.values():
		var entity := RenderFrame.Entity.new()
		entity.kind = RenderFrame.Entity.Kind.PICKUP
		entity.id = pk.id
		entity.pos = pk.pos
		entity.type_id = pk.part_id if pk.kind == SimPickup.Kind.PART else (&"health" if pk.kind == SimPickup.Kind.HEALTH else &"energy")
		entity.state = 1 if pk.life >= 0.0 and pk.life < 8.0 else 0  # 消えかけ
		frame.pickups.append(entity)
	return frame


func request_equip(part_id: StringName) -> void:
	if world != null and world.equip_part(local_id, part_id):
		Save.set_last_loadout(local_player.loadout)


func request_unequip(slot: RobotPart.Slot) -> void:
	if world != null and world.unequip_slot(local_id, slot):
		Save.set_last_loadout(local_player.loadout)


func player_color(_id: int) -> Color:
	return Color.html(Settings.get_string("player/color"))


func scoreboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if local_player != null:
		rows.append({"id": local_id, "name": local_player.player_name, "score": local_player.score,
			"kills": local_player.kills, "deaths": local_player.deaths, "ping": 0, "local": true})
	return rows


func shutdown(reason: String = "") -> void:
	Save.flush()
	ended.emit(reason)


func dev_command(command: String, args: PackedStringArray) -> String:
	if world == null:
		return "no world"
	match command:
		"god":
			_god = not _god
			return "god mode %s" % ("on" if _god else "off")
		"heal":
			local_player.health = local_player.stats.max_health
			local_player.energy = local_player.stats.max_energy
			return "healed"
		"give":
			if args.is_empty():
				return "usage: give <part_id|all>"
			var ids: Array[StringName] = []
			if args[0] == "all":
				for part in Content.all_parts():
					ids.append(part.id)
			elif Content.part(StringName(args[0])) != null:
				ids.append(StringName(args[0]))
			else:
				return "unknown part '%s'" % args[0]
			for id in ids:
				world.grant_part(local_id, id)
				Save.unlock_part(id)
			return "granted %d part(s)" % ids.size()
		"equip":
			if args.is_empty():
				return "usage: equip <part_id>"
			return "equipped" if world.equip_part(local_id, StringName(args[0])) else "cannot equip (not owned / unknown)"
		"spawn":
			if args.is_empty():
				return "usage: spawn <enemy_id> [count]"
			var def := Content.enemy(StringName(args[0]))
			if def == null:
				return "unknown enemy '%s'" % args[0]
			var count := int(args[1]) if args.size() > 1 else 1
			for i in clampi(count, 1, 20):
				var angle := local_player.yaw + (float(i) - float(count) / 2.0) * 0.4
				var at := local_player.pos + SimMath.forward(angle) * 8.0
				world.spawn_enemy_at(def, Vector3(clampf(at.x, -25.0, 25.0), 0.0, clampf(at.z, -25.0, 25.0)))
			return "spawned %d %s" % [count, args[0]]
		"killall":
			for e: SimEnemy in world.enemies.values().duplicate():
				world.damage_enemy(e, 99999.0, local_id, e.pos)
			return "cleared enemies"
		"enemies":
			world.spawn_enemies = args.is_empty() or args[0] != "off"
			return "enemy spawning %s" % ("on" if world.spawn_enemies else "off")
		"tp":
			if args.size() >= 2:
				local_player.pos = Vector3(float(args[0]), 0.0, float(args[1]))
				local_player.prev_pos = local_player.pos
				return "teleported"
			return "usage: tp <x> <z>"
	return "unknown command '%s'" % command


func _track_progress(event: SimEvent) -> void:
	match event.type:
		SimEvent.Type.PICKUP:
			if event.a == local_id and event.value > 0.5 and Content.part(event.tag) != null:
				Save.unlock_part(event.tag)
		SimEvent.Type.KILL:
			if event.a == local_id and event.b != local_id and event.tag != &"player":
				Save.add_stat("enemies")
			if event.b == local_id:
				Save.add_stat("deaths")
