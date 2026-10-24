class_name MainMenu
extends Node3D
## メインメニュー。背景は、パーツを次々に付け替えるロボットの展示（ゲームと同じビューを使う）。
## ソロ / オンライン接続 / 設定 / 終了。プロフィールの戦績も出す。

const SHOWCASE_INTERVAL := 2.6

var _world_view: WorldView
var _camera: Camera3D
var _robot: RobotView
var _entity := RenderFrame.Entity.new()
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _swap_timer: float = 1.2

var _root: Control
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
	# 展示用のカメラは、ゆっくり円を描く
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


# --- 構築 ---

func _build_showcase() -> void:
	_world_view = WorldView.new()
	_world_view.name = "World"
	add_child(_world_view)
	_world_view.build_arena(ArenaGenerator.generate(7, GameRules.new()))

	# 台座
	var pedestal := MeshInstance3D.new()
	pedestal.mesh = Mats.cylinder(1.3, 0.12, 40)
	pedestal.material_override = Mats.solid(Color(0.1, 0.11, 0.14), 0.6, 0.4)
	pedestal.position = Vector3(0, 0.06, 0)
	_world_view.add_child(pedestal)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.24
	torus.outer_radius = 1.34
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = Mats.glow(UiTheme.ACCENT, 2.0)
	ring.position = Vector3(0, 0.12, 0)
	ring.scale = Vector3(1, 0.25, 1)
	_world_view.add_child(ring)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	# 画面の右寄りにロボットが見えるよう、視野を左へずらす（左はメニュー）
	_camera.h_offset = -1.6
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

	# 左側を少し暗くして、文字を読みやすくする
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.custom_minimum_size.x = 520
	shade.color = Color(0.02, 0.025, 0.04, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_bottom", 48)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_title.add_theme_constant_override("outline_size", 10)
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 16)
	_subtitle.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	column.add_child(_subtitle)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 28
	column.add_child(spacer)

	_menu_box = VBoxContainer.new()
	_menu_box.custom_minimum_size.x = 340
	_menu_box.add_theme_constant_override("separation", 10)
	column.add_child(_menu_box)
	_buttons["solo"] = _make_button(_menu_box, _on_solo)
	_buttons["online"] = _make_button(_menu_box, _show_online)
	_buttons["settings"] = _make_button(_menu_box, _open_settings)
	if not OS.has_feature("web"):
		_buttons["quit"] = _make_button(_menu_box, _on_quit)

	_build_online_panel(column)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(fill)
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	column.add_child(_stats_label)

	_notice = Label.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position = Vector2(-300, 24)
	_notice.custom_minimum_size = Vector2(600, 0)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.add_theme_color_override("font_color", UiTheme.BAD)
	_notice.modulate.a = 0.0
	_root.add_child(_notice)

	_settings_center = CenterContainer.new()
	_settings_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_center.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	_settings_center.add_child(dim)
	_settings = SettingsMenu.new()
	_settings.back_requested.connect(_close_settings)
	_settings_center.add_child(_settings)
	_root.add_child(_settings_center)
	_buttons["solo"].grab_focus()


func _build_online_panel(parent: Control) -> void:
	_online_panel = PanelContainer.new()
	_online_panel.visible = false
	_online_panel.custom_minimum_size.x = 420
	parent.add_child(_online_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_online_panel.add_child(box)
	_online_title = Label.new()
	_online_title.add_theme_font_size_override("font_size", 20)
	_online_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(_online_title)
	_address = LineEdit.new()
	_address.text = Settings.get_string("net/server")
	_address.text_submitted.connect(func(_text: String) -> void: _on_connect())
	box.add_child(_address)
	_online_hint = Label.new()
	_online_hint.add_theme_font_size_override("font_size", 12)
	_online_hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_online_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_online_hint.custom_minimum_size.x = 380
	box.add_child(_online_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_connect_button = _make_button(row, _on_connect)
	_connect_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button = _make_button(row, _show_main)


func _make_button(parent: Control, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func() -> void:
		Audio.play_ui(&"ui_click")
		callback.call())
	button.mouse_entered.connect(func() -> void: Audio.play_ui(&"ui_hover", -8.0))
	parent.add_child(button)
	return button


# --- 操作 ---

func _on_solo() -> void:
	Game.start_solo()


func _show_online() -> void:
	_menu_box.visible = false
	_online_panel.visible = true
	_address.grab_focus()
	_address.caret_column = _address.text.length()


func _show_main() -> void:
	_online_panel.visible = false
	_menu_box.visible = true
	(_buttons["online"] as Button).grab_focus()


func _open_settings() -> void:
	_settings_center.visible = true
	_settings.refresh()


func _close_settings() -> void:
	_settings_center.visible = false
	(_buttons["settings"] as Button).grab_focus()


func _on_quit() -> void:
	Game.quit_game()


func _on_connect() -> void:
	var url := _address.text.strip_edges()
	if url.is_empty():
		return
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	# HTTPS のページからは、暗号化されていない ws:// には接続できない（ブラウザが遮断する）
	if OS.has_feature("web") and url.begins_with("ws://") and not _is_local(url):
		if str(JavaScriptBridge.eval("location.protocol")) == "https:":
			_show_notice(tr("menu.online.mixed_content"))
			Audio.play_ui(&"ui_error")
			return
	Settings.set_value("net/server", url)
	Game.start_online(url)


func _is_local(url: String) -> bool:
	return url.contains("://localhost") or url.contains("://127.0.0.1") or url.contains("://[::1]")


func _show_notice(text: String) -> void:
	_notice.text = text
	_notice.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(_notice, "modulate:a", 0.0, 0.6)


# --- 展示 ---

func _starter_loadout() -> Loadout:
	var loadout := Loadout.new()
	for part in Content.starter_parts():
		loadout.equip(part)
	return loadout


func _shuffle_loadout() -> void:
	var loadout := Loadout.new()
	for slot in RobotPart.Slot.values():
		var options := Content.parts_for_slot(slot)
		loadout.equip(options[_rng.randi() % options.size()])
	_entity.loadout = loadout.to_indices()
	_world_view.effects.shockwave(Vector3(0, 0.15, 0), UiTheme.ACCENT, 2.0, 0.6)
	Audio.play_ui(&"equip", -6.0)


func _update_stats() -> void:
	_stats_label.text = "%s %d     %s %d     %s %d     %s %d / %d" % [
		tr("menu.stat.best"), Save.get_stat("best_score"),
		tr("menu.stat.enemies"), Save.get_stat("enemies"),
		tr("menu.stat.deaths"), Save.get_stat("deaths"),
		tr("menu.stat.parts"), Save.unlocked_parts().size() + Content.starter_parts().size(), Content.all_parts().size()]


func _retranslate() -> void:
	_title.text = tr("ui.title")
	_subtitle.text = tr("menu.subtitle")
	(_buttons["solo"] as Button).text = tr("menu.solo")
	(_buttons["online"] as Button).text = tr("menu.online")
	(_buttons["settings"] as Button).text = tr("menu.settings")
	if _buttons.has("quit"):
		(_buttons["quit"] as Button).text = tr("menu.quit")
	_online_title.text = tr("menu.online.title")
	_online_hint.text = tr("menu.online.hint")
	_connect_button.text = tr("menu.connect")
	_back_button.text = tr("settings.back")
	_update_stats()
