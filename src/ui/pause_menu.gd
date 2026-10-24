class_name PauseMenu
extends CanvasLayer
## ポーズメニュー。ソロでは世界が止まり、オンラインでは止められないので入力だけが無効になる。

signal resumed
signal leave_requested

var _session: GameSession
var _root: Control
var _main_panel: PanelContainer
var _settings: SettingsMenu
var _title: Label
var _resume: Button
var _settings_button: Button
var _leave: Button
var _note: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_main_panel = PanelContainer.new()
	center.add_child(_main_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	box.add_theme_constant_override("separation", 10)
	_main_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_resume = _make_button(box, close)
	_settings_button = _make_button(box, _open_settings)
	_leave = _make_button(box, _on_leave)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_note.add_theme_font_size_override("font_size", 12)
	box.add_child(_note)

	_settings = SettingsMenu.new()
	_settings.visible = false
	_settings.back_requested.connect(_close_settings)
	center.add_child(_settings)
	visible = false
	_retranslate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _title != null:
		_retranslate()


func open(session: GameSession) -> void:
	_session = session
	session.paused = true
	_note.text = tr("pause.online_note") if session.is_online() else ""
	_main_panel.visible = true
	_settings.visible = false
	visible = true
	if not Cfg.is_headless():
		Input.set_custom_mouse_cursor(null)
	Audio.play_ui(&"ui_confirm")
	_resume.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	Audio.play_ui(&"ui_back")
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		if _settings.visible:
			_close_settings()
		else:
			close()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	_main_panel.visible = false
	_settings.visible = true
	_settings.refresh()


func _close_settings() -> void:
	_settings.visible = false
	_main_panel.visible = true
	_resume.grab_focus()


func _on_leave() -> void:
	visible = false
	leave_requested.emit()


func _make_button(parent: Control, callback: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(func() -> void:
		Audio.play_ui(&"ui_click")
		callback.call())
	button.mouse_entered.connect(func() -> void: Audio.play_ui(&"ui_hover", -8.0))
	parent.add_child(button)
	return button


func _retranslate() -> void:
	_title.text = tr("pause.title")
	_resume.text = tr("pause.resume")
	_settings_button.text = tr("menu.settings")
	_leave.text = tr("pause.leave")
