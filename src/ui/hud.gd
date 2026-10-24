class_name Hud
extends CanvasLayer
## AAAサイバーミリタリーHUD。
## アーマード・コアやサイバーパンク調のホログラフィック・タクティカルバイザー仕様。
## 四隅のコーナーブラケット、斜角パーツ換装パネル、セグメントスラントゲージ、
## 円形ソナーレーダー、戦績デジタルディスプレイを完全統合。

const SLOTS: Array[RobotPart.Slot] = [RobotPart.Slot.EYES, RobotPart.Slot.LEGS, RobotPart.Slot.ARMS, RobotPart.Slot.CORE]
const SLOT_KEYS: Array[String] = ["[1]", "[2]", "[3]", "[4]"]
const TOAST_SECONDS := 3.5
const FEED_SECONDS := 6.0
const MAX_TOASTS := 4
const MAX_FEED := 5

var session: GameSession

var _root: Control
var _visor_overlay: Control
var _name_labels: Dictionary = {}
var _slot_titles: Dictionary = {}
var _chips: Dictionary = {}
var _stats_label: Label
var _title_label: Label
var _health_bar: StatBar
var _energy_bar: StatBar
var _weapon_label: Label
var _boost_label: Label
var _score_label: Label
var _ping_label: Label
var _radar: Radar
var _toasts: VBoxContainer
var _feed: VBoxContainer
var _death_label: Label
var _danger_frame: Panel
var _last_low_health_warn: float = 0.0
var _ping_visible: bool = false

var _wave_label: Label
var _wave_banner: Label
var _wave_sub: Label
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _last_wave: int = 1


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 1. 画面四隅のバイザーフレーム
	_visor_overlay = Control.new()
	_visor_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_visor_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor_overlay.draw.connect(_draw_visor_brackets)
	_root.add_child(_visor_overlay)

	# 2. 各種HUD要素
	_build_danger_frame()
	_build_parts_panel()
	_build_status_bars()
	_build_top_right()
	_build_radar()
	_build_notifications()
	_build_wave_ui()
	_build_death_label()
	_retranslate()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _root != null:
		_retranslate()


func bind(game_session: GameSession) -> void:
	session = game_session
	_ping_visible = session.is_online()
	_ping_label.visible = _ping_visible
	_radar.set_geometry(session.geometry)


func update_frame(frame: RenderFrame, delta: float) -> void:
	if session == null or session.local_player == null:
		return
	var p := session.local_player
	var stats := p.stats

	_health_bar.set_values(p.health, stats.max_health)
	_energy_bar.set_values(p.energy, stats.max_energy)
	_update_parts_panel(p)
	_update_weapon_label(p)
	
	_score_label.text = "SCORE: %05d   KILLS: %02d   LOSS: %02d" % [p.score, p.kills, p.deaths]
	if _ping_visible:
		_ping_label.text = "PING: %d ms" % session.ping_ms()
	
	_radar.update_frame(frame, stats.vision_range)

	# ウェーブ情報更新
	if frame.wave_number != _last_wave:
		_on_wave_advanced(frame.wave_number)
		_last_wave = frame.wave_number
	_wave_label.text = "WAVE %02d // TARGETS: %02d / %02d" % [frame.wave_number, frame.wave_kills, frame.wave_target]

	# ボスHPバー更新
	if frame.boss_id > 0:
		_boss_panel.visible = true
		_boss_bar.value = frame.boss_health_fraction * 100.0
	else:
		_boss_panel.visible = false

	_death_label.visible = not p.alive
	if not p.alive:
		_death_label.text = "%s\n%s" % [tr("hud.eliminated"), tr("hud.respawn_in") % maxf(p.respawn_timer, 0.0)]

	# 低HP警告パルス
	var health_ratio := p.health / maxf(stats.max_health, 1.0)
	var pulse := 0.0
	if p.alive and health_ratio < 0.28:
		pulse = (0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)) * (1.0 - health_ratio / 0.28)
		_last_low_health_warn -= delta
		if _last_low_health_warn <= 0.0:
			_last_low_health_warn = 1.0
			Audio.play_ui(&"low_health", -5.0)
	_danger_frame.modulate.a = lerpf(_danger_frame.modulate.a, pulse, minf(1.0, delta * 12.0))


