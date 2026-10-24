extends TestCase
## ネットコード: クライアント予測の収束（通信なしのハーネス）、サーバーの入力検証と参加処理、ClientSession。

const DT := SimConfig.DT

## 遅延・ジッタ・ロスのある一方通行のリンク（ティック単位）。順序は保つ
class Link:
	extends RefCounted
	var queue: Array = []
	var rng := DetRng.new(1)
	var delay: int = 0
	var jitter: int = 0
	var loss: float = 0.0
	var last_due: int = 0

	func send(now: int, payload: Variant, droppable: bool = true) -> void:
		if droppable and loss > 0.0 and rng.chance(loss):
			return
		var due := now + delay + (rng.range_int(0, jitter) if jitter > 0 else 0)
		due = maxi(due, last_due)
		last_due = due
		queue.append([due, payload])

	func receive(now: int) -> Array:
		var out: Array = []
		while not queue.is_empty() and queue[0][0] <= now:
			out.append(queue.pop_front()[1])
		return out

var _servers: Array[GameServer] = []
var _clients: Array[ClientSession] = []
var _sent: Array = []


func after_each() -> void:
	Net.tap = Callable()
	Log.level = Log.Level.WARN
	for server in _servers:
		server.queue_free()
	for client in _clients:
		client.queue_free()
	_servers.clear()
	_clients.clear()


# =============================================================
# 予測の収束
# =============================================================

func _input_script(seed_value: int, total_ticks: int, settle_ticks: int) -> Callable:
	var rng := DetRng.new(seed_value)
	var state := {"move": Vector2.ZERO, "buttons": 0, "yaw": 0.0}
	return func(_seq: int, tick: int) -> PlayerInput:
		var input := PlayerInput.new()
		if tick >= total_ticks - settle_ticks:
			input.aim_yaw = state["yaw"]
			return input
		if tick % 18 == 0:
			state["move"] = Vector2(rng.next_signed(), rng.next_signed()).limit_length(1.0)
			state["yaw"] = rng.range_float(0.0, TAU)
			state["buttons"] = int(rng.next_u32() % 8)
			if rng.chance(0.6):
				state["buttons"] = state["buttons"] & ~PlayerInput.BTN_DASH
		input.move = state["move"]
		input.aim_yaw = state["yaw"]
		input.buttons = state["buttons"]
		return input


## サーバーとクライアントを遅延リンクで繋いで動かす。戻り値: {world, server_player, reconciler}
func _simulate(ticks: int, up_delay: int, down_delay: int, jitter: int, loss: float, script: Callable, on_tick: Callable = Callable()) -> Dictionary:
	var rules := GameRules.new()
	rules.world_pickups = 0
	var world := SimWorld.new(rules, 3)
	world.spawn_enemies = false
	var server_player := world.add_player(1, "A")
	server_player.invuln = 0.0
	var client_player := SimPlayer.new()
	client_player.id = 1
	client_player.set_loadout(server_player.loadout.duplicate_loadout())
	client_player.copy_predicted_state_from(server_player)
	client_player.health = server_player.health
	var reconciler := Reconciler.new(client_player, world.geometry)
	var peer := PeerState.new(1)
	var up := Link.new()
	var down := Link.new()
	for link in [up, down]:
		link.jitter = jitter
		link.loss = loss
	up.delay = up_delay
	down.delay = down_delay
	up.rng = DetRng.new(11)
	down.rng = DetRng.new(12)

	var recent: Array[PlayerInput] = []
	for tick in ticks:
		var input: PlayerInput = script.call(tick + 1, tick)
		input.seq = tick + 1
		input.quantize()
		reconciler.predict(input)
		recent.append(input)
		while recent.size() > NetProtocol.INPUT_REDUNDANCY:
			recent.pop_front()
		var buffer := StreamPeerBuffer.new()
		for r in recent:
			r.encode(buffer)
		up.send(tick, buffer.data_array)

		for payload: PackedByteArray in up.receive(tick):
			var reader := StreamPeerBuffer.new()
			reader.data_array = payload
			for i in payload.size() / PlayerInput.WIRE_SIZE:
				peer.enqueue(PlayerInput.decode(reader))
		var taken := peer.take()
		world.step({1: taken} if taken != null else {})
		world.drain_events()
		if tick % NetProtocol.SNAPSHOT_INTERVAL == 0:
			down.send(tick, SnapshotCodec.encode(world, server_player, server_player.last_seq))
		for bytes: PackedByteArray in down.receive(tick):
			var snapshot := SnapshotCodec.decode(bytes)
			if snapshot.own_loadout != client_player.loadout.to_indices():
				client_player.set_loadout(Loadout.from_indices(snapshot.own_loadout))
			reconciler.apply_authoritative(snapshot.own, snapshot.ack_seq)
		reconciler.smooth(DT)
		if on_tick.is_valid():
			on_tick.call(tick, world, server_player, reconciler)
	return {"world": world, "server_player": server_player, "reconciler": reconciler}


