extends Node

# WebSocketベースのマルチプレイヤー・ネットワーク管理
signal connected_to_server
signal connection_closed
signal player_joined(id: String, player_name: String, x: float, y: float, color_hex: String)
signal player_left(id: String)
signal player_moved(id: String, x: float, y: float)
signal player_acted(id: String, action_type: String, extra_data: Dictionary)
signal chat_received(sender_name: String, message: String)

var socket: WebSocketPeer = WebSocketPeer.new()
var is_online: bool = false
var my_id: String = ""
var my_name: String = "Player"
var my_color_hex: String = "#3498db"

func _ready() -> void:
	# ランダムなプレイヤーIDを生成
	my_id = "user_" + str(randi() % 10000)

func connect_to_server(url: String, player_name: String, color_hex: String) -> Error:
	my_name = player_name
	my_color_hex = color_hex
	socket = WebSocketPeer.new()
	var err = socket.connect_to_url(url)
	if err != OK:
		push_error("WebSocket connection initiation failed: " + str(err))
		return err
	return OK

func disconnect_from_server() -> void:
	if is_online:
		send_data({ "type": "leave", "id": my_id })
		socket.close()
		is_online = false
		connection_closed.emit()

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_online:
			is_online = true
			connected_to_server.emit()
			# サーバーに自己紹介を送信
			send_data({
				"type": "join",
				"id": my_id,
				"name": my_name,
				"color": my_color_hex,
				"x": 576.0,
				"y": 324.0
			})
			
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var msg_str = packet.get_string_from_utf8()
			_handle_json_message(msg_str)
			
	elif state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
		if is_online:
			is_online = false
			connection_closed.emit()

func send_data(data: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str = JSON.stringify(data)
		socket.send_text(json_str)

func send_movement(pos: Vector2) -> void:
	if is_online:
		send_data({
			"type": "move",
			"id": my_id,
			"x": pos.x,
			"y": pos.y
		})

func send_action(action_type: String, extra: Dictionary = {}) -> void:
	if is_online:
		var payload = {
			"type": "action",
			"id": my_id,
			"action": action_type
		}
		for k in extra.keys():
			payload[k] = extra[k]
		send_data(payload)

func _handle_json_message(text: String) -> void:
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		return
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
		
	var type = data.get("type", "")
	var sender_id = data.get("id", "")
	
	# 自分自身のメッセージは無視
	if sender_id == my_id and type != "welcome":
		return
		
	match type:
		"welcome":
			# サーバーが割り振った固有IDがあれば採用
			if data.has("assigned_id"):
				my_id = data["assigned_id"]
			# 既存プレイヤー一覧の同期
			if data.has("players"):
				for p in data["players"]:
					if p["id"] != my_id:
						player_joined.emit(p["id"], p.get("name", "Player"), p.get("x", 0.0), p.get("y", 0.0), p.get("color", "#3498db"))
		"join":
			player_joined.emit(sender_id, data.get("name", "Player"), data.get("x", 0.0), data.get("y", 0.0), data.get("color", "#3498db"))
		"leave":
			player_left.emit(sender_id)
		"move":
			player_moved.emit(sender_id, float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		"action":
			player_acted.emit(sender_id, data.get("action", ""), data)
		"chat":
			chat_received.emit(data.get("sender", "Anonymous"), data.get("text", ""))
