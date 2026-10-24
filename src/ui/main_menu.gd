class_name MainMenu
extends Node3D
## AAAクオリティの近未来ミリタリーSFメインメニュー。
## 3Dロボット展示ショーケース、斜角サイバーボタン、
## ホログラフィックバイザーフレーム、パイロット戦績ディスプレイを統合。

const SHOWCASE_INTERVAL := 2.6

var _world_view: WorldView
var _camera: Camera3D
var _robot: RobotView
var _entity := RenderFrame.Entity.new()
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _swap_timer: float = 1.2

var _root: Control
var _visor_overlay: Control
var _menu_box: VBoxContainer
var _title: Label
var _subtitle: Label
var _buttons: Dictionary = {}
var _stats_label: Label
var _notice: Label
var _online_panel: PanelContainer
var _address: LineEdit
var _online_hint: Label
var _connect_button: Button
var _back_button: Button
var _online_title: Label
var _settings: SettingsMenu
var _settings_center: CenterContainer


func _ready() -> void:
	_rng.randomize()
	_build_showcase()
	_build_ui()
	_retranslate()
	Events.profile_changed.connect(_update_stats)
	if not Game.menu_notice.is_empty():
		_show_notice(Game.menu_notice)
		Game.menu_notice = ""
	Audio.start_music()
	if not Cfg.is_headless():
		Audio.warm_up()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _title != null:
		_retranslate()


func _process(delta: float) -> void:
	_time += delta
	var angle := _time * 0.18
	_camera.position = Vector3(sin(angle) * 5.2, 2.7, cos(angle) * 5.2)
	_camera.look_at(Vector3(0, 1.0, 0))
	_entity.yaw = _time * 0.7
	_robot.apply(_entity, delta)
	_swap_timer -= delta
	if _swap_timer <= 0.0:
		_swap_timer = SHOWCASE_INTERVAL
		_shuffle_loadout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings_center.visible:
			_close_settings()
		elif _online_panel.visible:
			_show_main()
		get_viewport().set_input_as_handled()


