class_name ClientSession
extends GameSession
## オンライン。サーバー権威のゲームに参加する。
##  - 自分のロボット: 入力を受けた瞬間に予測して動かし、サーバーの確認が届いたら補正する（Reconciler）
##  - ほかのプレイヤー・敵・弾: サーバー時刻の少し過去を補間して描く（InterpolationBuffer）
##  - 自分の弾: 見た目だけ先に出す（サーバーの弾は描かない）

enum Phase { CONNECTING, JOINING, WAITING_STATE, PLAYING, CLOSED }

## この時間サンプルが来ないエンティティは消す[秒]
const STALE_SECONDS := 0.25
const PING_INTERVAL := 1.0

var phase: Phase = Phase.CONNECTING
var server_url: String = ""
var display_name: String = "Player"

var reconciler: Reconciler
var clock := ClockSync.new()

var _seq: int = 0
var _recent_inputs: Array[PlayerInput] = []
## 種類ごとの「id -> InterpolationBuffer」
var _buffers := {
	RenderFrame.Entity.Kind.PLAYER: {},
	RenderFrame.Entity.Kind.ENEMY: {},
	RenderFrame.Entity.Kind.PROJECTILE: {},
	RenderFrame.Entity.Kind.PICKUP: {},
}
var _cosmetic_shots: Array[SimProjectile] = []
var _roster: Dictionary = {}
var _last_snapshot_tick: int = -1
var _ping: float = 0.0
var _ping_timer: float = 0.0
var _arena_seed: int = 0

## 統計（結合テスト・デバッグ表示用）
var snapshots_received: int = 0
var events_received: int = 0
var max_players_seen: int = 0


func is_online() -> bool:
	return true


func is_ready() -> bool:
	return phase == Phase.PLAYING and local_player != null and geometry != null


func status_key() -> String:
	match phase:
		Phase.CONNECTING:
			return "net.connecting"
		Phase.JOINING:
			return "net.joining"
		Phase.WAITING_STATE:
			return "net.joining"
	return ""


func ping_ms() -> int:
	return roundi(_ping)


func start(url: String, player_name: String) -> void:
	server_url = url
	display_name = player_name
	connect_signals()
	var error := Net.connect_to(url)
	if error != OK:
		notice.emit(tr("net.error.cannot_connect"), Events.ToastKind.BAD)
		_close("cannot_connect")


## Net のシグナルを受け取る準備（start が呼ぶ。テストでは通信なしに直接呼べる）
func connect_signals() -> void:
	Net.connected_to_server.connect(_on_connected)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)
	Net.welcome_received.connect(_on_welcome)
	Net.rejected.connect(_on_rejected)
	Net.snapshot_received.connect(_on_snapshot)
	Net.events_received.connect(_on_events)
	Net.pong_received.connect(_on_pong)
	Net.chat_received.connect(_on_chat)
	Net.roster_received.connect(_on_roster)
	Net.inventory_received.connect(_on_inventory)


func shutdown(reason: String = "") -> void:
	_disconnect_signals()
	if phase != Phase.CLOSED:
		phase = Phase.CLOSED
		Net.close()
		ended.emit(reason)


func _physics_process(delta: float) -> void:
	if phase == Phase.PLAYING:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = PING_INTERVAL
			Net.send_ping(Time.get_ticks_msec())
	if reconciler == null or phase != Phase.PLAYING:
		return
	_step_cosmetic_shots(SimConfig.DT)
	_predict_one_tick()


func _process(delta: float) -> void:
	if reconciler != null:
		reconciler.smooth(delta)


## 1 ティック分: 入力を取って予測し、サーバーへ送る
func _predict_one_tick() -> void:
	_seq += 1
	var input: PlayerInput = null
	if not paused and input_provider.is_valid():
		input = input_provider.call(_seq)
	if input == null:
		# ポーズ中・入力なしでも、確認応答を途切れさせないために空の入力を送り続ける
		input = PlayerInput.new()
		input.aim_yaw = local_player.yaw
	input.seq = _seq
	input.quantize()
	var flags := reconciler.predict(input)
	_emit_predicted_events(flags, input)

	_recent_inputs.append(input)
	while _recent_inputs.size() > NetProtocol.INPUT_REDUNDANCY:
		_recent_inputs.pop_front()
	var buffer := StreamPeerBuffer.new()
	for recent in _recent_inputs:
		recent.encode(buffer)
	Net.send_input(buffer.data_array)


