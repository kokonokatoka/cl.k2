class_name SnapshotCodec
extends RefCounted
## サーバー → クライアントのスナップショットとイベントのバイナリ変換。
## 位置は 1/64 m の int16、角度は 16bit/8bit、体力は 8bit に量子化して小さくする。
## スナップショットは受信者ごとに作る（自分の完全な状態＋関連性のある他のエンティティ）。

const FORMAT: int = 1
const POSITION_SCALE: float = 64.0
const VELOCITY_SCALE: float = 8.0
const NO_PART: int = 255
const MAX_ENEMIES: int = 255
const MAX_PICKUPS: int = 255

## デコード結果
class Snapshot:
	extends RefCounted
	var tick: int = 0
	var ack_seq: int = 0
	## 自分の状態（予測の対象＋体力など）。無ければ null
	var own: SimPlayer
	var own_loadout: PackedInt32Array = PackedInt32Array()
	var players: Array[RenderFrame.Entity] = []
	var enemies: Array[RenderFrame.Entity] = []
	var projectiles: Array[RenderFrame.Entity] = []
	var pickups: Array[RenderFrame.Entity] = []


static func encode(world: SimWorld, recipient: SimPlayer, ack_seq: int) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(FORMAT)
	buffer.put_u32(world.tick)
	buffer.put_u32(ack_seq)

	if recipient != null:
		buffer.put_u8(1)
		_encode_own(buffer, recipient)
	else:
		buffer.put_u8(0)

	# プレイヤー（自分以外）
	var players: Array[SimPlayer] = []
	for p: SimPlayer in world.players.values():
		if p != recipient and _visible(recipient, p.pos, 0.0):
			players.append(p)
	buffer.put_u8(mini(players.size(), 255))
	for i in mini(players.size(), 255):
		_encode_player(buffer, players[i])

	var enemies: Array[SimEnemy] = []
	for e: SimEnemy in world.enemies.values():
		if _visible(recipient, e.pos, 0.0) and enemies.size() < MAX_ENEMIES:
			enemies.append(e)
	buffer.put_u8(enemies.size())
	for e in enemies:
		_encode_enemy(buffer, e)

	var projectiles: Array[SimProjectile] = []
	for pr: SimProjectile in world.projectiles.values():
		if _visible(recipient, pr.pos, Relevance.PROJECTILE_EXTRA) and projectiles.size() < 65535:
			projectiles.append(pr)
	buffer.put_u16(projectiles.size())
	for pr in projectiles:
		_encode_projectile(buffer, pr)

	var pickups: Array[SimPickup] = []
	for pk: SimPickup in world.pickups.values():
		if _visible(recipient, pk.pos, 2.0) and pickups.size() < MAX_PICKUPS:
			pickups.append(pk)
	buffer.put_u8(pickups.size())
	for pk in pickups:
		_encode_pickup(buffer, pk)
	return buffer.data_array


static func decode(bytes: PackedByteArray) -> Snapshot:
	var snapshot := Snapshot.new()
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	if bytes.size() < 10 or buffer.get_u8() != FORMAT:
		return null
	snapshot.tick = buffer.get_u32()
	snapshot.ack_seq = buffer.get_u32()
	if buffer.get_u8() == 1:
		snapshot.own = SimPlayer.new()
		snapshot.own_loadout = _decode_own(buffer, snapshot.own)
	for i in buffer.get_u8():
		snapshot.players.append(_decode_player(buffer))
	for i in buffer.get_u8():
		snapshot.enemies.append(_decode_enemy(buffer))
	for i in buffer.get_u16():
		snapshot.projectiles.append(_decode_projectile(buffer))
	for i in buffer.get_u8():
		snapshot.pickups.append(_decode_pickup(buffer))
	return snapshot


# --- イベント ---

static func encode_events(events: Array[SimEvent]) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.put_u16(mini(events.size(), 65535))
	for i in mini(events.size(), 65535):
		var e := events[i]
		buffer.put_u8(e.type)
		_put_position(buffer, e.pos)
		buffer.put_u32(e.a)
		buffer.put_u32(e.b)
		buffer.put_float(e.value)
		buffer.put_u8(TagTable.index_of(e.tag))
	return buffer.data_array


