class_name SettingsMenu
extends PanelContainer
## 設定画面（音量・映像・ゲーム・操作・プロフィール）。メインメニューとポーズメニューで共用する。
## 値は Settings に即時反映・保存される。表示は refresh() で現在値に合わせる。

signal back_requested

var _tabs: TabContainer
## 設定キー -> 更新用のコールバック（refresh で現在値を流し込む）
var _refreshers: Array[Callable] = []
var _rebinding: StringName = &""
var _rebind_buttons: Dictionary = {}
var _rebind_hint: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(680, 480)
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _tabs != null:
		_rebuild.call_deferred()


## 表示を現在の設定値に合わせる
func refresh() -> void:
	for refresher in _refreshers:
		refresher.call()
	_update_rebind_buttons()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_refreshers.clear()
	_rebind_buttons.clear()
	_build()


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = tr("menu.settings")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_add_tab(tr("settings.tab.audio"), _build_audio)
	_add_tab(tr("settings.tab.video"), _build_video)
	_add_tab(tr("settings.tab.game"), _build_game)
	_add_tab(tr("settings.tab.controls"), _build_controls)
	_add_tab(tr("settings.tab.profile"), _build_profile)

	var footer := HBoxContainer.new()
	box.add_child(footer)
	var reset := Button.new()
	reset.text = tr("settings.reset")
	reset.pressed.connect(_on_reset_pressed)
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back := Button.new()
	back.text = tr("settings.back")
	back.custom_minimum_size = Vector2(140, 0)
	back.pressed.connect(func() -> void:
		Audio.play_ui(&"ui_back")
		back_requested.emit())
	footer.add_child(back)
	refresh()


func _add_tab(title: String, builder: Callable) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.name = title
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 14)
	margin.name = title
	margin.add_child(page)
	_tabs.add_child(margin)
	builder.call(page)


# --- タブの中身 ---

func _build_audio(page: VBoxContainer) -> void:
	_add_slider(page, "audio/master", "settings.audio.master", 0.0, 1.0, 0.05, true)
	_add_slider(page, "audio/music", "settings.audio.music", 0.0, 1.0, 0.05, true)
	_add_slider(page, "audio/sfx", "settings.audio.sfx", 0.0, 1.0, 0.05, true)
	_add_slider(page, "audio/ui", "settings.audio.ui", 0.0, 1.0, 0.05, true)


func _build_video(page: VBoxContainer) -> void:
	if not OS.has_feature("web"):
		_add_check(page, "video/fullscreen", "settings.video.fullscreen")
	_add_check(page, "video/vsync", "settings.video.vsync")
	_add_option(page, "video/msaa", "settings.video.msaa", [0, 1, 2, 3], ["settings.off", "2x", "4x", "8x"])
	_add_check(page, "video/shadows", "settings.video.shadows")
	_add_slider(page, "video/ui_scale", "settings.video.ui_scale", 0.75, 1.5, 0.05, false)
	_add_check(page, "video/show_fps", "settings.video.show_fps")


func _build_game(page: VBoxContainer) -> void:
	_add_option(page, "game/language", "settings.game.language", ["auto", "en", "ja"],
		["settings.language.auto", "English", "日本語"])
	_add_slider(page, "game/screen_shake", "settings.game.screen_shake", 0.0, 1.0, 0.05, false)
	_add_slider(page, "game/camera_lookahead", "settings.game.camera_lookahead", 0.0, 1.0, 0.05, false)
	_add_check(page, "game/damage_numbers", "settings.game.damage_numbers")


func _build_controls(page: VBoxContainer) -> void:
	_rebind_hint = Label.new()
	_rebind_hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_rebind_hint.add_theme_font_size_override("font_size", 13)
	_rebind_hint.text = tr("settings.controls.hint")
	page.add_child(_rebind_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 250)
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for action in InputActions.REMAPPABLE:
		var label := Label.new()
		label.text = tr("action.%s" % action)
		label.custom_minimum_size.x = 260
		grid.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 0)
		button.pressed.connect(_begin_rebind.bind(action))
		grid.add_child(button)
		_rebind_buttons[action] = button
	var reset := Button.new()
	reset.text = tr("settings.controls.reset")
	reset.pressed.connect(func() -> void:
		Settings.reset_all_bindings()
		_update_rebind_buttons())
	page.add_child(reset)