func handle_event(event: SimEvent) -> void:
	if session == null:
		return
	match event.type:
		SimEvent.Type.PICKUP:
			if event.a != session.local_id:
				return
			var part := Content.part(event.tag)
			if part != null:
				var text := (tr("toast.new_part") if event.value > 0.5 else tr("toast.duplicate_part")) % part.get_title()
				toast(text, Events.ToastKind.GOOD, part.get_rarity_color())
			elif event.tag == &"health":
				toast("REPAIR +AP // 装甲修復", Events.ToastKind.GOOD)
			elif event.tag == &"energy":
				toast("ENERGY CELL +EN // 出力補給", Events.ToastKind.GOOD)
		SimEvent.Type.KILL:
			_add_feed_line(event)


func toast(text: String, kind: int = Events.ToastKind.INFO, color_override: Color = Color(0, 0, 0, 0)) -> void:
	var container := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.92)
	style.border_width_left = 3
	style.border_color = Color(0.2, 0.8, 1.0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	container.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	
	var color := color_override
	if color.a == 0.0:
		match kind:
			Events.ToastKind.GOOD: color = Color(0.3, 0.95, 0.6)
			Events.ToastKind.WARN: color = Color(1.0, 0.7, 0.2)
			Events.ToastKind.BAD: color = Color(1.0, 0.35, 0.35)
			_: color = Color(0.9, 0.95, 1.0)
	label.add_theme_color_override("font_color", color)
	container.add_child(label)

	_toasts.add_child(container)
	while _toasts.get_child_count() > MAX_TOASTS:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	
	var tween := create_tween()
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(container, "modulate:a", 0.0, 0.5)
	tween.tween_callback(container.queue_free)


func _add_feed_line(event: SimEvent) -> void:
	var victim := ""
	if event.tag == &"player":
		victim = session.player_name(event.b)
	else:
		var def := Content.enemy(event.tag)
		victim = def.get_title() if def != null else "?"
	
	var text := ""
	if event.a != 0:
		text = "%s  ▶▶  %s" % [session.player_name(event.a), victim]
	elif event.tag == &"player":
		text = "TERMINATED // %s" % victim
	else:
		return
	
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var involves_local := event.a == session.local_id or (event.tag == &"player" and event.b == session.local_id)
	label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2) if involves_local else Color(0.65, 0.75, 0.85, 0.8))
	label.add_theme_font_size_override("font_size", 13)
	_feed.add_child(label)
	
	while _feed.get_child_count() > MAX_FEED:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	
	var tween := create_tween()
	tween.tween_interval(FEED_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


# --- 画面四隅のホログラフィック・バイザーフレーム ---

func _draw_visor_brackets() -> void:
	var w := _visor_overlay.size.x
	var h := _visor_overlay.size.y
	var margin := 16.0
	var len := 36.0
	var c := Color(0.18, 0.45, 0.65, 0.5)
	var c_bright := Color(0.3, 0.85, 1.0, 0.8)

	# 左上ブラケット
	_visor_overlay.draw_line(Vector2(margin, margin + len), Vector2(margin, margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(margin, margin), Vector2(margin + len, margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(margin, margin), Vector2(margin + 6, margin + 6), c_bright, 2.0)

	# 右上ブラケット
	_visor_overlay.draw_line(Vector2(w - margin - len, margin), Vector2(w - margin, margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, margin), Vector2(w - margin, margin + len), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, margin), Vector2(w - margin - 6, margin + 6), c_bright, 2.0)

	# 左下ブラケット
	_visor_overlay.draw_line(Vector2(margin, h - margin - len), Vector2(margin, h - margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(margin, h - margin), Vector2(margin + len, h - margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(margin, h - margin), Vector2(margin + 6, h - margin - 6), c_bright, 2.0)

	# 右下ブラケット
	_visor_overlay.draw_line(Vector2(w - margin - len, h - margin), Vector2(w - margin, h - margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, h - margin - len), Vector2(w - margin, h - margin), c, 1.5)
	_visor_overlay.draw_line(Vector2(w - margin, h - margin), Vector2(w - margin - 6, h - margin - 6), c_bright, 2.0)

	# 左下の操作ガイド（洗練されたミリタリーフッター）
	var font := _visor_overlay.get_theme_default_font()
	var footer := "WASD MANEUVER  |  MOUSE AIM  |  LMB FIRE  |  SHIFT BOOST  |  SPACE JUMP  |  [1-4] RE-ARM  |  TAB INTEL"
	_visor_overlay.draw_string(font, Vector2(margin + 18, h - margin - 6), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.6, 0.75, 0.65))


# --- UIコンポーネント組み立て ---

func _build_parts_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	_root.add_child(panel)

	# ハイテクサイバーパネル
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.035, 0.06, 0.88)
	style.border_width_left = 2
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.18, 0.45, 0.65, 0.7)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var header_hbox := HBoxContainer.new()
	box.add_child(header_hbox)

	var led := ColorRect.new()
	led.color = Color(0.2, 0.9, 1.0)
	led.custom_minimum_size = Vector2(4, 14)
	header_hbox.add_child(led)

	_title_label = Label.new()
	_title_label.text = "CHASSIS SPEC // 機体装備"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	header_hbox.add_child(_title_label)

	for i in range(SLOTS.size()):
		var slot := SLOTS[i]
		var key_str := SLOT_KEYS[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# キーバッジ [1] - [4]
		var key_label := Label.new()
		key_label.text = key_str
		key_label.custom_minimum_size.x = 22
		key_label.add_theme_font_size_override("font_size", 11)
		key_label.add_theme_color_override("font_color", Color(0.95, 0.65, 0.15))
		row.add_child(key_label)

		# レアリティLED
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(3, 22)
		row.add_child(chip)
		_chips[slot] = chip

		var title := Label.new()
		title.custom_minimum_size.x = 64
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		row.add_child(title)
		_slot_titles[slot] = title

		row.add_child(_arrow_button("◀", slot, -1))

		var name_label := Label.new()
		name_label.custom_minimum_size.x = 160
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.add_theme_font_size_override("font_size", 13)
		row.add_child(name_label)
		_name_labels[slot] = name_label

		row.add_child(_arrow_button("▶", slot, 1))
		box.add_child(row)

	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.18, 0.35, 0.5, 0.5)
	sep.add_theme_stylebox_override("separator", sep_style)
	box.add_child(sep)

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", Color(0.65, 0.8, 0.9, 0.9))
	box.add_child(_stats_label)


func _arrow_button(text: String, slot: RobotPart.Slot, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(24, 22)
	
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.08, 0.12, 0.18, 0.9)
	btn_style.border_width_left = 1
	btn_style.border_width_top = 1
	btn_style.border_width_right = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.2, 0.4, 0.6, 0.6)
	btn_style.set_corner_radius_all(2)
	button.add_theme_stylebox_override("normal", btn_style)
	
	var hover_style := btn_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = Color(0.15, 0.25, 0.4, 0.95)
	hover_style.border_color = Color(0.3, 0.85, 1.0, 0.9)
	button.add_theme_stylebox_override("hover", hover_style)

	button.pressed.connect(func() -> void:
		if session != null:
			session.cycle_slot(slot, step)
			Audio.play_ui(&"equip"))
	return button