func test_prediction_matches_the_server_without_loss() -> void:
	var total := 60 * 14
	var result := _simulate(total, 6, 6, 0, 0.0, _input_script(1, total, 120))
	var reconciler: Reconciler = result["reconciler"]
	var server_player: SimPlayer = result["server_player"]
	assert_eq(reconciler.snaps, 0, "no hard snaps on a clean link")
	assert_true(reconciler.max_error < 0.25, "max prediction error %.3f m" % reconciler.max_error)
	assert_true(reconciler.player.pos.distance_to(server_player.pos) < 0.05, "ends at the same place (%.3f m apart)" % reconciler.player.pos.distance_to(server_player.pos))
	assert_true(Vector2(server_player.pos.x, server_player.pos.z).length() > 0.5 or reconciler.pending.size() > 0, "the player actually moved")


func test_prediction_converges_with_jitter_and_loss() -> void:
	var total := 60 * 20
	var result := _simulate(total, 5, 7, 4, 0.12, _input_script(2, total, 240))
	var reconciler: Reconciler = result["reconciler"]
	var server_player: SimPlayer = result["server_player"]
	var distance := reconciler.player.pos.distance_to(server_player.pos)
	print("    lossy link: corrections=%d snaps=%d max_error=%.2f final_diff=%.3f" % [reconciler.corrections, reconciler.snaps, reconciler.max_error, distance])
	assert_true(distance < 0.05, "final difference %.3f m" % distance)
	assert_true(reconciler.view_offset.length() < 0.01, "visual offset has decayed")
	assert_true(reconciler.snaps <= 6, "only a few hard snaps (%d)" % reconciler.snaps)


func test_server_side_displacement_is_corrected() -> void:
	var total := 60 * 8
	var shove := func(tick: int, _world: SimWorld, server_player: SimPlayer, _reconciler: Reconciler) -> void:
		if tick == 120:
			server_player.pos += Vector3(2.0, 0.0, 0.0)  # 例: 爆風で飛ばされた
	var result := _simulate(total, 4, 4, 0, 0.0, _input_script(3, total, 150), shove)
	var reconciler: Reconciler = result["reconciler"]
	var server_player: SimPlayer = result["server_player"]
	assert_true(reconciler.corrections > 0 or reconciler.snaps > 0, "the client noticed the discrepancy")
	assert_true(reconciler.player.pos.distance_to(server_player.pos) < 0.05, "and converged")


func test_large_displacement_snaps_instead_of_sliding() -> void:
	var total := 60 * 6
	var teleport := func(tick: int, _world: SimWorld, server_player: SimPlayer, _reconciler: Reconciler) -> void:
		if tick == 100:
			server_player.pos = Vector3(-15.0, 0.0, 12.0)
	var result := _simulate(total, 3, 3, 0, 0.0, _input_script(4, total, 120), teleport)
	var reconciler: Reconciler = result["reconciler"]
	assert_true(reconciler.snaps >= 1)
	assert_true(reconciler.player.pos.distance_to((result["server_player"] as SimPlayer).pos) < 0.05)


