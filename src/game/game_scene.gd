class_name GameScene
extends Node3D
## ゲーム中のシーン。セッション（ソロ/オンライン）を作り、ビュー・カメラ・視界・HUD・入力をつなぐ。
## ここは「つなぐだけ」で、ゲームのルールはシミュレーション（src/sim）にある。

## 発砲したときの画面揺れ（武器ごと）
const SHAKE_BY_WEAPON := {&"blaster": 0.05, &"scatter": 0.22, &"pulse": 0.035, &"rail": 0.38}
const SLOT_ACTIONS := {
	&"swap_eyes": RobotPart.Slot.EYES,
	&"swap_legs": RobotPart.Slot.LEGS,
	&"swap_arms": RobotPart.Slot.ARMS,
	&"swap_core": RobotPart.Slot.CORE,
}

var session: GameSession
var world_view: WorldView
var camera: TopDownCamera
var sampler: InputSampler
var vision: VisionOverlay
var hud: Hud
var overhead: OverheadLabels
var pause_menu: PauseMenu
var scoreboard: ScoreboardPanel
var chat: ChatBox

var _status_label: Label
var _bot: BotBrain
var _arena_built: bool = false


func _ready() -> void:
	world_view = WorldView.new()
	world_view.name = "World"
	add_child(world_view)
	camera = TopDownCamera.new()
	camera.name = "Camera"
	add_child(camera)
	sampler = InputSampler.new()
	sampler.name = "InputSampler"
	add_child(sampler)

	var overhead_layer := CanvasLayer.new()
	overhead_layer.layer = 4
	add_child(overhead_layer)
	overhead = OverheadLabels.new()
	overhead.theme = UiTheme.get_theme()
	overhead_layer.add_child(overhead)
	vision = VisionOverlay.new()
	vision.name = "VisionOverlay"
	add_child(vision)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	scoreboard = ScoreboardPanel.new()
	scoreboard.name = "Scoreboard"
	add_child(scoreboard)
	chat = ChatBox.new()
	chat.name = "Chat"
	add_child(chat)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.resumed.connect(_on_resumed)
	pause_menu.leave_requested.connect(_on_leave_requested)
	_build_status_label()

	_start_session()


func _exit_tree() -> void:
	if not Cfg.is_headless():
		Input.set_custom_mouse_cursor(null)
	Audio.stop_music()
	if session != null:
		if session.ended.is_connected(_on_session_ended):
			session.ended.disconnect(_on_session_ended)
		session.shutdown("scene closed")
		Events.session_ended.emit("scene closed")


func _process(delta: float) -> void:
	if session == null:
		return
	if not _arena_built:
		_status_label.text = tr(session.status_key())
		_status_label.visible = true
		return
	_status_label.visible = false
	sampler.enabled = not session.paused and not chat.is_typing() and not pause_menu.visible
	var frame := session.sample(Engine.get_physics_interpolation_fraction())
	world_view.update_frame(frame, delta)
	hud.update_frame(frame, delta)
	if frame.local != null and session.local_player != null:
		var look: Variant = null if sampler.using_gamepad else sampler.aim_point_on_ground()
		camera.follow(frame.local.pos, look, delta)
		var stats := session.local_player.stats
		vision.update_vision(camera, frame.local.pos, stats.vision_range, stats.vision_tint, delta)
	overhead.update_frame(frame, camera)


func _unhandled_input(event: InputEvent) -> void:
	if session == null or not _arena_built:
		if event.is_action_pressed("pause"):
			_on_leave_requested()
		return
	if event.is_action_pressed("pause") and not pause_menu.visible:
		pause_menu.open(session)
		get_viewport().set_input_as_handled()
		return
	for action: StringName in SLOT_ACTIONS:
		if event.is_action_pressed(action):
			session.cycle_slot(SLOT_ACTIONS[action], 1)
			Audio.play_ui(&"equip")
			get_viewport().set_input_as_handled()
			return


