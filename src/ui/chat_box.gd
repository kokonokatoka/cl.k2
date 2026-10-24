class_name ChatBox
extends CanvasLayer
## オンラインのチャット。chat アクション（Enter / T）で入力欄が開き、Enter で送信、Esc で閉じる。
## 受け取った発言は一定時間だけ画面の左下に出る。入力中は操作入力を止める。

const MESSAGE_SECONDS := 9.0
const MAX_MESSAGES := 8

var _session: GameSession
var _log: VBoxContainer
var _input: LineEdit


func _ready() -> void:
	layer = 14
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 24
	box.offset_top = -240
	box.offset_right = 460
	box.offset_bottom = -50
	box.custom_minimum_size = Vector2(436, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(box)
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 2)
	box.add_child(_log)
	_input = LineEdit.new()
	_input.max_length = NetProtocol.MAX_CHAT_LENGTH
	_input.visible = false
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_gui_input)
	box.add_child(_input)
	visible = false


## セッションに合わせる。チャットはオンラインのときだけ使える
func setup(session: GameSession) -> void:
	_session = session
	visible = session.is_online()
	_input.placeholder_text = tr("chat.placeholder")


func is_typing() -> bool:
	return _input != null and _input.visible and _input.has_focus()


func add_message(sender: String, text: String) -> void:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 450
	label.add_theme_font_size_override("font_size", 14)
	if sender.is_empty():
		label.text = text
		label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	else:
		label.text = "%s: %s" % [sender, text]
	_log.add_child(label)
	while _log.get_child_count() > MAX_MESSAGES:
		var oldest := _log.get_child(0)
		_log.remove_child(oldest)
		oldest.queue_free()
	var tween := create_tween()
	tween.tween_interval(MESSAGE_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if _session == null or not _session.is_online() or is_typing():
		return
	if event.is_action_pressed("chat"):
		_input.visible = true
		_input.text = ""
		_input.grab_focus()
		get_viewport().set_input_as_handled()


func _on_submitted(text: String) -> void:
	if not text.strip_edges().is_empty():
		_session.send_chat(text)
	_close_input()


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_input()
		_input.accept_event()


func _close_input() -> void:
	_input.release_focus()
	_input.visible = false
	_input.text = ""