## 予測で起きたこと（ジャンプ・着地・ダッシュ・発砲）は、サーバーの通知を待たずに演出する
func _emit_predicted_events(flags: int, input: PlayerInput) -> void:
	var p := local_player
	if flags & PlayerSim.EV_JUMP:
		sim_event.emit(SimEvent.make(SimEvent.Type.JUMP, p.pos, local_id))
	if flags & PlayerSim.EV_LAND:
		sim_event.emit(SimEvent.make(SimEvent.Type.LAND, p.pos, local_id))
	if flags & PlayerSim.EV_DASH:
		sim_event.emit(SimEvent.make(SimEvent.Type.DASH, p.pos, local_id))
	if flags & PlayerSim.EV_FIRE:
		for shot in PlayerSim.build_shots(p, input.seq):
			_cosmetic_shots.append(shot)
		sim_event.emit(SimEvent.make(SimEvent.Type.SHOT, p.muzzle_position(), local_id, 0, 0.0, p.stats.weapon_kind))


func _step_cosmetic_shots(dt: float) -> void:
	for i in range(_cosmetic_shots.size() - 1, -1, -1):
		var shot := _cosmetic_shots[i]
		shot.prev_pos = shot.pos
		shot.pos += shot.vel * dt
		shot.life -= dt
		if shot.life <= 0.0 or Motion.segment_hit_geometry(geometry, shot.prev_pos, shot.pos) >= 0.0:
			_cosmetic_shots.remove_at(i)


# --- 描画用のフレーム ---

func sample(alpha: float) -> RenderFrame:
	var frame := RenderFrame.new()
	if not is_ready():
		return frame
	var render_time := clock.server_time(float(Time.get_ticks_usec()) / 1000000.0) - NetProtocol.INTERPOLATION_DELAY

	var me := make_player_entity(local_player, alpha, local_id)
	me.pos += reconciler.view_offset
	frame.players.append(me)
	frame.local = me

	_sample_buffers(RenderFrame.Entity.Kind.PLAYER, render_time, frame.players)
	_sample_buffers(RenderFrame.Entity.Kind.ENEMY, render_time, frame.enemies)
	_sample_buffers(RenderFrame.Entity.Kind.PROJECTILE, render_time, frame.projectiles)
	_sample_buffers(RenderFrame.Entity.Kind.PICKUP, render_time, frame.pickups)
	for entity in frame.players:
		if not entity.is_local:
			entity.display_name = _roster.get(entity.id, {}).get("name", "?")

	for shot in _cosmetic_shots:
		var e := RenderFrame.Entity.new()
		e.kind = RenderFrame.Entity.Kind.PROJECTILE
		e.id = -shot.id - 1 - (hash(shot) & 0xFFFFFF)
		e.pos = shot.prev_pos.lerp(shot.pos, alpha)
		e.velocity = shot.vel
		e.yaw = SimMath.yaw_of(shot.vel)
		e.type_id = shot.weapon_kind
		e.owned_by_local = true
		frame.projectiles.append(e)
	return frame


func _sample_buffers(kind: int, render_time: float, into: Array[RenderFrame.Entity]) -> void:
	var table: Dictionary = _buffers[kind]
	for id in table.keys():
		var buffer: InterpolationBuffer = table[id]
		# 長いあいだサンプルが来ない = 関連性の外に出た・消えた
		if render_time > buffer.last_time() + STALE_SECONDS:
			table.erase(id)
			continue
		var entity := buffer.sample_at(render_time)
		if entity != null:
			into.append(entity)


# --- 操作 ---

func request_equip(part_id: StringName) -> void:
	var part := Content.part(part_id)
	if part != null:
		Net.send_equip(int(part.get_slot()), String(part_id))