static func decode_events(bytes: PackedByteArray) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	if bytes.size() < 2:
		return events
	for i in buffer.get_u16():
		if buffer.get_available_bytes() < 20:
			break
		var e := SimEvent.new()
		e.type = buffer.get_u8() as SimEvent.Type
		e.pos = _get_position(buffer)
		e.a = buffer.get_u32()
		e.b = buffer.get_u32()
		e.value = buffer.get_float()
		e.tag = TagTable.at(buffer.get_u8())
		events.append(e)
	return events


## このイベントを recipient に送るか。自分に関係するもの・近くのもの・全員に見せたいもの（撃破）
static func event_is_relevant(event: SimEvent, recipient: SimPlayer) -> bool:
	if recipient == null:
		return true
	if event.type == SimEvent.Type.KILL:
		return true
	if event.a == recipient.id or event.b == recipient.id:
		return true
	return Relevance.is_relevant(recipient, event.pos, 3.0)


# --- 自分 ---

static func _encode_own(buffer: StreamPeerBuffer, p: SimPlayer) -> void:
	for v in [p.pos.x, p.pos.y, p.pos.z, p.vel.x, p.vel.y, p.vel.z, p.yaw, p.energy, p.fire_cd,
			p.dash_time, p.dash_cd, p.dash_dir.x, p.dash_dir.z, p.invuln, p.health, p.respawn_timer]:
		buffer.put_float(v)
	buffer.put_u8((1 if p.on_floor else 0) | (2 if p.alive else 0))
	buffer.put_u8(p.last_buttons & 0xFF)
	for index in p.loadout.to_indices():
		buffer.put_u8(NO_PART if index < 0 else index)


static func _decode_own(buffer: StreamPeerBuffer, p: SimPlayer) -> PackedInt32Array:
	p.pos = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
	p.vel = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
	p.yaw = buffer.get_float()
	p.energy = buffer.get_float()
	p.fire_cd = buffer.get_float()
	p.dash_time = buffer.get_float()
	p.dash_cd = buffer.get_float()
	p.dash_dir = Vector3(buffer.get_float(), 0.0, buffer.get_float())
	p.invuln = buffer.get_float()
	p.health = buffer.get_float()
	p.respawn_timer = buffer.get_float()
	var flags := buffer.get_u8()
	p.on_floor = flags & 1 != 0
	p.alive = flags & 2 != 0
	p.last_buttons = buffer.get_u8()
	var indices := PackedInt32Array()
	for slot in RobotPart.Slot.size():
		var index := buffer.get_u8()
		indices.append(-1 if index == NO_PART else index)
	return indices


# --- 他のエンティティ ---

static func _encode_player(buffer: StreamPeerBuffer, p: SimPlayer) -> void:
	buffer.put_u32(p.id)
	_put_position(buffer, p.pos)
	buffer.put_u16(_quantize_yaw16(p.yaw))
	buffer.put_u8((1 if p.alive else 0) | (2 if p.dash_time > 0.0 else 0) | (4 if p.invuln > 0.0 else 0))
	buffer.put_u8(clampi(roundi(p.health / maxf(p.stats.max_health, 1.0) * 255.0), 0, 255))
	for index in p.loadout.to_indices():
		buffer.put_u8(NO_PART if index < 0 else index)


static func _decode_player(buffer: StreamPeerBuffer) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = RenderFrame.Entity.Kind.PLAYER
	e.id = buffer.get_u32()
	e.pos = _get_position(buffer)
	e.yaw = float(buffer.get_u16()) / 65536.0 * TAU
	var flags := buffer.get_u8()
	e.alive = flags & 1 != 0
	if flags & 2 != 0:
		e.flags |= RenderFrame.Entity.FLAG_DASHING
	if flags & 4 != 0:
		e.flags |= RenderFrame.Entity.FLAG_INVULN
	e.health_fraction = float(buffer.get_u8()) / 255.0
	var indices := PackedInt32Array()
	for slot in RobotPart.Slot.size():
		var index := buffer.get_u8()
		indices.append(-1 if index == NO_PART else index)
	e.loadout = indices
	return e


static func _encode_enemy(buffer: StreamPeerBuffer, e: SimEnemy) -> void:
	buffer.put_u32(e.id)
	buffer.put_u8(maxi(0, Content.enemy_index(e.def.id)))
	buffer.put_16(_quantize_position(e.pos.x))
	buffer.put_16(_quantize_position(e.pos.z))
	buffer.put_u8(roundi(wrapf(e.yaw, 0.0, TAU) / TAU * 256.0) & 0xFF)
	buffer.put_u8(clampi(roundi(e.health_fraction() * 255.0), 0, 255))
	buffer.put_u8((int(e.state) & 0x0F) | (0x80 if e.hurt_flash > 0.0 else 0))


