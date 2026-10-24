class_name DevOverlay
extends CanvasLayer
## 開発・デバッグ用オーバーレイ＆コンソール（autoload: Dev）。
## F3: デバッグ統計情報オーバーレイ
## `: 開発コンソール（チート・動作確認・netsim）

var debug_visible: bool = false
var console_visible: bool = false

var _fps_label: Label
var _debug_panel: PanelContainer
var _debug_text: Label
var _console_panel: PanelContainer
var _console_output: RichTextLabel
var _console_input: LineEdit
var _cmd_history: PackedStringArray = []
var _history_index: int = -1

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_update_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 or event.is_action_pressed(&"toggle_debug"):
			debug_visible = not debug_visible
			_update_visibility()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_QUOTELEFT or event.keycode == KEY_ASCIITILDE or event.is_action_pressed(&"toggle_console"):
			console_visible = not console_visible
			_update_visibility()
			if console_visible:
				_console_input.grab_focus()
				_console_input.clear()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var show_fps: bool = Settings.get_bool("video/show_fps") if Settings != null else true
	_fps_label.visible = show_fps and not debug_visible
	if _fps_label.visible:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	if debug_visible:
		_refresh_debug_text()


func _build_ui() -> void:
	var global_theme := UiTheme.get_theme()

	# 1. 控えめなFPS表示
	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.theme = global_theme
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -120.0
	_fps_label.offset_top = 8.0
	_fps_label.offset_right = -12.0
	_fps_label.offset_bottom = 28.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 0.85))
	_fps_label.add_theme_font_size_override("font_size", 12)
	add_child(_fps_label)

	# 2. F3 デバッグパネル（左上）
	_debug_panel = PanelContainer.new()
	_debug_panel.name = "DebugPanel"
	_debug_panel.theme = global_theme
	_debug_panel.offset_left = 12.0
	_debug_panel.offset_top = 12.0
	_debug_panel.offset_right = 400.0
	_debug_panel.offset_bottom = 320.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.1, 0.88)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.6, 0.9, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	_debug_panel.add_theme_stylebox_override("panel", style)

	_debug_text = Label.new()
	_debug_text.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	_debug_text.add_theme_font_size_override("font_size", 11)
	_debug_panel.add_child(_debug_text)
	add_child(_debug_panel)

	# 3. 開発コンソール（上部全幅）
	_console_panel = PanelContainer.new()
	_console_panel.name = "ConsolePanel"
	_console_panel.theme = global_theme
	_console_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_console_panel.offset_left = 0.0
	_console_panel.offset_top = 0.0
	_console_panel.offset_right = 0.0
	_console_panel.offset_bottom = 240.0
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.02, 0.03, 0.05, 0.94)
	c_style.border_width_bottom = 2
	c_style.border_color = Color(0.15, 0.7, 0.9, 0.8)
	c_style.content_margin_left = 12.0
	c_style.content_margin_top = 8.0
	c_style.content_margin_right = 12.0
	c_style.content_margin_bottom = 8.0
	_console_panel.add_theme_stylebox_override("panel", c_style)

	var c_vbox := VBoxContainer.new()
	c_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_console_panel.add_child(c_vbox)

	_console_output = RichTextLabel.new()
	_console_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_console_output.scroll_following = true
	_console_output.bbcode_enabled = true
	_console_output.add_theme_font_size_override("normal_font_size", 12)
	_console_output.text = "[color=#4ec9b0]cl.k2 Developer Console[/color] (type 'help' for commands)\n"
	c_vbox.add_child(_console_output)

	var hbox := HBoxContainer.new()
	c_vbox.add_child(hbox)

	var prompt := Label.new()
	prompt.text = "> "
	prompt.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	hbox.add_child(prompt)

	_console_input = LineEdit.new()
	_console_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_console_input.placeholder_text = "help / god / heal / give all / spawn brute / netsim"
	_console_input.text_submitted.connect(_on_command_submitted)
	_console_input.add_theme_font_size_override("font_size", 12)
	hbox.add_child(_console_input)

	add_child(_console_panel)


func _update_visibility() -> void:
	_debug_panel.visible = debug_visible
	_console_panel.visible = console_visible