func _build_status_bars() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.position.y -= 20
	_root.add_child(anchor)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.position = Vector2(-170, -96)
	anchor.add_child(box)

	# AP 装甲耐久ゲージ（レッド/クリムゾン）
	_health_bar = StatBar.new()
	_health_bar.fill_color = Color(1.0, 0.25, 0.35)
	_health_bar.label_text = "AP // ARMOR"
	_health_bar.is_health = true
	_health_bar.custom_minimum_size = Vector2(340, 24)
	box.add_child(_health_bar)

	# EN エネルギー出力ゲージ（シアン/エレクトリックブルー）
	_energy_bar = StatBar.new()
	_energy_bar.fill_color = Color(0.15, 0.85, 1.0)
	_energy_bar.label_text = "EN // REACTOR"
	_energy_bar.is_health = false
	_energy_bar.custom_minimum_size = Vector2(340, 20)
	box.add_child(_energy_bar)

	var sub_hbox := HBoxContainer.new()
	sub_hbox.custom_minimum_size.x = 340
	box.add_child(sub_hbox)

	_weapon_label = Label.new()
	_weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_weapon_label.add_theme_font_size_override("font_size", 11)
	_weapon_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	sub_hbox.add_child(_weapon_label)

	_boost_label = Label.new()
	_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boost_label.add_theme_font_size_override("font_size", 11)
	_boost_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.5))
	sub_hbox.add_child(_boost_label)