func _start_session() -> void:
	var display_name: String = Settings.get_string("player/name")
	if display_name.is_empty():
		display_name = Save.player_name() if not Save.player_name().is_empty() else "Player"

	var mode: String = Game.pending.get("mode", "solo")
	if mode == "online":
		var client := ClientSession.new()
		client.name = "Session"
		add_child(client)
		session = client
		session.ended.connect(_on_session_ended)
		session.notice.connect(func(text: String, kind: int) -> void: hud.toast(text, kind))
		client.start(String(Game.pending.get("url", "")), display_name)
	else:
		var local := LocalSession.new()
		local.name = "Session"
		add_child(local)
		session = local
		local.start(int(Game.pending.get("seed", 1)), GameRules.new(), display_name)

	if Cfg.get_bool("autoplay"):
		_bot = BotBrain.new(session, int(Cfg.get_int("bot-seed", 7)))
		session.input_provider = _bot.sample
	else:
		session.input_provider = sampler.sample
	sampler.local_player_getter = func() -> SimPlayer: return session.local_player
	world_view.color_provider = session.player_color
	session.sim_event.connect(_on_sim_event)
	session.chat_received.connect(chat.add_message)
	chat.setup(session)

	if session.is_ready():
		_on_session_ready()
	else:
		session.ready_to_play.connect(_on_session_ready, CONNECT_ONE_SHOT)


## 世界の形と自分のプレイヤーが揃った。ここから描画を始める
func _on_session_ready() -> void:
	world_view.local_id = session.local_id
	world_view.build_arena(session.geometry)
	hud.bind(session)
	scoreboard.bind(session)
	camera.snap_to(session.local_player.pos)
	_arena_built = true
	if not Cfg.is_headless():
		_set_crosshair_cursor()
		Audio.start_music()
		Audio.warm_up()
	Events.session_started.emit()


func _on_sim_event(event: SimEvent) -> void:
	world_view.handle_event(event)
	hud.handle_event(event)
	var local_id := session.local_id
	match event.type:
		SimEvent.Type.SHOT:
			if event.a == local_id:
				camera.add_trauma(SHAKE_BY_WEAPON.get(event.tag, 0.05))
		SimEvent.Type.HIT:
			if event.b == local_id and event.tag == &"player":
				camera.add_trauma(0.4)
				vision.flash_hit(minf(1.0, event.value / 25.0))
		SimEvent.Type.KILL:
			if session.local_player != null and event.pos.distance_to(session.local_player.pos) < 14.0:
				camera.add_trauma(0.3 if event.b == local_id else 0.14)
		SimEvent.Type.LAND:
			if event.a == local_id:
				camera.add_trauma(0.08)


func _on_resumed() -> void:
	if session != null:
		session.paused = false
	if not Cfg.is_headless():
		_set_crosshair_cursor()


func _on_leave_requested() -> void:
	Game.go_menu()


## サーバーに断られた・切れたとき: メッセージを持ってメニューへ戻る
func _on_session_ended(reason: String) -> void:
	if reason != "" and reason != "left":
		var key := "net.error.%s" % reason
		var text := tr(key)
		Game.menu_notice = text if text != key else tr("net.error.disconnected")
	Game.go_menu()


func _build_status_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.theme = UiTheme.get_theme()
	_status_label.add_theme_font_size_override("font_size", 28)
	layer.add_child(_status_label)


## 照準のカーソル（リング＋中心点）
func _set_crosshair_cursor() -> void:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5 - Vector2(0.5, 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center)
			var alpha := 0.0
			if absf(d - 10.0) < 1.0:
				alpha = 1.0
			elif d < 1.6:
				alpha = 1.0
			elif absf(x - center.x) < 0.8 and d > 12.0 and d < 15.5:
				alpha = 0.9
			elif absf(y - center.y) < 0.8 and d > 12.0 and d < 15.5:
				alpha = 0.9
			if alpha > 0.0:
				image.set_pixel(x, y, Color(1.0, 0.7, 0.3, alpha))
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(image), Input.CURSOR_ARROW, Vector2(size, size) * 0.5)
