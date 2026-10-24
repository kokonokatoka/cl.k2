class_name GarageMenu
extends Control
## AAAクオリティのガレージ・機体アセンブリUI。
## メカ換装、スロット別パーツ一覧、性能比較パラメータバー、
## リアルタイム3Dプレビュー連携、カラーリング変更を完全統合。

signal back_requested
signal deploy_requested

const SLOTS: Array[RobotPart.Slot] = [
	RobotPart.Slot.EYES,
	RobotPart.Slot.LEGS,
	RobotPart.Slot.ARMS,
	RobotPart.Slot.CORE,
]

var _current_slot: RobotPart.Slot = RobotPart.Slot.EYES
var _current_loadout: Loadout
var _hovered_part: RobotPart
var _robot_preview_callback: Callable

var _slot_buttons: Dictionary = {}
var _parts_container: GridContainer
var _stat_bars: Dictionary = {}
var _part_detail_title: Label
var _part_detail_desc: Label
var _part_detail_stats: Label
var _equip_button: Button
var _color_picker: ColorPickerButton


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()


func _ready() -> void:
	_current_loadout = Save.last_loadout().duplicate_loadout()
	if _current_loadout.parts().is_empty():
		for p in Content.starter_parts():
			_current_loadout.equip(p)
	_build_ui()
	_select_slot(RobotPart.Slot.EYES)
	_update_spec_bars()


func set_robot_preview_callback(callback: Callable) -> void:
	_robot_preview_callback = callback
	if _robot_preview_callback.is_valid() and _current_loadout != null:
		_robot_preview_callback.call(_current_loadout)


func refresh() -> void:
	_current_loadout = Save.last_loadout().duplicate_loadout()
	_update_slot_indicators()
	_populate_parts_list()
	_update_spec_bars()
	if _robot_preview_callback.is_valid():
		_robot_preview_callback.call(_current_loadout)