func _build_showcase() -> void:
	_world_view = WorldView.new()
	_world_view.name = "World"
	add_child(_world_view)
	_world_view.build_arena(ArenaGenerator.generate(7, GameRules.new()))

	# 台座
	var pedestal := MeshInstance3D.new()
	pedestal.mesh = Mats.cylinder(1.3, 0.12, 40)
	pedestal.material_override = Mats.solid(Color(0.08, 0.1, 0.14), 0.6, 0.4)
	pedestal.position = Vector3(0, 0.06, 0)
	_world_view.add_child(pedestal)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.24
	torus.outer_radius = 1.34
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = Mats.glow(Color(0.2, 0.85, 1.0), 2.2)
	ring.position = Vector3(0, 0.12, 0)
	ring.scale = Vector3(1, 0.25, 1)
	_world_view.add_child(ring)

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_camera.h_offset = -1.5
	add_child(_camera)
	_camera.current = true

	_robot = RobotView.new()
	_world_view.add_child(_robot)
	_entity.kind = RenderFrame.Entity.Kind.PLAYER
	_entity.pos = Vector3(0, 0.12, 0)
	_entity.display_name = ""
	_entity.loadout = _starter_loadout().to_indices()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	layer.add_child(_root)

	# 左側グラデーション背景
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size.x = 540
	shade.color = Color(0.015, 0.025, 0.045, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	# 四隅のミリタリーフレーム
	_visor_overlay = Control.new()
	_visor_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_visor_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor_overlay.draw.connect(_draw_menu_brackets)
	_root.add_child(_visor_overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 40)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(column)

	# タイトルヘッダー
	var sub_header := Label.new()
	sub_header.text = "// PROJECT CYBER-KNIGHT // サーバー権威オンライン"
	sub_header.add_theme_font_size_override("font_size", 11)
	sub_header.add_theme_color_override("font_color", Color(0.25, 0.75, 1.0, 0.85))
	column.add_child(sub_header)

	_title = Label.new()
	_title.text = "cl.k2"
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 0.9))
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "パーツ換装 × 見下ろし型ロボットアクション"
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))
	column.add_child(_subtitle)

	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.2, 0.45, 0.65, 0.5)
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.custom_minimum_size.y = 20
	column.add_child(sep)

	_menu_box = VBoxContainer.new()
	_menu_box.custom_minimum_size.x = 360
	_menu_box.add_theme_constant_override("separation", 8)
	column.add_child(_menu_box)

	_buttons["solo"] = _make_cyber_button(_menu_box, "01 // DEPLOY SOLO (出撃)", _on_solo, Color(0.2, 0.85, 1.0))
	_buttons["online"] = _make_cyber_button(_menu_box, "02 // ONLINE MULTIPLAYER (通信対戦)", _show_online, Color(0.3, 0.95, 0.6))
	_buttons["settings"] = _make_cyber_button(_menu_box, "03 // SYSTEM SETTINGS (設定)", _open_settings, Color(0.7, 0.8, 0.9))
	if not OS.has_feature("web"):
		_buttons["quit"] = _make_cyber_button(_menu_box, "04 // DISENGAGE (終了)", _on_quit, Color(1.0, 0.4, 0.4))

	_build_online_panel(column)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(fill)

	# パイロット戦績ディスプレイ
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 0.85))
	column.add_child(_stats_label)

	_notice = Label.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position = Vector2(-300, 24)
	_notice.custom_minimum_size = Vector2(600, 0)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 16)
	_notice.add_theme_color_override("font_color", Color(1.0, 0.3, 0.35))
	_notice.modulate.a = 0.0
	_root.add_child(_notice)

	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	_settings_center.add_child(dim)
	_settings = SettingsMenu.new()
	_settings.back_requested.connect(_close_settings)
	_settings_center.add_child(_settings)
	_root.add_child(_settings_center)

	_buttons["solo"].grab_focus()


func _make_cyber_button(parent: Control, label_text: String, callback: Callable, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(360, 42)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.04, 0.07, 0.12, 0.9)
	normal.border_width_left = 3
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.18, 0.35, 0.5, 0.6)
	normal.content_margin_left = 18
	normal.content_margin_right = 14
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.16, 0.26, 0.96)
	hover.border_width_left = 4
	hover.border_color = accent_color
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.15, 0.25, 0.38, 1.0)
	pressed.border_color = accent_color
	btn.add_theme_stylebox_override("pressed", pressed)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = accent_color
	focus.border_width_left = 4
	btn.add_theme_stylebox_override("focus", focus)

	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", accent_color)
	btn.add_theme_font_size_override("font_size", 14)

	btn.pressed.connect(func() -> void:
		Audio.play_ui(&"click")
		callback.call())
	parent.add_child(btn)
	return btn


func _draw_menu_brackets() -> void:
	var w := _visor_overlay.size.x
	var h := _visor_overlay.size.y
	var margin := 20.0
	var len := 40.0
	var c := Color(0.2, 0.5, 0.7, 0.5)
	var c_bright := Color(0.3, 0.9, 1.0, 0.8)

	_visor_overlay.draw_line(Vector2(w - margin - len, margin), Vector2(w - margin, margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, margin), Vector2(w - margin, margin + len), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, margin), Vector2(w - margin - 6, margin + 6), c_bright, 2.0)

	_visor_overlay.draw_line(Vector2(w - margin - len, h - margin), Vector2(w - margin, h - margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, h - margin - len), Vector2(w - margin, h - margin), c, 1.5)

	var font := _visor_overlay.get_theme_default_font()
	var ver_text := "SYS.VER 2.0 // CORE ENGINE READY // 60 FPS"
	_visor_overlay.draw_string(font, Vector2(w - margin - 260, h - margin - 6), ver_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, 10, Color(0.4, 0.65, 0.8, 0.6))