func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-360, 24)
	box.custom_minimum_size = Vector2(336, 0)
	_root.add_child(box)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.035, 0.06, 0.88)
	style.border_width_right = 2
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.18, 0.45, 0.65, 0.7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	box.add_child(panel)

	var inner_box := VBoxContainer.new()
	inner_box.add_theme_constant_override("separation", 2)
	panel.add_child(inner_box)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 14)
	_score_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	inner_box.add_child(_score_label)

	_ping_label = Label.new()
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping_label.add_theme_font_size_override("font_size", 10)
	_ping_label.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8, 0.7))
	inner_box.add_child(_ping_label)

	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 3)
	box.add_child(_feed)


func _build_radar() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	anchor.position = Vector2(-204, -204)
	_root.add_child(anchor)
	_radar = Radar.new()
	anchor.add_child(_radar)


func _build_notifications() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	anchor.position.y += 45
	_root.add_child(anchor)

	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(-220, 0)
	_toasts.custom_minimum_size = Vector2(440, 0)
	_toasts.add_theme_constant_override("separation", 6)
	anchor.add_child(_toasts)


func _build_wave_ui() -> void:
	# 1. 上部中央のウェーブ情報タグ
	var wave_tag_panel := PanelContainer.new()
	wave_tag_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_tag_panel.position = Vector2(-150, 16)
	wave_tag_panel.custom_minimum_size = Vector2(300, 28)
	var tag_style := StyleBoxFlat.new()
	tag_style.bg_color = Color(0.02, 0.04, 0.08, 0.88)
	tag_style.border_width_bottom = 2
	tag_style.border_color = Color(0.2, 0.85, 1.0)
	tag_style.content_margin_left = 12
	tag_style.content_margin_right = 12
	tag_style.content_margin_top = 4
	tag_style.content_margin_bottom = 4
	wave_tag_panel.add_theme_stylebox_override("panel", tag_style)
	_root.add_child(wave_tag_panel)

	_wave_label = Label.new()
	_wave_label.text = "WAVE 01 // TARGETS: 00 / 06"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 12)
	_wave_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	wave_tag_panel.add_child(_wave_label)

	# 2. ボスHPバー（画面最上部）
	_boss_panel = PanelContainer.new()
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-260, 48)
	_boss_panel.custom_minimum_size = Vector2(520, 36)
	var boss_style := StyleBoxFlat.new()
	boss_style.bg_color = Color(0.06, 0.02, 0.03, 0.92)
	boss_style.border_width_left = 3
	boss_style.border_width_right = 3
	boss_style.border_width_bottom = 1
	boss_style.border_color = Color(1.0, 0.25, 0.25)
	boss_style.content_margin_left = 14
	boss_style.content_margin_right = 14
	boss_style.content_margin_top = 6
	boss_style.content_margin_bottom = 6
	_boss_panel.add_theme_stylebox_override("panel", boss_style)
	_boss_panel.visible = false
	_root.add_child(_boss_panel)

	var boss_v := VBoxContainer.new()
	boss_v.add_theme_constant_override("separation", 4)
	_boss_panel.add_child(boss_v)

	var boss_lbl := Label.new()
	boss_lbl.text = "HOSTILE TITAN // GIGAS BRUTE [THREAT: CRITICAL]"
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_lbl.add_theme_font_size_override("font_size", 11)
	boss_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	boss_v.add_child(boss_lbl)

	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size.y = 8
	_boss_bar.max_value = 100.0
	_boss_bar.value = 100.0
	_boss_bar.show_percentage = false
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.2, 0.25)
	_boss_bar.add_theme_stylebox_override("fill", bar_fill)
	boss_v.add_child(_boss_bar)

	# 3. 画面中央の大迫力ウェーブ通知バナー
	_wave_banner = Label.new()
	_wave_banner.set_anchors_preset(Control.PRESET_CENTER)
	_wave_banner.position = Vector2(-400, -110)
	_wave_banner.custom_minimum_size = Vector2(800, 50)
	_wave_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_banner.add_theme_font_size_override("font_size", 38)
	_wave_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_wave_banner.add_theme_constant_override("outline_size", 8)
	_wave_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_wave_banner.modulate.a = 0.0
	_root.add_child(_wave_banner)

	_wave_sub = Label.new()
	_wave_sub.set_anchors_preset(Control.PRESET_CENTER)
	_wave_sub.position = Vector2(-400, -60)
	_wave_sub.custom_minimum_size = Vector2(800, 30)
	_wave_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_sub.add_theme_font_size_override("font_size", 16)
	_wave_sub.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	_wave_sub.add_theme_constant_override("outline_size", 4)
	_wave_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_wave_sub.modulate.a = 0.0
	_root.add_child(_wave_sub)