func request_unequip(slot: RobotPart.Slot) -> void:
	Net.send_equip(int(slot), "")


func send_chat(text: String) -> void:
	Net.send_chat(text)


func scoreboard() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in _roster:
		var row: Dictionary = _roster[id]
		rows.append({"id": id, "name": row.get("name", "?"), "score": row.get("score", 0), "kills": row.get("kills", 0),
			"deaths": row.get("deaths", 0), "ping": row.get("ping", 0), "local": id == local_id})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return rows


func player_name(id: int) -> String:
	return _roster.get(id, {}).get("name", "?")


func player_color(id: int) -> Color:
	if id == local_id:
		return Color.html(Settings.get_string("player/color"))
	var hex: String = _roster.get(id, {}).get("color", "")
	return Color.html(hex) if hex.length() == 6 and hex.is_valid_html_color() else super.player_color(id)


# --- ネットワークからの受信 ---

func _on_connected() -> void:
	phase = Phase.JOINING
	var color := Settings.get_string("player/color")
	Net.send_hello(display_name, color)


func _on_connection_failed() -> void:
	notice.emit(tr("net.error.cannot_connect"), Events.ToastKind.BAD)
	_close("cannot_connect")


func _on_server_disconnected() -> void:
	if phase != Phase.CLOSED:
		notice.emit(tr("net.error.disconnected"), Events.ToastKind.BAD)
		_close("disconnected")


func _on_rejected(reason: String) -> void:
	var key := "net.error.%s" % reason
	var text := tr(key)
	notice.emit(text if text != key else tr("net.error.rejected"), Events.ToastKind.BAD)
	_close(reason)


func _on_welcome(info: Dictionary) -> void:
	local_id = int(info["your_id"])
	rules = GameRules.from_dict(info["rules"])
	_arena_seed = int(info["seed"])
	geometry = ArenaGenerator.generate(_arena_seed, rules)
	phase = Phase.WAITING_STATE
	Log.info("client", "welcome: id %d, arena seed %d" % [local_id, _arena_seed])


func _on_snapshot(payload: PackedByteArray) -> void:
	if phase != Phase.WAITING_STATE and phase != Phase.PLAYING:
		return
	var snapshot := SnapshotCodec.decode(payload)
	if snapshot == null or snapshot.tick <= _last_snapshot_tick:
		return
	_last_snapshot_tick = snapshot.tick
	snapshots_received += 1
	var server_time := float(snapshot.tick) * SimConfig.DT
	clock.observe(server_time, float(Time.get_ticks_usec()) / 1000000.0)

	if snapshot.own != null:
		if local_player == null:
			_create_local_player(snapshot)
		else:
			_apply_own_state(snapshot)

	_push_entities(snapshot.players, RenderFrame.Entity.Kind.PLAYER, server_time)
	_push_entities(snapshot.enemies, RenderFrame.Entity.Kind.ENEMY, server_time)
	_push_entities(snapshot.projectiles, RenderFrame.Entity.Kind.PROJECTILE, server_time)
	_push_entities(snapshot.pickups, RenderFrame.Entity.Kind.PICKUP, server_time)
	max_players_seen = maxi(max_players_seen, (_buffers[RenderFrame.Entity.Kind.PLAYER] as Dictionary).size() + 1)


func _create_local_player(snapshot: SnapshotCodec.Snapshot) -> void:
	local_player = SimPlayer.new()
	local_player.id = local_id
	local_player.player_name = display_name
	local_player.team = local_id
	local_player.pos = snapshot.own.pos
	local_player.prev_pos = snapshot.own.pos
	local_player.yaw = snapshot.own.yaw
	local_player.prev_yaw = snapshot.own.yaw
	local_player.set_loadout(Loadout.from_indices(snapshot.own_loadout))
	reconciler = Reconciler.new(local_player, geometry)
	reconciler.apply_authoritative(snapshot.own, snapshot.ack_seq)
	reconciler.max_error = 0.0
	reconciler.snaps = 0
	reconciler.corrections = 0
	reconciler.view_offset = Vector3.ZERO
	local_player.prev_pos = local_player.pos
	local_player.prev_yaw = local_player.yaw
	phase = Phase.PLAYING
	ready_to_play.emit()


