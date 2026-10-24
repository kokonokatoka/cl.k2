class_name BotClient
extends Node
## ビューなしで動く自動操縦のクライアント（結合テスト用。`--bot-client --connect=ws://…`）。
## ClientSession と BotBrain をそのまま使い、結果を JSON に書いて終了する。

var session: ClientSession
var brain: BotBrain

var _duration: float = 10.0
var _result_path: String = ""
var _elapsed: float = 0.0
var _rejected_reason: String = ""
var _connected: bool = false
var _start_position: Vector3 = Vector3.ZERO
var _distance: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _damage_dealt: float = 0.0
var _kills: int = 0
var _deaths: int = 0
var _seen_events: int = 0
var _chat_received: int = 0
var _chat_sent: int = 0
var _done: bool = false


func start(url: String, display_name: String) -> void:
	_duration = Cfg.get_float("duration", 10.0)
	_result_path = Cfg.get_string("result")
	session = ClientSession.new()
	session.name = "Session"
	add_child(session)
	session.ended.connect(_on_ended)
	session.sim_event.connect(_on_sim_event)
	session.chat_received.connect(func(_sender: String, _text: String) -> void: _chat_received += 1)
	session.ready_to_play.connect(_on_ready)
	brain = BotBrain.new(session, Cfg.get_int("bot-seed", 1))
	session.input_provider = brain.sample
	session.start(url, display_name)


func _physics_process(delta: float) -> void:
	if session == null:
		return
	_elapsed += delta
	if session.is_ready():
		_distance += session.local_player.pos.distance_to(_last_position)
		_last_position = session.local_player.pos
		# 少しの間チャットを送ってみる（経路の確認）
		if _elapsed > 2.0 and _chat_sent == 0:
			_chat_sent = 1
			session.send_chat("hello from bot")
	if _elapsed >= _duration:
		_finish()


func _on_ready() -> void:
	_connected = true
	_start_position = session.local_player.pos
	_last_position = _start_position


func _on_ended(reason: String) -> void:
	_rejected_reason = reason
	_finish()


func _on_sim_event(event: SimEvent) -> void:
	_seen_events += 1
	if event.type == SimEvent.Type.HIT and event.a == session.local_id:
		_damage_dealt += event.value
	if event.type == SimEvent.Type.KILL:
		if event.a == session.local_id:
			_kills += 1
		if event.b == session.local_id and event.tag == &"player":
			_deaths += 1


func _finish() -> void:
	if _done:
		return
	_done = true
	set_physics_process(false)
	var reconciler := session.reconciler
	var result := {
		"connected": _connected,
		"ended_reason": _rejected_reason,
		"phase": int(session.phase),
		"snapshots": session.snapshots_received,
		"events": session.events_received,
		"max_players_seen": session.max_players_seen,
		"distance": _distance,
		"damage_dealt": _damage_dealt,
		"kills": _kills,
		"deaths": _deaths,
		"chat_received": _chat_received,
		"ping_ms": session.ping_ms(),
		"corrections": reconciler.corrections if reconciler != null else 0,
		"snaps": reconciler.snaps if reconciler != null else 0,
		"max_error": reconciler.max_error if reconciler != null else 0.0,
		"snapshot_bytes": Net.snapshot_bytes,
		"local_id": session.local_id,
	}
	Log.info("bot", "finished: %s" % JSON.stringify(result))
	if not _result_path.is_empty():
		var file := FileAccess.open(_result_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result))
			file.close()
	session.ended.disconnect(_on_ended)
	session.shutdown("bot finished")
	get_tree().quit()