static func _decode_enemy(buffer: StreamPeerBuffer) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = RenderFrame.Entity.Kind.ENEMY
	e.id = buffer.get_u32()
	var def := Content.enemy_at(buffer.get_u8())
	e.type_id = def.id if def != null else &""
	e.pos = Vector3(float(buffer.get_16()) / POSITION_SCALE, 0.0, float(buffer.get_16()) / POSITION_SCALE)
	e.yaw = float(buffer.get_u8()) / 256.0 * TAU
	e.health_fraction = float(buffer.get_u8()) / 255.0
	var state := buffer.get_u8()
	e.state = state & 0x0F
	if state & 0x80 != 0:
		e.flags |= RenderFrame.Entity.FLAG_HURT
	return e


static func _encode_projectile(buffer: StreamPeerBuffer, pr: SimProjectile) -> void:
	buffer.put_u32(pr.id)
	buffer.put_u8(TagTable.index_of(pr.weapon_kind))
	buffer.put_u32(pr.owner_id if pr.owner_kind == SimProjectile.Owner.PLAYER else 0)
	_put_position(buffer, pr.pos)
	buffer.put_16(clampi(roundi(pr.vel.x * VELOCITY_SCALE), -32768, 32767))
	buffer.put_16(clampi(roundi(pr.vel.z * VELOCITY_SCALE), -32768, 32767))


static func _decode_projectile(buffer: StreamPeerBuffer) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = RenderFrame.Entity.Kind.PROJECTILE
	e.id = buffer.get_u32()
	e.type_id = TagTable.at(buffer.get_u8())
	e.state = buffer.get_u32()  # 撃った人のID（0 = 敵）
	e.pos = _get_position(buffer)
	e.velocity = Vector3(float(buffer.get_16()) / VELOCITY_SCALE, 0.0, float(buffer.get_16()) / VELOCITY_SCALE)
	e.yaw = SimMath.yaw_of(e.velocity)
	return e


static func _encode_pickup(buffer: StreamPeerBuffer, pk: SimPickup) -> void:
	buffer.put_u32(pk.id)
	buffer.put_u8(pk.kind)
	buffer.put_u8(NO_PART if pk.kind != SimPickup.Kind.PART else maxi(0, Content.part_index(pk.part_id)))
	buffer.put_16(_quantize_position(pk.pos.x))
	buffer.put_16(_quantize_position(pk.pos.z))
	buffer.put_u8(1 if pk.life >= 0.0 and pk.life < 8.0 else 0)


static func _decode_pickup(buffer: StreamPeerBuffer) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = RenderFrame.Entity.Kind.PICKUP
	e.id = buffer.get_u32()
	var pickup_kind := buffer.get_u8()
	var part_index := buffer.get_u8()
	match pickup_kind:
		SimPickup.Kind.PART:
			var part := Content.part_at(part_index)
			e.type_id = part.id if part != null else &""
		SimPickup.Kind.HEALTH:
			e.type_id = &"health"
		_:
			e.type_id = &"energy"
	e.pos = Vector3(float(buffer.get_16()) / POSITION_SCALE, 0.0, float(buffer.get_16()) / POSITION_SCALE)
	e.state = buffer.get_u8()
	return e


# --- 量子化 ---

static func _visible(recipient: SimPlayer, at: Vector3, extra: float) -> bool:
	return recipient == null or Relevance.is_relevant(recipient, at, extra)


static func _quantize_position(value: float) -> int:
	return clampi(roundi(value * POSITION_SCALE), -32768, 32767)


static func _put_position(buffer: StreamPeerBuffer, pos: Vector3) -> void:
	buffer.put_16(_quantize_position(pos.x))
	buffer.put_16(_quantize_position(pos.y))
	buffer.put_16(_quantize_position(pos.z))


static func _get_position(buffer: StreamPeerBuffer) -> Vector3:
	return Vector3(float(buffer.get_16()) / POSITION_SCALE, float(buffer.get_16()) / POSITION_SCALE, float(buffer.get_16()) / POSITION_SCALE)


static func _quantize_yaw16(yaw: float) -> int:
	return roundi(wrapf(yaw, 0.0, TAU) / TAU * 65536.0) & 0xFFFF