func _refresh_debug_text() -> void:
	var fps := Engine.get_frames_per_second()
	var proc_time := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_time := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)

	var text := "=== DEBUG STATS (F3) ===\n"
	text += "FPS: %d  | Process: %.2f ms | Physics: %.2f ms\n" % [fps, proc_time, phys_time]
	text += "Memory: %.1f MB\n" % static_mem

	# セッション情報
	var scene = get_tree().current_scene
	var session = scene.get("session") if scene != null else null
	if session != null:
		var mode := "SOLO (LocalSession)" if session is LocalSession else "ONLINE (ClientSession)"
		text += "Session: %s\n" % mode
		var world = session.get("world")
		if world != null:
			text += "Sim Tick: %d | Entities: P=%d E=%d B=%d Item=%d\n" % [
				world.tick, world.players.size(), world.enemies.size(), world.projectiles.size(), world.pickups.size()
			]
		# クライアント予測統計
		var rec = session.get("reconciler")
		if rec != null:
			text += "Net Rec: max_err=%.3fm snaps=%d corr=%d\n" % [rec.max_error, rec.snaps, rec.corrections]
	elif Game != null and Game.state == Game.State.SERVER:
		text += "Session: DEDICATED SERVER\n"

	# ネットワーク統計
	if Net != null:
		text += "Net Rates: In %.1f KB/s | Out %.1f KB/s (Snapshot: %d B)\n" % [Net.rate_in / 1024.0, Net.rate_out / 1024.0, Net.snapshot_bytes]
		if Net.latency_ms > 0.0 or Net.loss > 0.0:
			text += "NetSim: Latency=%.0fms Jitter=%.0fms Loss=%.1f%%\n" % [Net.latency_ms, Net.jitter_ms, Net.loss * 100.0]

	# 最新ログ
	if Log != null and Log.history.size() > 0:
		text += "\n--- Recent Log ---\n"
		var start := maxi(0, Log.history.size() - 4)
		for i in range(start, Log.history.size()):
			text += Log.history[i] + "\n"

	_debug_text.text = text


func _on_command_submitted(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	_cmd_history.append(text)
	_history_index = _cmd_history.size()
	_console_input.clear()
	_execute_console_command(text)


func _execute_console_command(line: String) -> void:
	_console_output.append_text("[color=#888888]> %s[/color]\n" % line)
	var parts := line.split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)

	match cmd:
		"help":
			_console_output.append_text("[color=#00e676]Commands:[/color]\n" +
				"  help                  - List commands\n" +
				"  god                   - Toggle god mode (Solo)\n" +
				"  heal                  - Restore HP & Energy (Solo)\n" +
				"  give <part_id|all>    - Unlock and give parts\n" +
				"  equip <part_id>       - Equip part\n" +
				"  spawn <enemy> [count] - Spawn enemies (scout, gunner, brute)\n" +
				"  killall               - Clear all active enemies\n" +
				"  tp <x> <z>            - Teleport player\n" +
				"  netsim <lag> [jitt] [loss] - Set network simulation (e.g. netsim 50 15 0.05)\n" +
				"  fps <0|1>             - Toggle permanent FPS counter\n" +
				"  clear                 - Clear console text\n")
		"clear":
			_console_output.clear()
		"fps":
			if args.size() > 0:
				var on := args[0] == "1" or args[0] == "on" or args[0] == "true"
				Settings.set_setting("video/show_fps", on)
				_console_output.append_text("FPS display: %s\n" % ("ON" if on else "OFF"))
		"netsim":
			if args.is_empty():
				_console_output.append_text("NetSim: Latency=%.0fms Jitter=%.0fms Loss=%.2f\n" % [Net.latency_ms, Net.jitter_ms, Net.loss])
			else:
				Net.latency_ms = float(args[0])
				Net.jitter_ms = float(args[1]) if args.size() > 1 else 0.0
				Net.loss = float(args[2]) if args.size() > 2 else 0.0
				_console_output.append_text("[color=#00e676]NetSim set:[/color] latency=%.0fms, jitter=%.0fms, loss=%.2f\n" % [Net.latency_ms, Net.jitter_ms, Net.loss])
		_:
			# セッションの dev_command へ転送
			var scene = get_tree().current_scene
			var session = scene.get("session") if scene != null else null
			if session != null and session.has_method("dev_command"):
				var res: String = session.dev_command(cmd, args)
				_console_output.append_text("%s\n" % res)
			else:
				_console_output.append_text("[color=#ff5555]Unknown command or no active game session: '%s'[/color]\n" % cmd)
