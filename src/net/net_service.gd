extends Node
## ネットワークの窓口（autoload: Net）。WebSocket 上の Godot マルチプレイヤーと、すべての RPC をここに集める。
## RPC はサーバーとクライアントで同じノードパス（/root/Net）に同じ宣言が必要なため 1 か所にまとめている。
## 受け取ったデータはシグナルで GameServer / ClientSession に渡す。ゲームの処理はここに書かない。
##
## 開発用に、人工的な遅延・ジッタ・パケットロスを挟める（latency_ms / jitter_ms / loss）。
## 遅延は「送信側」と「受信側」の両方に掛かるので、往復では 2 倍になる。

# --- 接続の状態 ---
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connected_to_server
signal connection_failed
signal server_disconnected

# --- サーバーが受け取る ---
signal hello_received(peer_id: int, version: int, content_hash: int, player_name: String, color_hex: String)
signal input_received(peer_id: int, payload: PackedByteArray)
signal equip_received(peer_id: int, slot: int, part_id: String)
signal chat_requested(peer_id: int, text: String)
signal ping_received(peer_id: int, client_msec: int)

# --- クライアントが受け取る ---
signal welcome_received(info: Dictionary)
signal rejected(reason: String)
signal snapshot_received(payload: PackedByteArray)
signal events_received(payload: PackedByteArray)
signal pong_received(client_msec: int, server_tick: int)
signal chat_received(sender: String, text: String)
signal roster_received(rows: Array)
signal inventory_received(part_ids: PackedStringArray)

## 擬似的な通信状態（開発・テスト用）
var latency_ms: float = 0.0
var jitter_ms: float = 0.0
var loss: float = 0.0

## テスト用: 送信したものを観察する。(kind: String, peer_id: int, data: Variant) を受け取る。
## 実際の通信相手（_peer）がいなければ何も送られないので、サーバー/クライアントの処理を通信なしでテストできる
var tap: Callable

## 通信量の統計（バイト/秒。ペイロードの大きさだけを数える概算）
var rate_in: float = 0.0
var rate_out: float = 0.0
var snapshot_bytes: int = 0

var _peer: WebSocketMultiplayerPeer
var _out_queue: Array[Dictionary] = []
var _in_queue: Array[Dictionary] = []
var _last_out_due: float = 0.0
var _last_in_due: float = 0.0
var _bytes_in: int = 0
var _bytes_out: int = 0
var _rate_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	latency_ms = Cfg.get_float("latency", 0.0)
	jitter_ms = Cfg.get_float("jitter", 0.0)
	loss = Cfg.get_float("loss", 0.0)


func _process(delta: float) -> void:
	_flush(_out_queue)
	_flush(_in_queue)
	_rate_timer += delta
	if _rate_timer >= 1.0:
		rate_in = float(_bytes_in) / _rate_timer
		rate_out = float(_bytes_out) / _rate_timer
		_bytes_in = 0
		_bytes_out = 0
		_rate_timer = 0.0


# --- 接続 ---