func _apply_own_state(snapshot: SnapshotCodec.Snapshot) -> void:
	# 装備が変わっていたら（換装・拾得）、性能値を作り直してから補正する
	if local_player.loadout.to_indices() != snapshot.own_loadout:
		local_player.set_loadout(Loadout.from_indices(snapshot.own_loadout))
	var was_alive := local_player.alive
	reconciler.apply_authoritative(snapshot.own, snapshot.ack_seq)
	if snapshot.own.alive and not was_alive:
		# 復活した。古い入力・見た目のずれを引きずらない
		reconciler.view_offset = Vector3.ZERO
		local_player.prev_pos = local_player.pos


func _push_entities(entities: Array[RenderFrame.Entity], kind: int, server_time: float) -> void:
	var table: Dictionary = _buffers[kind]
	for entity in entities:
		# 自分の弾は予測側で描いているので、サーバーの弾は描かない
		if kind == RenderFrame.Entity.Kind.PROJECTILE and entity.state == local_id:
			continue
		var buffer: InterpolationBuffer = table.get(entity.id)
		if buffer == null:
			buffer = InterpolationBuffer.new()
			table[entity.id] = buffer
		buffer.push(server_time, entity)


func _on_events(payload: PackedByteArray) -> void:
	for event in SnapshotCodec.decode_events(payload):
		events_received += 1
		# 自分の動作は予測側で演出済み
		if event.a == local_id and event.type in [SimEvent.Type.JUMP, SimEvent.Type.LAND, SimEvent.Type.DASH, SimEvent.Type.SHOT]:
			continue
		match event.type:
			SimEvent.Type.KILL:
				if event.tag != &"player":
					(_buffers[RenderFrame.Entity.Kind.ENEMY] as Dictionary).erase(event.b)
			SimEvent.Type.HIT, SimEvent.Type.HIT_WORLD:
				if event.a == local_id or event.type == SimEvent.Type.HIT_WORLD:
					_drop_nearest_cosmetic_shot(event.pos)
		sim_event.emit(event)


## 当たった／壁に当たった弾は、見た目の弾も消す（近い 1 発）
func _drop_nearest_cosmetic_shot(at: Vector3) -> void:
	var best := -1
	var best_distance := 4.0
	for i in _cosmetic_shots.size():
		var d := _cosmetic_shots[i].pos.distance_to(at)
		if d < best_distance:
			best_distance = d
			best = i
	if best >= 0:
		_cosmetic_shots.remove_at(best)


func _on_pong(client_msec: int, _server_tick: int) -> void:
	var rtt := float(Time.get_ticks_msec() - client_msec)
	_ping = rtt if _ping <= 0.0 else lerpf(_ping, rtt, 0.3)


func _on_chat(sender: String, text: String) -> void:
	chat_received.emit(sender, text)


func _on_roster(rows: Array) -> void:
	_roster.clear()
	for row in rows:
		_roster[int(row["id"])] = row


func _on_inventory(part_ids: PackedStringArray) -> void:
	if local_player == null:
		return
	local_player.inventory.clear()
	for id in part_ids:
		local_player.inventory[StringName(id)] = true


func _disconnect_signals() -> void:
	for pair in [
		[Net.connected_to_server, _on_connected], [Net.connection_failed, _on_connection_failed],
		[Net.server_disconnected, _on_server_disconnected], [Net.welcome_received, _on_welcome],
		[Net.rejected, _on_rejected], [Net.snapshot_received, _on_snapshot], [Net.events_received, _on_events],
		[Net.pong_received, _on_pong], [Net.chat_received, _on_chat], [Net.roster_received, _on_roster],
		[Net.inventory_received, _on_inventory],
	]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _close(reason: String) -> void:
	if phase != Phase.CLOSED:
		phase = Phase.CLOSED
		Net.close()
		ended.emit(reason)