func test_prediction_survives_a_mid_game_loadout_change() -> void:
	var total := 60 * 10
	var swap := func(tick: int, world: SimWorld, _server_player: SimPlayer, _reconciler: Reconciler) -> void:
		if tick == 150:
			world.grant_part(1, &"legs_roller")
			world.equip_part(1, &"legs_roller")
	var result := _simulate(total, 5, 5, 0, 0.0, _input_script(5, total, 150), swap)
	var reconciler: Reconciler = result["reconciler"]
	assert_eq(reconciler.player.loadout.get_part(RobotPart.Slot.LEGS).id, &"legs_roller", "client adopted the new legs")
	assert_true(reconciler.player.pos.distance_to((result["server_player"] as SimPlayer).pos) < 0.05)


func test_pending_inputs_are_bounded_when_the_server_is_silent() -> void:
	var geo := WorldGeometry.new(20.0)
	geo.finalize()
	var player := SimPlayer.new()
	var reconciler := Reconciler.new(player, geo)
	for i in 1000:
		var input := PlayerInput.new()
		input.seq = i + 1
		reconciler.predict(input)
	assert_true(reconciler.pending.size() <= Reconciler.MAX_PENDING)


func test_reconciler_drops_acknowledged_inputs() -> void:
	var geo := WorldGeometry.new(20.0)
	geo.finalize()
	var player := SimPlayer.new()
	var reconciler := Reconciler.new(player, geo)
	for i in 10:
		var input := PlayerInput.new()
		input.seq = i + 1
		reconciler.predict(input)
	var auth := SimPlayer.new()
	reconciler.apply_authoritative(auth, 7)
	assert_eq(reconciler.pending.size(), 3)
	assert_eq(reconciler.pending[0].seq, 8)


# =============================================================
# サーバーの処理
# =============================================================

func _server() -> GameServer:
	var server := GameServer.new()
	var rules := GameRules.new()
	rules.world_pickups = 0
	server.rules = rules
	server.arena_seed = 5
	server.world = SimWorld.new(rules, 5)
	server.world.spawn_enemies = false
	server.max_players = 3
	# 不正な入力や満員の拒否は、わざと起こして「警告が出る」のが正しい挙動。ログは静かにする
	Log.level = Log.Level.ERROR
	tree.root.add_child(server)
	_servers.append(server)
	_sent.clear()
	Net.tap = func(kind: String, peer_id: int, data: Variant) -> void: _sent.append([kind, peer_id, data])
	return server


func _messages(kind: String, peer_id: int = -1) -> Array:
	var result: Array = []
	for item in _sent:
		if item[0] == kind and (peer_id < 0 or item[1] == peer_id):
			result.append(item[2])
	return result


func _join(server: GameServer, id: int, player_name: String = "Bob") -> void:
	server._on_peer_connected(id)
	server._on_hello(id, NetProtocol.VERSION, Content.content_hash(), player_name, "ff8800")


func _input_payload(sequences: Array, buttons: int = 0) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	for seq in sequences:
		var input := PlayerInput.new()
		input.seq = seq
		input.buttons = buttons
		input.quantize().encode(buffer)
	return buffer.data_array


func test_server_welcomes_a_valid_hello() -> void:
	var server := _server()
	_join(server, 7, "Alice")
	assert_true(server.peers[7].joined)
	assert_true(server.world.players.has(7))
	assert_eq(server.world.players[7].player_name, "Alice")
	var welcomes := _messages("welcome", 7)
	assert_eq(welcomes.size(), 1)
	assert_eq(welcomes[0]["your_id"], 7)
	assert_eq(welcomes[0]["seed"], 5)
	assert_eq(GameRules.from_dict(welcomes[0]["rules"]).cover_count, server.rules.cover_count)
	assert_eq(_messages("inventory", 7).size(), 1)
	assert_eq((_messages("inventory", 7)[0] as PackedStringArray).size(), Content.starter_parts().size())


func test_server_rejects_wrong_version_and_content() -> void:
	var server := _server()
	server._on_peer_connected(7)
	server._on_hello(7, NetProtocol.VERSION + 1, Content.content_hash(), "X", "")
	assert_eq(_messages("reject", 7), ["version_mismatch"])
	assert_false(server.peers[7].joined)
	server._on_peer_connected(8)
	server._on_hello(8, NetProtocol.VERSION, Content.content_hash() ^ 1, "X", "")
	assert_eq(_messages("reject", 8), ["content_mismatch"])
	assert_false(server.world.players.has(7) or server.world.players.has(8))


