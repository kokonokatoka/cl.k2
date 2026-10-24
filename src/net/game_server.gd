class_name GameServer
extends Node
## 専用サーバー（ビューなし）。サーバーが唯一の真実で、クライアントは入力を送り、結果を受け取る。
##
##   godot --headless --path . -- --server --port=8910
##
## 1 物理ティック（60Hz）につき: 各プレイヤーの入力を 1 つ消費 → SimWorld を 1 ティック → イベント配信 →
## 一定間隔（20Hz）で、受信者ごとに関連性で絞ったスナップショットを送る。

const HANDSHAKE_TIMEOUT_MSEC := 5000
const IDLE_TIMEOUT_MSEC := 20000
const ROSTER_INTERVAL_TICKS := 60
const MAX_INPUT_PAYLOAD := PlayerInput.WIRE_SIZE * 8

var world: SimWorld
var rules: GameRules
var peers: Dictionary = {}
var max_players: int = 16
var arena_seed: int = 1

# --- 統計（結合テストと運用の確認用） ---
var stats := {
	"ticks": 0, "players_peak": 0, "joins": 0, "rejects": 0,
	"snapshots": 0, "snapshot_bytes": 0, "tick_ms_total": 0.0, "tick_ms_max": 0.0,
	"inputs_dropped": 0, "rate_limited": 0,
}

var _stop_after_msec: int = 0
var _result_path: String = ""
var _started_msec: int = 0


func start(port: int, max_clients: int, seed_value: int) -> void:
	max_players = max_clients
	arena_seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec() & 0x7FFFFFFF)
	rules = GameRules.new()
	rules.pvp = Cfg.get_bool("pvp", true)
	if Cfg.has("enemies"):
		rules.enemy_base = Cfg.get_int("enemies", rules.enemy_base)
	if Cfg.has("arena"):
		rules.arena_half_size = Cfg.get_float("arena", rules.arena_half_size)
		rules.cover_count = int(rules.cover_count * pow(rules.arena_half_size / 30.0, 2.0))
	world = SimWorld.new(rules, arena_seed)
	_started_msec = Time.get_ticks_msec()
	if Cfg.has("duration"):
		_stop_after_msec = int(Cfg.get_float("duration") * 1000.0)
	_result_path = Cfg.get_string("result")

	if Cfg.is_headless():
		# ヘッドレスは何もしないと全力で回ってしまうので、フレームレートに上限を付ける
		Engine.max_fps = 120

	Net.hello_received.connect(_on_hello)
	Net.input_received.connect(_on_input)
	Net.equip_received.connect(_on_equip)
	Net.chat_requested.connect(_on_chat)
	Net.ping_received.connect(_on_ping)
	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	var error := Net.host(port, max_clients)
	if error != OK:
		Log.error("server", "cannot listen on port %d (error %d)" % [port, error])
		get_tree().quit(1)
		return
	Log.info("server", "ready: arena seed %d, content hash %08x, protocol %d" % [arena_seed, Content.content_hash(), NetProtocol.VERSION])


func _physics_process(delta: float) -> void:
	if world == null:
		return
	var started := Time.get_ticks_usec()
	var now := Time.get_ticks_msec()
	_check_timeouts(now)

	var inputs := {}
	for id in peers:
		var peer: PeerState = peers[id]
		peer.refill(delta)
		if peer.joined and world.players.has(id):
			var input := peer.take()
			if input != null:
				inputs[id] = input
	world.step(inputs)
	_dispatch_events(world.drain_events())
	if world.tick % NetProtocol.SNAPSHOT_INTERVAL == 0:
		_send_snapshots()
	if world.tick % ROSTER_INTERVAL_TICKS == 0:
		_send_roster()

	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	stats["ticks"] += 1
	stats["tick_ms_total"] += elapsed_ms
	stats["tick_ms_max"] = maxf(stats["tick_ms_max"], elapsed_ms)
	if _stop_after_msec > 0 and now - _started_msec >= _stop_after_msec:
		_finish()


func shutdown() -> void:
	Net.close()