func _on_wave_advanced(wave: int) -> void:
	Audio.play_ui(&"ui_confirm")
	_wave_banner.text = ">> WAVE %02d COMMENCING <<" % wave
	_wave_sub.text = "ELIMINATE HOSTILE COMBAT UNITS" if wave % 3 != 0 else "! WARNING: HOSTILE TITAN INCOMING !"
	_wave_banner.modulate.a = 1.0
	_wave_sub.modulate.a = 1.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_wave_banner, "modulate:a", 0.0, 2.5).set_ease(Tween.EASE_IN)
	tween.tween_property(_wave_sub, "modulate:a", 0.0, 2.8).set_ease(Tween.EASE_IN)


func _build_death_label() -> void:
	_death_label = Label.new()
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 34)
	_death_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.35))
	_death_label.add_theme_constant_override("outline_size", 8)
	_death_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_death_label.visible = false
	_root.add_child(_death_label)


func _build_danger_frame() -> void:
	_danger_frame = Panel.new()
	_danger_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.1, 0.2, 0.2)
	style.border_width_left = 18
	style.border_width_top = 18
	style.border_width_right = 18
	style.border_width_bottom = 18
	style.border_color = Color(1.0, 0.1, 0.2, 0.8)
	_danger_frame.add_theme_stylebox_override("panel", style)
	_danger_frame.modulate.a = 0.0
	_root.add_child(_danger_frame)


func _update_parts_panel(p: SimPlayer) -> void:
	for slot in SLOTS:
		var part := p.loadout.get_part(slot)
		var label: Label = _name_labels[slot]
		var chip: ColorRect = _chips[slot]
		if part != null:
			label.text = part.get_title()
			label.add_theme_color_override("font_color", part.get_rarity_color())
			chip.color = part.get_rarity_color()
		else:
			label.text = "-- EMPTY --"
			label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
			chip.color = Color(0.2, 0.25, 0.35)

	var s := p.stats
	var jmp := "NO" if s.jump_velocity <= 0.001 else ("%.1f" % s.jump_velocity)
	var vis := "BLIND" if s.vision_range <= 0.001 else ("%.1fm" % s.vision_range)
	var dmg := "NONE" if s.weapon_damage <= 0.001 else ("%d" % roundi(s.weapon_damage))
	_stats_label.text = "SPD: %4.1f  |  JMP: %s\nVIS: %5s  |  ATK: %s" % [s.move_speed, jmp, vis, dmg]


func _update_weapon_label(p: SimPlayer) -> void:
	var w_name := p.stats.weapon_kind.to_upper()
	if w_name == "": w_name = "UNARMED"
	_weapon_label.text = "[LMB] %s" % w_name

	if p.dash_cd <= 0.0:
		_boost_label.text = "[SHIFT] BOOST // READY"
		_boost_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.5))
	else:
		_boost_label.text = "[SHIFT] BOOST // %.1fs" % p.dash_cd
		_boost_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))


func _retranslate() -> void:
	_slot_titles[RobotPart.Slot.EYES].text = "OPTICS"
	_slot_titles[RobotPart.Slot.LEGS].text = "CHASSIS"
	_slot_titles[RobotPart.Slot.ARMS].text = "ARMAMENT"
	_slot_titles[RobotPart.Slot.CORE].text = "REACTOR"