func _build_online_panel(parent: Control) -> void:
	_online_panel = PanelContainer.new()
	_online_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.94)
	style.border_width_left = 3
	style.border_color = Color(0.2, 0.85, 1.0)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_online_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(_online_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_online_panel.add_child(box)

	_online_title = Label.new()
	_online_title.add_theme_font_size_override("font_size", 16)
	_online_title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	box.add_child(_online_title)

	_address = LineEdit.new()
	_address.text = Settings.get_string("net/server")
	if _address.text.is_empty():
		_address.text = "ws://127.0.0.1:%d" % NetProtocol.DEFAULT_PORT
	_address.placeholder_text = "ws://host:port"
	_address.custom_minimum_size = Vector2(340, 36)
	_address.text_submitted.connect(func(_t: String) -> void: _on_connect())
	box.add_child(_address)

	_online_hint = Label.new()
	_online_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_hint.custom_minimum_size.x = 340
	_online_hint.add_theme_font_size_override("font_size", 11)
	_online_hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 0.8))
	box.add_child(_online_hint)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	box.add_child(hbox)

	_connect_button = Button.new()
	_connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_connect_button.custom_minimum_size.y = 36
	_connect_button.pressed.connect(_on_connect)
	hbox.add_child(_connect_button)

	_back_button = Button.new()
	_back_button.text = "BACK"
	_back_button.custom_minimum_size = Vector2(80, 36)
	_back_button.pressed.connect(_show_main)
	hbox.add_child(_back_button)


func _on_solo() -> void:
	Game.start_solo()


func _show_online() -> void:
	_menu_box.visible = false
	_online_panel.visible = true
	_address.grab_focus()
	_address.select_all()


func _show_main() -> void:
	_online_panel.visible = false
	_menu_box.visible = true
	_buttons["solo"].grab_focus()


func _on_connect() -> void:
	var url := _address.text.strip_edges()
	if url.is_empty():
		return
	Settings.set_value("net/server", url)
	Game.start_online(url)


func _open_settings() -> void:
	_settings_center.visible = true
	_settings.refresh()


func _close_settings() -> void:
	_settings_center.visible = false
	_buttons["settings"].grab_focus()


func _on_quit() -> void:
	Game.quit_game()


func _update_stats() -> void:
	_stats_label.text = "RECORD // HIGH SCORE: %05d | ELIMINATED: %03d | LOSS: %02d | PARTS: %02d/%02d" % [
		Save.get_stat("best_score"),
		Save.get_stat("enemies"),
		Save.get_stat("deaths"),
		Save.unlocked_parts().size() + Content.starter_parts().size(),
		Content.all_parts().size(),
	]


func _show_notice(text: String) -> void:
	_notice.text = "! WARNING: " + text
	_notice.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(_notice, "modulate:a", 0.0, 0.8)


func _retranslate() -> void:
	_subtitle.text = tr("menu.subtitle")
	_update_stats()
	_online_title.text = "ONLINE SQUAD LINK // サーバー接続"
	_online_hint.text = tr("menu.online.hint")
	_connect_button.text = "CONNECT // 接続開始"


func _starter_loadout() -> Loadout:
	var loadout := Loadout.new()
	for part in Content.starter_parts():
		loadout.equip(part)
	return loadout


func _shuffle_loadout() -> void:
	var loadout := Loadout.new()
	for slot in RobotPart.Slot.values():
		var options := Content.parts_for_slot(slot)
		if not options.is_empty():
			loadout.equip(options[_rng.randi() % options.size()])
	_entity.loadout = loadout.to_indices()
	_world_view.effects.shockwave(Vector3(0, 0.15, 0), Color(0.2, 0.85, 1.0), 2.0, 0.6)
	Audio.play_ui(&"equip", -6.0)