## サーバーとして待ち受ける
func host(port: int, max_clients: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error != OK:
		return error
	_attach(peer)
	Log.info("net", "listening on port %d (max %d clients)" % [port, max_clients])
	return OK


## クライアントとして接続する（url 例: ws://127.0.0.1:8910）
func connect_to(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		return error
	_attach(peer)
	Log.info("net", "connecting to %s" % url)
	return OK


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	_out_queue.clear()
	_in_queue.clear()


func is_connected_to_server() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func disconnect_peer(peer_id: int) -> void:
	if _peer != null:
		_peer.disconnect_peer(peer_id)


func local_peer_id() -> int:
	return multiplayer.get_unique_id() if _peer != null else 0


# --- クライアント → サーバー（送る側） ---

func send_hello(player_name: String, color_hex: String) -> void:
	# --protocol-override は、版の違うクライアントを装うテスト用
	var version := Cfg.get_int("protocol-override", NetProtocol.VERSION)
	_tap("hello", 1, [version, player_name, color_hex])
	_send(false, func() -> void: c_hello.rpc_id(1, version, Content.content_hash(), player_name, color_hex))


func send_input(payload: PackedByteArray) -> void:
	_tap("input", 1, payload)
	_send(true, func() -> void: c_input.rpc_id(1, payload), payload.size())


func send_equip(slot: int, part_id: String) -> void:
	_tap("equip", 1, [slot, part_id])
	_send(false, func() -> void: c_equip.rpc_id(1, slot, part_id))


func send_chat(text: String) -> void:
	_tap("chat", 1, text)
	_send(false, func() -> void: c_chat.rpc_id(1, text))


func send_ping(client_msec: int) -> void:
	_tap("ping", 1, client_msec)
	_send(true, func() -> void: c_ping.rpc_id(1, client_msec))


# --- サーバー → クライアント（送る側） ---

func send_welcome(peer_id: int, info: Dictionary) -> void:
	_tap("welcome", peer_id, info)
	_send(false, func() -> void: s_welcome.rpc_id(peer_id, info))


func send_reject(peer_id: int, reason: String) -> void:
	_tap("reject", peer_id, reason)
	_send(false, func() -> void: s_reject.rpc_id(peer_id, reason))


func send_snapshot(peer_id: int, payload: PackedByteArray) -> void:
	snapshot_bytes = payload.size()
	_tap("snapshot", peer_id, payload)
	_send(true, func() -> void: s_snapshot.rpc_id(peer_id, payload), payload.size())


func send_events(peer_id: int, payload: PackedByteArray) -> void:
	_tap("events", peer_id, payload)
	_send(false, func() -> void: s_events.rpc_id(peer_id, payload), payload.size())


func send_pong(peer_id: int, client_msec: int, server_tick: int) -> void:
	_tap("pong", peer_id, [client_msec, server_tick])
	_send(true, func() -> void: s_pong.rpc_id(peer_id, client_msec, server_tick))


func send_chat_to(peer_id: int, sender: String, text: String) -> void:
	_tap("chat_to", peer_id, [sender, text])
	_send(false, func() -> void: s_chat.rpc_id(peer_id, sender, text))


func send_roster(peer_id: int, rows: Array) -> void:
	_tap("roster", peer_id, rows)
	_send(false, func() -> void: s_roster.rpc_id(peer_id, rows))


func send_inventory(peer_id: int, part_ids: PackedStringArray) -> void:
	_tap("inventory", peer_id, part_ids)
	_send(false, func() -> void: s_inventory.rpc_id(peer_id, part_ids))


# --- RPC（受ける側）---

@rpc("any_peer", "call_remote", "reliable")
func c_hello(version: int, content_hash: int, player_name: String, color_hex: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_receive(false, func() -> void: hello_received.emit(sender, version, content_hash, player_name, color_hex))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_input(payload: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_receive(true, func() -> void: input_received.emit(sender, payload), payload.size())


@rpc("any_peer", "call_remote", "reliable")
func c_equip(slot: int, part_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_receive(false, func() -> void: equip_received.emit(sender, slot, part_id))


@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_receive(false, func() -> void: chat_requested.emit(sender, text))


@rpc("any_peer", "call_remote", "unreliable")
func c_ping(client_msec: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	_receive(true, func() -> void: ping_received.emit(sender, client_msec))


@rpc("authority", "call_remote", "reliable")
func s_welcome(info: Dictionary) -> void:
	_receive(false, func() -> void: welcome_received.emit(info))


@rpc("authority", "call_remote", "reliable")
func s_reject(reason: String) -> void:
	_receive(false, func() -> void: rejected.emit(reason))


@rpc("authority", "call_remote", "unreliable_ordered")
func s_snapshot(payload: PackedByteArray) -> void:
	_receive(true, func() -> void: snapshot_received.emit(payload), payload.size())


@rpc("authority", "call_remote", "reliable")
func s_events(payload: PackedByteArray) -> void:
	_receive(false, func() -> void: events_received.emit(payload), payload.size())


@rpc("authority", "call_remote", "unreliable")
func s_pong(client_msec: int, server_tick: int) -> void:
	_receive(true, func() -> void: pong_received.emit(client_msec, server_tick))


@rpc("authority", "call_remote", "reliable")
func s_chat(sender: String, text: String) -> void:
	_receive(false, func() -> void: chat_received.emit(sender, text))


@rpc("authority", "call_remote", "reliable")
func s_roster(rows: Array) -> void:
	_receive(false, func() -> void: roster_received.emit(rows))


@rpc("authority", "call_remote", "reliable")
func s_inventory(part_ids: PackedStringArray) -> void:
	_receive(false, func() -> void: inventory_received.emit(part_ids))


# --- 内部 ---

func _attach(peer: WebSocketMultiplayerPeer) -> void:
	close()
	_peer = peer
	multiplayer.multiplayer_peer = peer
	# クライアントどうしが直接やり取りする経路は塞ぐ（サーバーを必ず経由する）
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer != null:
		scene_multiplayer.server_relay = false
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	peer_connected.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	Log.info("net", "connected to server")
	connected_to_server.emit()


func _on_connection_failed() -> void:
	Log.warn("net", "connection failed")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	Log.warn("net", "server disconnected")
	server_disconnected.emit()


func _tap(kind: String, peer_id: int, data: Variant) -> void:
	if tap.is_valid():
		tap.call(kind, peer_id, data)


## 送信。通信状態の擬似劣化があれば遅らせる／落とす。droppable: 落としてよい（信頼性のない）通信か
func _send(droppable: bool, action: Callable, size: int = 0) -> void:
	if _peer == null:
		return
	_bytes_out += size
	if latency_ms <= 0.0 and jitter_ms <= 0.0 and loss <= 0.0:
		action.call()
		return
	if droppable and _rng.randf() < loss:
		return
	_last_out_due = _queue_delayed(_out_queue, action, _last_out_due)


func _receive(droppable: bool, action: Callable, size: int = 0) -> void:
	_bytes_in += size
	if latency_ms <= 0.0 and jitter_ms <= 0.0 and loss <= 0.0:
		action.call()
		return
	if droppable and _rng.randf() < loss:
		return
	_last_in_due = _queue_delayed(_in_queue, action, _last_in_due)


## 順序を保ったまま遅延させる（前のものより先に出ないよう、期限は単調にする）
func _queue_delayed(queue: Array[Dictionary], action: Callable, last_due: float) -> float:
	var due := float(Time.get_ticks_usec()) / 1000.0 + latency_ms + _rng.randf() * jitter_ms
	due = maxf(due, last_due)
	queue.append({"due": due, "action": action})
	return due


func _flush(queue: Array[Dictionary]) -> void:
	var now := float(Time.get_ticks_usec()) / 1000.0
	while not queue.is_empty() and queue[0]["due"] <= now:
		var item: Dictionary = queue.pop_front()
		(item["action"] as Callable).call()