func _build_ui() -> void:
	# 暗色グラデーション背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.07, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 全体マージン
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var v_box := VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 14)
	margin.add_child(v_box)

	# 1. ヘッダー
	var header := HBoxContainer.new()
	v_box.add_child(header)

	var title := Label.new()
	title.text = "ASSEMBLY DOCK // 機体換装・兵装換装"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0))
	header.add_child(title)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	var color_label := Label.new()
	color_label.text = "PAINT // 機体塗装:"
	color_label.add_theme_font_size_override("font_size", 13)
	color_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	header.add_child(color_label)

	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(80, 26)
	_color_picker.edit_alpha = false
	_color_picker.color = Color.html(Settings.get_string("player/color"))
	_color_picker.color_changed.connect(_on_color_changed)
	header.add_child(_color_picker)

	# 2. メイン作業領域（左右2ペイン構造）
	var content_h := HBoxContainer.new()
	content_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_h.add_theme_constant_override("separation", 24)
	v_box.add_child(content_h)

	# 左ペイン: スロット選択 ＆ パーツ一覧
	var left_pane := VBoxContainer.new()
	left_pane.custom_minimum_size.x = 440
	left_pane.add_theme_constant_override("separation", 10)
	content_h.add_child(left_pane)

	# スロットタブ
	var slot_tabs := HBoxContainer.new()
	slot_tabs.add_theme_constant_override("separation", 6)
	left_pane.add_child(slot_tabs)

	var slot_names := {
		RobotPart.Slot.EYES: "OPTICS\n光学アイ",
		RobotPart.Slot.LEGS: "CHASSIS\n推進脚部",
		RobotPart.Slot.ARMS: "WEAPON\n腕部火器",
		RobotPart.Slot.CORE: "REACTOR\n動力コア",
	}

	for slot in SLOTS:
		var btn := Button.new()
		btn.text = slot_names[slot]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 44
		btn.pressed.connect(_select_slot.bind(slot))
		btn.mouse_entered.connect(func() -> void: Audio.play_ui(&"ui_hover", -8.0))
		slot_tabs.add_child(btn)
		_slot_buttons[slot] = btn

	# パーツリストのスクロールコンテナ
	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_top", 10)
	left_pane.add_child(scroll_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(scroll)

	_parts_container = GridContainer.new()
	_parts_container.columns = 1
	_parts_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_container.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_parts_container)

	# 中央/右ペイン: 3Dビュー（透明領域）＋ 性能比較スペックシート ＆ パーツ詳細
	var right_pane := VBoxContainer.new()
	right_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_pane.add_theme_constant_override("separation", 14)
	content_h.add_child(right_pane)

	# 3Dロボット鑑賞スペース（背景透過）
	var preview_spacer := Control.new()
	preview_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_pane.add_child(preview_spacer)

	# 選択中パーツの詳細カード ＆ 性能比較バー
	var detail_panel := PanelContainer.new()
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.04, 0.07, 0.12, 0.94)
	detail_style.border_width_left = 3
	detail_style.border_width_top = 1
	detail_style.border_width_right = 1
	detail_style.border_width_bottom = 1
	detail_style.border_color = Color(0.18, 0.35, 0.5, 0.7)
	detail_style.content_margin_left = 18
	detail_style.content_margin_right = 18
	detail_style.content_margin_top = 12
	detail_style.content_margin_bottom = 12
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	right_pane.add_child(detail_panel)

	var detail_v := VBoxContainer.new()
	detail_v.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail_v)

	var title_h := HBoxContainer.new()
	detail_v.add_child(title_h)

	_part_detail_title = Label.new()
	_part_detail_title.text = "SELECT PART // パーツを選択"
	_part_detail_title.add_theme_font_size_override("font_size", 18)
	_part_detail_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	title_h.add_child(_part_detail_title)

	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_h.add_child(title_spacer)

	_equip_button = Button.new()
	_equip_button.text = "EQUIP // 装備する"
	_equip_button.custom_minimum_size = Vector2(160, 36)
	_equip_button.pressed.connect(_on_equip_pressed)
	title_h.add_child(_equip_button)

	_part_detail_desc = Label.new()
	_part_detail_desc.text = "所持パーツ一覧から選択して機体性能の変化を確認できます。"
	_part_detail_desc.add_theme_font_size_override("font_size", 12)
	_part_detail_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_part_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_v.add_child(_part_detail_desc)

	# 性能比較スペックバー一覧
	var spec_grid := GridContainer.new()
	spec_grid.columns = 2
	spec_grid.add_theme_constant_override("h_separation", 24)
	spec_grid.add_theme_constant_override("v_separation", 6)
	detail_v.add_child(spec_grid)

	_build_spec_bar(spec_grid, "AP (耐久値)", "health", 400.0)
	_build_spec_bar(spec_grid, "EN (エネルギー)", "energy", 200.0)
	_build_spec_bar(spec_grid, "SPEED (機動力)", "speed", 14.0)
	_build_spec_bar(spec_grid, "FIREPOWER (火力)", "damage", 60.0)
	_build_spec_bar(spec_grid, "OPTICS (索敵範囲)", "vision", 18.0)
	_build_spec_bar(spec_grid, "ARMOR (装甲値)", "armor", 30.0)

	# 3. フッター（出撃 / 戻る）
	var footer := HBoxContainer.new()
	v_box.add_child(footer)

	var back_btn := Button.new()
	back_btn.text = "<< RETURN // メインメニュー"
	back_btn.custom_minimum_size = Vector2(180, 42)
	back_btn.pressed.connect(func() -> void:
		Audio.play_ui(&"ui_back")
		back_requested.emit())
	footer.add_child(back_btn)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)

	var deploy_btn := Button.new()
	deploy_btn.text = "SORTIE // この機体で出撃 >>"
	deploy_btn.custom_minimum_size = Vector2(240, 42)
	var deploy_style := StyleBoxFlat.new()
	deploy_style.bg_color = Color(0.12, 0.45, 0.28, 0.95)
	deploy_style.border_width_left = 3
	deploy_style.border_color = Color(0.3, 0.95, 0.6)
	deploy_btn.add_theme_stylebox_override("normal", deploy_style)
	deploy_btn.pressed.connect(func() -> void:
		Audio.play_ui(&"ui_confirm")
		deploy_requested.emit())
	footer.add_child(deploy_btn)


func _build_spec_bar(parent: Control, label_text: String, key: String, max_val: float) -> void:
	var h := HBoxContainer.new()
	h.custom_minimum_size.x = 280
	parent.add_child(h)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 110
	lbl.add_theme_font_size_override("font_size", 12)
	h.add_child(lbl)

	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size.y = 12
	bar.max_value = max_val
	bar.show_percentage = false
	h.add_child(bar)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size.x = 55
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0))
	h.add_child(val_lbl)

	_stat_bars[key] = {"bar": bar, "label": val_lbl, "max": max_val}


func _select_slot(slot: RobotPart.Slot) -> void:
	_current_slot = slot
	Audio.play_ui(&"ui_click")
	_update_slot_indicators()
	_populate_parts_list()