func _build_profile(page: VBoxContainer) -> void:
	var name_row := _row(page, "settings.profile.name")
	var name_edit := LineEdit.new()
	name_edit.max_length = NetProtocol.MAX_NAME_LENGTH
	name_edit.custom_minimum_size.x = 240
	name_edit.placeholder_text = "Player"
	name_edit.text_changed.connect(func(text: String) -> void: Settings.set_value("player/name", text))
	name_row.add_child(name_edit)
	_refreshers.append(func() -> void: name_edit.text = Settings.get_string("player/name"))

	var color_row := _row(page, "settings.profile.color")
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(120, 32)
	picker.color_changed.connect(func(color: Color) -> void: Settings.set_value("player/color", color.to_html(false)))
	color_row.add_child(picker)
	_refreshers.append(func() -> void: picker.color = Color.html(Settings.get_string("player/color")))


# --- 部品 ---

func _row(page: Control, label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = tr(label_key)
	label.custom_minimum_size.x = 260
	row.add_child(label)
	page.add_child(row)
	return row


func _add_slider(page: Control, key: String, label_key: String, min_value: float, max_value: float, step: float, click_on_release: bool) -> void:
	var row := _row(page, label_key)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(240, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 56
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		Settings.set_value(key, value)
		value_label.text = "%d%%" % roundi(value * 100.0))
	if click_on_release:
		slider.drag_ended.connect(func(_changed: bool) -> void: Audio.play_ui(&"ui_click"))
	_refreshers.append(func() -> void:
		slider.set_value_no_signal(Settings.get_float(key))
		value_label.text = "%d%%" % roundi(Settings.get_float(key) * 100.0))


func _add_check(page: Control, key: String, label_key: String) -> void:
	var row := _row(page, label_key)
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void:
		Audio.play_ui(&"ui_click")
		Settings.set_value(key, on))
	row.add_child(check)
	_refreshers.append(func() -> void: check.set_pressed_no_signal(Settings.get_bool(key)))


func _add_option(page: Control, key: String, label_key: String, values: Array, labels: Array) -> void:
	var row := _row(page, label_key)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 200
	for i in values.size():
		var text := String(labels[i])
		option.add_item(tr(text) if text.begins_with("settings.") else text, i)
	option.item_selected.connect(func(index: int) -> void:
		Audio.play_ui(&"ui_click")
		Settings.set_value(key, values[index]))
	row.add_child(option)
	_refreshers.append(func() -> void: option.select(maxi(0, values.find(Settings.get_value(key)))))


# --- キーの割り当て ---

func _begin_rebind(action: StringName) -> void:
	_rebinding = action
	(_rebind_buttons[action] as Button).text = tr("settings.controls.press_key")
	Audio.play_ui(&"ui_click")


func _input(event: InputEvent) -> void:
	if _rebinding == &"" or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_rebinding = &""
		_update_rebind_buttons()
		get_viewport().set_input_as_handled()
		return
	var binding := InputActions.binding_from_event(event)
	if binding.is_empty():
		return
	Settings.set_binding(_rebinding, [binding])
	_rebinding = &""
	_update_rebind_buttons()
	Audio.play_ui(&"ui_confirm")
	get_viewport().set_input_as_handled()


func _update_rebind_buttons() -> void:
	var overrides := Settings.get_bindings()
	for action: StringName in _rebind_buttons:
		var button: Button = _rebind_buttons[action]
		if action == _rebinding:
			continue
		var bindings := InputActions.effective_bindings(action, overrides)
		var names := PackedStringArray()
		for binding: Dictionary in bindings:
			if binding.has("k") or binding.has("m"):
				names.append(InputActions.describe(binding))
		button.text = " / ".join(names) if not names.is_empty() else tr("settings.controls.unbound")


func _on_reset_pressed() -> void:
	Audio.play_ui(&"ui_back")
	Settings.reset_to_defaults()
	refresh()