# --- 接続 ---

func _on_peer_connected(peer_id: int) -> void:
	if peers.size() >= max_players:
		Log.warn("server", "refusing peer %d: server full" % peer_id)
		_reject(peer_id, "server_full")
		return
	peers[peer_id] = PeerState.new(peer_id)
	Log.debug("server", "peer %d connected, waiting for hello" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var peer: PeerState = peers.get(peer_id)
	if peer == null:
		return
	peers.erase(peer_id)
	if peer.joined:
		world.remove_player(peer_id)
		Log.info("server", "%s (%d) left. players: %d" % [peer.player_name, peer_id, _joined_count()])
		_broadcast_chat("", "%s left" % peer.player_name)
		_send_roster()


func _on_hello(peer_id: int, version: int, content_hash: int, player_name: String, color_hex: String) -> void:
	var peer: PeerState = peers.get(peer_id)
	if peer == null or peer.joined:
		return
	if version != NetProtocol.VERSION:
		_reject(peer_id, "version_mismatch")
		return
	if content_hash != Content.content_hash():
		_reject(peer_id, "content_mismatch")
		return
	peer.joined = true
	peer.player_name = _sanitize_name(player_name, peer_id)
	peer.color_hex = color_hex.substr(0, 6)
	var player := world.add_player(peer_id, peer.player_name)
	stats["joins"] += 1
	stats["players_peak"] = maxi(stats["players_peak"], _joined_count())
	Log.info("server", "%s (%d) joined. players: %d" % [peer.player_name, peer_id, _joined_count()])
	Net.send_welcome(peer_id, {
		"your_id": peer_id,
		"tick": world.tick,
		"seed": arena_seed,
		"rules": rules.to_dict(),
		"protocol": NetProtocol.VERSION,
		"tick_rate": SimConfig.TICK_RATE,
	})
	_send_inventory(peer_id, player)
	_broadcast_chat("", "%s joined" % peer.player_name)
	_send_roster()


func _on_input(peer_id: int, payload: PackedByteArray) -> void:
	var peer: PeerState = peers.get(peer_id)
	if peer == null or not peer.joined:
		return
	if not peer.spend():
		stats["rate_limited"] += 1
		return
	if payload.size() == 0 or payload.size() > MAX_INPUT_PAYLOAD or payload.size() % PlayerInput.WIRE_SIZE != 0:
		Log.warn("server", "bad input payload size %d from %d" % [payload.size(), peer_id])
		return
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = payload
	var dropped_before := peer.dropped
	for i in payload.size() / PlayerInput.WIRE_SIZE:
		peer.enqueue(PlayerInput.decode(buffer))
	stats["inputs_dropped"] += peer.dropped - dropped_before


func _on_equip(peer_id: int, slot: int, part_id: String) -> void:
	var peer: PeerState = peers.get(peer_id)
	if peer == null or not peer.joined or not peer.spend(4.0):
		return
	if slot < 0 or slot >= RobotPart.Slot.size() or part_id.length() > 48:
		return
	if part_id.is_empty():
		world.unequip_slot(peer_id, slot as RobotPart.Slot)
	else:
		var part := Content.part(StringName(part_id))
		# スロットの取り違えは無視する（所持品の検証は SimWorld がする）
		if part != null and int(part.get_slot()) == slot:
			world.equip_part(peer_id, part.id)


func _on_chat(peer_id: int, text: String) -> void:
	var peer: PeerState = peers.get(peer_id)
	if peer == null or not peer.joined:
		return
	var now := Time.get_ticks_msec()
	if now - peer.last_chat_msec < 500 or not peer.spend(6.0):
		return
	peer.last_chat_msec = now
	var clean := _sanitize_text(text, NetProtocol.MAX_CHAT_LENGTH)
	if clean.is_empty():
		return
	_broadcast_chat(peer.player_name, clean)


func _on_ping(peer_id: int, client_msec: int) -> void:
	var peer: PeerState = peers.get(peer_id)
	if peer == null or not peer.spend(0.5):
		return
	Net.send_pong(peer_id, client_msec, world.tick)


# --- 配信 ---

func _dispatch_events(events: Array[SimEvent]) -> void:
	if events.is_empty():
		return
	for id in peers:
		var peer: PeerState = peers[id]
		if not peer.joined:
			continue
		var player: SimPlayer = world.players.get(id)
		var relevant: Array[SimEvent] = []
		for event in events:
			if SnapshotCodec.event_is_relevant(event, player):
				relevant.append(event)
			# 新しいパーツを拾ったら、その人に所持品を送り直す
			if event.type == SimEvent.Type.PICKUP and event.a == id and event.value > 0.5:
				_send_inventory(id, player)
		if not relevant.is_empty():
			Net.send_events(id, SnapshotCodec.encode_events(relevant))


func _send_snapshots() -> void:
	for id in peers:
		var peer: PeerState = peers[id]
		if not peer.joined:
			continue
		var player: SimPlayer = world.players.get(id)
		if player == null:
			continue
		var payload := SnapshotCodec.encode(world, player, player.last_seq)
		stats["snapshots"] += 1
		stats["snapshot_bytes"] += payload.size()
		Net.send_snapshot(id, payload)


func _send_roster() -> void:
	var rows: Array = []
	for id in peers:
		var peer: PeerState = peers[id]
		var player: SimPlayer = world.players.get(id)
		if not peer.joined or player == null:
			continue
		rows.append({"id": id, "name": peer.player_name, "color": peer.color_hex, "score": player.score,
			"kills": player.kills, "deaths": player.deaths, "ping": peer.ping_ms})
	for id in peers:
		if (peers[id] as PeerState).joined:
			Net.send_roster(id, rows)


func _send_inventory(peer_id: int, player: SimPlayer) -> void:
	if player == null:
		return
	var ids := PackedStringArray()
	for part_id: StringName in player.inventory:
		ids.append(String(part_id))
	Net.send_inventory(peer_id, ids)


func _broadcast_chat(sender: String, text: String) -> void:
	for id in peers:
		if (peers[id] as PeerState).joined:
			Net.send_chat_to(id, sender, text)


# --- 検査・後始末 ---

func _check_timeouts(now: int) -> void:
	for id in peers.keys():
		var peer: PeerState = peers[id]
		if not peer.joined and now - peer.connected_msec > HANDSHAKE_TIMEOUT_MSEC:
			Log.info("server", "peer %d did not say hello in time" % id)
			Net.disconnect_peer(id)
		elif peer.joined and now - peer.last_input_msec > IDLE_TIMEOUT_MSEC:
			Log.info("server", "kicking idle peer %d" % id)
			Net.disconnect_peer(id)


func _reject(peer_id: int, reason: String) -> void:
	stats["rejects"] += 1
	Net.send_reject(peer_id, reason)
	# 通知が届く猶予を与えてから切る
	get_tree().create_timer(0.3).timeout.connect(func() -> void: Net.disconnect_peer(peer_id))


func _joined_count() -> int:
	var count := 0
	for peer: PeerState in peers.values():
		if peer.joined:
			count += 1
	return count


func _finish() -> void:
	_stop_after_msec = 0
	var summary := stats.duplicate()
	summary["avg_tick_ms"] = stats["tick_ms_total"] / maxf(float(stats["ticks"]), 1.0)
	summary["enemies"] = world.enemies.size()
	summary["tick"] = world.tick
	Log.info("server", "finished: %s" % JSON.stringify(summary))
	if not _result_path.is_empty():
		var file := FileAccess.open(_result_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(summary))
			file.close()
	Net.close()
	get_tree().quit()


static func _sanitize_name(raw: String, peer_id: int) -> String:
	var clean := _sanitize_text(raw, NetProtocol.MAX_NAME_LENGTH)
	return clean if not clean.is_empty() else "Player%d" % (peer_id % 1000)


## 制御文字を除いて、長さを制限する
static func _sanitize_text(raw: String, max_length: int) -> String:
	var result := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code != 127:
			result += raw[i]
	return result.strip_edges().substr(0, max_length)