func _update_slot_indicators() -> void:
	for slot in SLOTS:
		var btn: Button = _slot_buttons[slot]
		var is_active := (slot == _current_slot)
		var equipped: RobotPart = _current_loadout.get_part(slot)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.18, 0.3, 0.95) if is_active else Color(0.04, 0.07, 0.12, 0.8)
		style.border_width_bottom = 3 if is_active else 1
		style.border_color = Color(0.25, 0.85, 1.0) if is_active else Color(0.18, 0.3, 0.45, 0.5)
		btn.add_theme_stylebox_override("normal", style)


func _populate_parts_list() -> void:
	for c in _parts_container.get_children():
		_parts_container.remove_child(c)
		c.queue_free()

	var all_slot_parts := Content.parts_for_slot(_current_slot)
	var equipped: RobotPart = _current_loadout.get_part(_current_slot)

	for p in all_slot_parts:
		var is_unlocked: bool = Save.is_unlocked(p.id) or p.starter
		var is_equipped: bool = (equipped != null and equipped.id == p.id)

		var card := Button.new()
		card.custom_minimum_size = Vector2(410, 46)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.05, 0.09, 0.15, 0.92) if is_unlocked else Color(0.03, 0.05, 0.08, 0.6)
		card_style.border_width_left = 4
		card_style.border_color = p.get_rarity_color() if is_unlocked else Color(0.25, 0.3, 0.35, 0.5)
		card_style.content_margin_left = 16
		card_style.content_margin_right = 16
		card_style.content_margin_top = 12
		card_style.content_margin_bottom = 12
		card.add_theme_stylebox_override("normal", card_style)

		var hover_style := card_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.1, 0.18, 0.28, 0.98)
		hover_style.border_color = Color(0.25, 0.85, 1.0)
		card.add_theme_stylebox_override("hover", hover_style)

		var title_text := p.get_title() if is_unlocked else "??? [LOCKED // 未入手]"
		if is_equipped:
			title_text += "  [EQUIPPED // 装備中]"
		elif not is_unlocked:
			title_text += "  [BATTLE DROP]"
		card.text = title_text
		card.add_theme_font_size_override("font_size", 13)
		card.add_theme_color_override("font_color", UiTheme.TEXT if is_unlocked else UiTheme.TEXT_DIM)

		if is_unlocked:
			card.pressed.connect(_on_part_clicked.bind(p))
			card.mouse_entered.connect(_on_part_hovered.bind(p))
		else:
			card.disabled = true

		_parts_container.add_child(card)

	# デフォルトで装備中パーツを選択表示
	if equipped != null:
		_show_part_details(equipped)


func _on_part_clicked(part: RobotPart) -> void:
	_show_part_details(part)
	_current_loadout.equip(part)
	Save.set_last_loadout(_current_loadout)
	Audio.play_ui(&"equip")
	_populate_parts_list()
	_update_spec_bars()
	if _robot_preview_callback.is_valid():
		_robot_preview_callback.call(_current_loadout)


func _on_part_hovered(part: RobotPart) -> void:
	Audio.play_ui(&"ui_hover", -8.0)
	_show_part_details(part)


func _show_part_details(part: RobotPart) -> void:
	_hovered_part = part
	_part_detail_title.text = "%s // %s" % [part.get_title(), RobotPart.slot_name(part.get_slot()).to_upper()]
	_part_detail_title.add_theme_color_override("font_color", part.get_rarity_color())
	_part_detail_desc.text = part.get_description()

	var equipped: RobotPart = _current_loadout.get_part(part.get_slot())
	var is_eq: bool = (equipped != null and equipped.id == part.id)
	_equip_button.disabled = is_eq
	_equip_button.text = "EQUIPPED // 装備中" if is_eq else "EQUIP // 装備する"


func _on_equip_pressed() -> void:
	if _hovered_part != null:
		_on_part_clicked(_hovered_part)


func _update_spec_bars() -> void:
	var stats := _current_loadout.build_stats()
	_set_bar_value("health", stats.max_health)
	_set_bar_value("energy", stats.max_energy)
	_set_bar_value("speed", stats.move_speed)
	_set_bar_value("damage", stats.weapon_damage)
	_set_bar_value("vision", stats.vision_range)
	_set_bar_value("armor", stats.armor)


func _set_bar_value(key: String, val: float) -> void:
	if not _stat_bars.has(key):
		return
	var entry: Dictionary = _stat_bars[key]
	var bar: ProgressBar = entry["bar"]
	var lbl: Label = entry["label"]
	bar.value = val
	lbl.text = "%d" % roundi(val) if val >= 10.0 else "%.1f" % val


func _on_color_changed(col: Color) -> void:
	Settings.set_value("player/color", col.to_html(false))