func test_server_rejects_when_full() -> void:
	var server := _server()
	for id in [1, 2, 3]:
		_join(server, id)
	server._on_peer_connected(4)
	assert_eq(_messages("reject", 4), ["server_full"])
	assert_false(server.peers.has(4))


func test_hello_twice_does_not_duplicate_the_player() -> void:
	var server := _server()
	_join(server, 7)
	server._on_hello(7, NetProtocol.VERSION, Content.content_hash(), "Other", "")
	assert_eq(server.world.players.size(), 1)
	assert_eq(server.world.players[7].player_name, "Bob")


func test_names_are_sanitized() -> void:
	var server := _server()
	_join(server, 7, "\u0001\u0007Mal\nice  with a very long name that goes on")
	var player_name: String = server.world.players[7].player_name
	assert_true(player_name.length() <= NetProtocol.MAX_NAME_LENGTH)
	assert_false(player_name.contains("\n") or player_name.contains("\u0001"))
	_join(server, 8, "   ")
	assert_true((server.world.players[8].player_name as String).begins_with("Player"), "empty name gets a default")


func test_inputs_are_queued_deduplicated_and_validated() -> void:
	var server := _server()
	_join(server, 7)
	var peer: PeerState = server.peers[7]
	server._on_input(7, _input_payload([1, 2, 3]))
	assert_eq(peer.queue.size(), 3)
	server._on_input(7, _input_payload([2, 3, 4]))
	assert_eq(peer.queue.size(), 4, "only seq 4 is new (redundant copies are dropped)")
	server._on_input(7, PackedByteArray([1, 2, 3]))
	server._on_input(7, PackedByteArray())
	server._on_input(7, _input_payload([5, 6, 7, 8, 9, 10, 11, 12, 13]))
	assert_eq(peer.queue.size(), 4, "oversized and malformed payloads are ignored")
	server._on_input(99, _input_payload([1]))
	assert_false(server.peers.has(99))


func test_input_queue_is_capped_and_counts_drops() -> void:
	var server := _server()
	_join(server, 7)
	var peer: PeerState = server.peers[7]
	for batch in 4:
		server._on_input(7, _input_payload([batch * 3 + 1, batch * 3 + 2, batch * 3 + 3]))
	assert_eq(peer.queue.size(), SimConfig.INPUT_QUEUE_MAX)
	assert_true(peer.dropped > 0)
	assert_true(server.stats["inputs_dropped"] > 0)
	assert_eq(peer.queue[0].seq, 12 - SimConfig.INPUT_QUEUE_MAX + 1, "the oldest were dropped")


func test_server_consumes_one_input_per_tick_and_repeats_then_idles() -> void:
	var peer := PeerState.new(1)
	for seq in [1, 2]:
		var input := PlayerInput.new()
		input.seq = seq
		input.buttons = PlayerInput.BTN_FIRE
		peer.enqueue(input)
	assert_eq(peer.take().seq, 1)
	assert_eq(peer.take().seq, 2)
	for i in SimConfig.INPUT_REPEAT_MAX:
		assert_eq(peer.take().seq, 2, "starved: the last input repeats")
	assert_null(peer.take(), "then nothing is pressed any more")


func test_a_flood_of_messages_is_rate_limited() -> void:
	var server := _server()
	_join(server, 7)
	var payload := _input_payload([1])
	for i in 1000:
		server._on_input(7, payload)
	assert_true(server.stats["rate_limited"] > 600, "limited %d" % server.stats["rate_limited"])


func test_equip_is_validated_server_side() -> void:
	var server := _server()
	_join(server, 7)
	var player: SimPlayer = server.world.players[7]
	server._on_equip(7, RobotPart.Slot.ARMS, "arms_rail")
	assert_eq(player.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_blaster", "not owned")
	server.world.grant_part(7, &"arms_rail")
	server._on_equip(7, RobotPart.Slot.EYES, "arms_rail")
	assert_eq(player.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_blaster", "wrong slot is ignored")
	server._on_equip(7, 99, "arms_rail")
	server._on_equip(7, RobotPart.Slot.ARMS, "nonsense")
	assert_eq(player.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_blaster")
	server._on_equip(7, RobotPart.Slot.ARMS, "arms_rail")
	assert_eq(player.loadout.get_part(RobotPart.Slot.ARMS).id, &"arms_rail")
	server._on_equip(7, RobotPart.Slot.ARMS, "")
	assert_false(player.loadout.has_slot(RobotPart.Slot.ARMS), "empty id unequips")


func test_chat_is_sanitized_and_rate_limited() -> void:
	var server := _server()
	_join(server, 7, "Ann")
	_join(server, 8, "Ben")
	_sent.clear()
	server._on_chat(7, "he\u0001llo\n world")
	var delivered := _messages("chat_to")
	assert_eq(delivered.size(), 2, "broadcast to both players")
	assert_eq(delivered[0], ["Ann", "hello world"])
	server._on_chat(7, "second message too soon")
	assert_eq(_messages("chat_to").size(), 2, "rate limited")
	server.peers[7].last_chat_msec = -100000
	server._on_chat(7, "x".repeat(500))
	assert_eq((_messages("chat_to")[2] as Array)[1].length(), NetProtocol.MAX_CHAT_LENGTH)
	server.peers[7].last_chat_msec = -100000
	server._on_chat(7, "\u0001\u0002  ")
	assert_eq(_messages("chat_to").size(), 4, "empty after sanitizing: nothing sent")


func test_ping_gets_a_pong_with_the_server_tick() -> void:
	var server := _server()
	_join(server, 7)
	server.world.tick = 123
	server._on_ping(7, 4242)
	assert_eq(_messages("pong", 7), [[4242, 123]])


func test_disconnect_removes_the_player_and_updates_the_roster() -> void:
	var server := _server()
	_join(server, 7)
	_join(server, 8)
	_sent.clear()
	server._on_peer_disconnected(7)
	assert_false(server.world.players.has(7))
	assert_false(server.peers.has(7))
	var rosters := _messages("roster", 8)
	assert_eq((rosters[rosters.size() - 1] as Array).size(), 1)


func test_server_sends_decodable_snapshots_with_the_ack() -> void:
	var server := _server()
	_join(server, 7)
	server._on_input(7, _input_payload([1, 2, 3]))
	for i in 3:
		server.world.step({7: server.peers[7].take()})
	_sent.clear()
	server._send_snapshots()
	var snapshots := _messages("snapshot", 7)
	assert_eq(snapshots.size(), 1)
	var snapshot := SnapshotCodec.decode(snapshots[0])
	assert_eq(snapshot.ack_seq, 3)
	assert_not_null(snapshot.own)


func test_server_events_are_filtered_per_recipient() -> void:
	var server := _server()
	_join(server, 7)
	_join(server, 8)
	server.world.players[7].pos = Vector3(-20, 0, -20)
	server.world.players[8].pos = Vector3(20, 0, 20)
	_sent.clear()
	var events: Array[SimEvent] = [SimEvent.make(SimEvent.Type.SHOT, Vector3(-19, 1, -20), 7, 0, 0.0, &"blaster")]
	server._dispatch_events(events)
	assert_eq(_messages("events", 7).size(), 1)
	assert_eq(_messages("events", 8).size(), 0, "too far away to hear about it")


func test_picking_up_a_new_part_resends_the_inventory() -> void:
	var server := _server()
	_join(server, 7)
	_sent.clear()
	var events: Array[SimEvent] = [SimEvent.make(SimEvent.Type.PICKUP, Vector3.ZERO, 7, 0, 1.0, &"arms_rail")]
	server._dispatch_events(events)
	assert_eq(_messages("inventory", 7).size(), 1)


# =============================================================
# ClientSession
# =============================================================

func _client() -> ClientSession:
	var client := ClientSession.new()
	tree.root.add_child(client)
	client.connect_signals()
	client.phase = ClientSession.Phase.JOINING
	_clients.append(client)
	return client


func _welcome(client: ClientSession, id: int, seed_value: int, rules: GameRules) -> void:
	client._on_welcome({"your_id": id, "seed": seed_value, "rules": rules.to_dict(), "tick": 0})


func _scenario() -> Dictionary:
	var rules := GameRules.new()
	rules.world_pickups = 0
	var world := SimWorld.new(rules, 5)
	world.spawn_enemies = false
	var me := world.add_player(7, "Me")
	var other := world.add_player(8, "Rival")
	me.invuln = 0.0
	other.invuln = 0.0
	return {"rules": rules, "world": world, "me": me, "other": other}


func test_client_becomes_ready_on_the_first_snapshot() -> void:
	var s := _scenario()
	var client := _client()
	var ready := [false]
	client.ready_to_play.connect(func() -> void: ready[0] = true)
	_welcome(client, 7, 5, s["rules"])
	assert_false(client.is_ready(), "needs a snapshot first")
	assert_eq(client.status_key(), "net.joining")
	client._on_snapshot(SnapshotCodec.encode(s["world"], s["me"], 0))
	assert_true(ready[0])
	assert_true(client.is_ready())
	assert_eq(client.status_key(), "")
	assert_vec3_near(client.local_player.pos, (s["me"] as SimPlayer).pos, 1e-4)
	assert_not_null(client.geometry)
	assert_eq(client.geometry.box_count, (s["world"] as SimWorld).geometry.box_count, "same arena from the same seed")


func test_client_shows_other_players_and_forgets_stale_ones() -> void:
	var s := _scenario()
	(s["other"] as SimPlayer).pos = (s["me"] as SimPlayer).pos + Vector3(3, 0, 0)
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	client._on_roster([{"id": 7, "name": "Me", "score": 0, "kills": 0, "deaths": 0, "ping": 0, "color": "ff0000"},
		{"id": 8, "name": "Rival", "score": 5, "kills": 1, "deaths": 0, "ping": 30, "color": "00ff00"}])
	var world: SimWorld = s["world"]
	world.tick = 30
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	var frame := client.sample(1.0)
	assert_not_null(frame.local)
	assert_eq(frame.players.size(), 2)
	var rival: RenderFrame.Entity = null
	for e in frame.players:
		if not e.is_local:
			rival = e
	assert_not_null(rival)
	assert_eq(rival.display_name, "Rival")
	assert_vec3_near(rival.pos, (s["other"] as SimPlayer).pos, 0.05)
	assert_eq(client.player_name(8), "Rival")
	assert_eq(client.player_color(8).to_html(false), "00ff00")
	assert_eq(client.scoreboard()[0]["name"], "Rival", "sorted by score")
	# 長く更新が無ければ消える
	client.clock.offset += 10.0
	assert_eq(client.sample(1.0).players.size(), 1)


func test_old_snapshots_are_ignored() -> void:
	var s := _scenario()
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	var world: SimWorld = s["world"]
	world.tick = 100
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	var received: int = client.snapshots_received
	world.tick = 90
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	assert_eq(client.snapshots_received, received)


func test_own_predicted_actions_are_not_announced_twice() -> void:
	var s := _scenario()
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	client._on_snapshot(SnapshotCodec.encode(s["world"], s["me"], 0))
	var seen: Array[int] = []
	client.sim_event.connect(func(e: SimEvent) -> void: seen.append(e.type))
	var events: Array[SimEvent] = [
		SimEvent.make(SimEvent.Type.JUMP, Vector3.ZERO, 7),
		SimEvent.make(SimEvent.Type.SHOT, Vector3.ZERO, 7, 0, 0.0, &"blaster"),
		SimEvent.make(SimEvent.Type.JUMP, Vector3.ZERO, 8),
		SimEvent.make(SimEvent.Type.HIT, Vector3.ZERO, 7, 8, 5.0, &"player"),
	]
	client._on_events(SnapshotCodec.encode_events(events))
	assert_eq(seen, [SimEvent.Type.JUMP, SimEvent.Type.HIT], "my own jump/shot were already shown by prediction")


func test_enemy_kill_removes_the_enemy_at_once() -> void:
	var s := _scenario()
	var world: SimWorld = s["world"]
	var enemy := world.spawn_enemy_at(Content.enemy(&"scout"), (s["me"] as SimPlayer).pos + Vector3(4, 0, 0))
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	assert_eq(client.sample(1.0).enemies.size(), 1)
	var kill: Array[SimEvent] = [SimEvent.make(SimEvent.Type.KILL, enemy.pos, 7, enemy.id, 10.0, &"scout")]
	client._on_events(SnapshotCodec.encode_events(kill))
	assert_eq(client.sample(1.0).enemies.size(), 0)


func test_firing_makes_a_local_shot_and_hides_the_servers_copy() -> void:
	var s := _scenario()
	var world: SimWorld = s["world"]
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	client.input_provider = func(seq: int) -> PlayerInput:
		var input := PlayerInput.new()
		input.seq = seq
		input.buttons = PlayerInput.BTN_FIRE
		return input
	var shots := [0]
	client.sim_event.connect(func(e: SimEvent) -> void: shots[0] += int(e.type == SimEvent.Type.SHOT))
	client._predict_one_tick()
	assert_eq(shots[0], 1, "muzzle flash and sound happen immediately")
	var frame := client.sample(1.0)
	assert_eq(frame.projectiles.size(), 1)
	assert_true(frame.projectiles[0].owned_by_local)
	# サーバーが同じ弾を送ってきても、自分の弾は描かない
	world.spawn_projectile(SimProjectile.make(SimProjectile.Owner.PLAYER, 7, &"blaster", (s["me"] as SimPlayer).pos + Vector3(0, 1.4, -1), Vector3(0, 0, -20), 1.0, 5.0, 0))
	world.tick = 40
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 1))
	assert_eq(client.sample(1.0).projectiles.size(), 1, "still only the local one")


func test_client_sends_redundant_inputs_and_idles_when_paused() -> void:
	var s := _scenario()
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	client._on_snapshot(SnapshotCodec.encode(s["world"], s["me"], 0))
	_sent.clear()
	Net.tap = func(kind: String, peer_id: int, data: Variant) -> void: _sent.append([kind, peer_id, data])
	client.input_provider = func(seq: int) -> PlayerInput:
		var input := PlayerInput.new()
		input.seq = seq
		input.buttons = PlayerInput.BTN_FIRE
		input.move = Vector2(1, 0)
		return input
	for i in 5:
		client._predict_one_tick()
	var payloads := _messages("input")
	assert_eq(payloads.size(), 5)
	assert_eq((payloads[0] as PackedByteArray).size(), PlayerInput.WIRE_SIZE, "first: one input")
	assert_eq((payloads[4] as PackedByteArray).size(), PlayerInput.WIRE_SIZE * NetProtocol.INPUT_REDUNDANCY, "later: the last few")
	client.paused = true
	_sent.clear()
	client._predict_one_tick()
	var reader := StreamPeerBuffer.new()
	var paused_payload: PackedByteArray = _messages("input")[0]
	reader.data_array = paused_payload
	reader.seek(paused_payload.size() - PlayerInput.WIRE_SIZE)
	var last := PlayerInput.decode(reader)
	assert_eq(last.buttons, 0, "paused clients send neutral input (the ack keeps flowing)")
	assert_eq(last.move, Vector2.ZERO)


func test_rejection_and_disconnect_end_the_session() -> void:
	var client := _client()
	var reasons: Array[String] = []
	client.ended.connect(func(reason: String) -> void: reasons.append(reason))
	client._on_rejected("version_mismatch")
	assert_eq(reasons, ["version_mismatch"])
	assert_eq(client.phase, ClientSession.Phase.CLOSED)
	client._on_server_disconnected()
	assert_eq(reasons.size(), 1, "already closed: not reported again")


func test_loadout_and_inventory_updates_apply() -> void:
	var s := _scenario()
	var world: SimWorld = s["world"]
	var client := _client()
	_welcome(client, 7, 5, s["rules"])
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	client._on_inventory(PackedStringArray(["arms_rail", "eye_scope"]))
	assert_true(client.local_player.inventory.has(&"arms_rail"))
	assert_false(client.local_player.inventory.has(&"arms_blaster"), "replaced, not merged")
	world.grant_part(7, &"legs_roller")
	world.equip_part(7, &"legs_roller")
	world.tick = 50
	client._on_snapshot(SnapshotCodec.encode(world, s["me"], 0))
	assert_eq(client.local_player.loadout.get_part(RobotPart.Slot.LEGS).id, &"legs_roller")
	assert_near(client.local_player.stats.move_speed, 10.0)
