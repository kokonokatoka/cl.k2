class_name Hud
extends CanvasLayer
## ゲーム中の HUD。パーツ換装パネル、体力・エネルギー、スコア、レーダー、通知、キルフィード、死亡表示。
## 状態は持たず、毎フレーム session から読んで表示するだけ。

const SLOTS: Array[RobotPart.Slot] = [RobotPart.Slot.EYES, RobotPart.Slot.LEGS, RobotPart.Slot.ARMS, RobotPart.Slot.CORE]
const TOAST_SECONDS := 3.5
const FEED_SECONDS := 6.0
const MAX_TOASTS := 4
const MAX_FEED := 5

var session: GameSession

var _root: Control
var _name_labels: Dictionary = {}
var _slot_titles: Dictionary = {}
var _chips: Dictionary = {}
var _stats_label: Label
var _title_label: Label
var _controls_label: Label
var _health_bar: StatBar
var _energy_bar: StatBar
var _weapon_label: Label
var _score_label: Label
var _ping_label: Label
var _radar: Radar
var _toasts: VBoxContainer
var _feed: VBoxContainer
var _death_label: Label
var _danger_frame: Panel
var _last_low_health_warn: float = 0.0
var _ping_visible: bool = false


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_danger_frame()
	_build_parts_panel()
	_build_status_bars()
	_build_top_right()
	_build_radar()
	_build_notifications()
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
	_score_label.text = "%s %d    %s %d    %s %d" % [
		tr("hud.score"), p.score, tr("hud.kills"), p.kills, tr("hud.deaths"), p.deaths]
	if _ping_visible:
		_ping_label.text = tr("hud.ping") % session.ping_ms()
	_radar.update_frame(frame, stats.vision_range)

	_death_label.visible = not p.alive
	if not p.alive:
		_death_label.text = "%s\n%s" % [tr("hud.eliminated"), tr("hud.respawn_in") % maxf(p.respawn_timer, 0.0)]

	# 体力が少ないと画面の縁が赤く脈打つ
	var health_ratio := p.health / maxf(stats.max_health, 1.0)
	var pulse := 0.0
	if p.alive and health_ratio < 0.3:
		pulse = (0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)) * (1.0 - health_ratio / 0.3)
		_last_low_health_warn -= delta
		if _last_low_health_warn <= 0.0:
			_last_low_health_warn = 1.1
			Audio.play_ui(&"low_health", -6.0)
	_danger_frame.modulate.a = lerpf(_danger_frame.modulate.a, pulse, minf(1.0, delta * 10.0))


## シミュレーションのイベントから、通知とキルフィードを出す
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
				toast(tr("toast.health"), Events.ToastKind.GOOD)
			elif event.tag == &"energy":
				toast(tr("toast.energy"), Events.ToastKind.GOOD)
		SimEvent.Type.KILL:
			_add_feed_line(event)


func toast(text: String, kind: int = Events.ToastKind.INFO, color_override: Color = Color(0, 0, 0, 0)) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_constant_override("outline_size", 6)
	var color := color_override
	if color.a == 0.0:
		match kind:
			Events.ToastKind.GOOD: color = UiTheme.GOOD
			Events.ToastKind.WARN: color = UiTheme.ACCENT
			Events.ToastKind.BAD: color = UiTheme.BAD
			_: color = UiTheme.TEXT
	label.add_theme_color_override("font_color", color)
	_toasts.add_child(label)
	while _toasts.get_child_count() > MAX_TOASTS:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tween := create_tween()
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


func _add_feed_line(event: SimEvent) -> void:
	var victim := ""
	if event.tag == &"player":
		victim = session.player_name(event.b)
	else:
		var def := Content.enemy(event.tag)
		victim = def.get_title() if def != null else "?"
	var text := ""
	if event.a != 0:
		text = tr("feed.kill") % [session.player_name(event.a), victim]
	elif event.tag == &"player":
		text = tr("feed.destroyed") % victim
	else:
		return
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var involves_local := event.a == session.local_id or (event.tag == &"player" and event.b == session.local_id)
	label.add_theme_color_override("font_color", UiTheme.ACCENT if involves_local else UiTheme.TEXT_DIM)
	label.add_theme_constant_override("outline_size", 5)
	_feed.add_child(label)
	while _feed.get_child_count() > MAX_FEED:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tween := create_tween()
	tween.tween_interval(FEED_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)


# --- 組み立て ---

func _build_parts_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(_title_label)

	for slot in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(5, 24)
		row.add_child(chip)
		_chips[slot] = chip
		var title := Label.new()
		title.custom_minimum_size.x = 52
		row.add_child(title)
		_slot_titles[slot] = title
		row.add_child(_arrow_button("<", slot, -1))
		var name_label := Label.new()
		name_label.custom_minimum_size.x = 170
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		row.add_child(name_label)
		_name_labels[slot] = name_label
		row.add_child(_arrow_button(">", slot, 1))
		box.add_child(row)

	box.add_child(HSeparator.new())
	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_stats_label)


func _arrow_button(text: String, slot: RobotPart.Slot, step: int) -> Button:
	var button := Button.new()
	button.text = text
	# フォーカスを持たせない（Space キーでボタンが押されてしまうのを防ぐ）
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(30, 0)
	button.pressed.connect(func() -> void:
		if session != null:
			session.cycle_slot(slot, step)
			Audio.play_ui(&"equip"))
	return button


func _build_status_bars() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.position.y -= 24
	_root.add_child(anchor)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.position = Vector2(-150, -86)
	anchor.add_child(box)
	_health_bar = StatBar.new()
	_health_bar.fill_color = UiTheme.HEALTH
	_health_bar.custom_minimum_size = Vector2(300, 24)
	box.add_child(_health_bar)
	_energy_bar = StatBar.new()
	_energy_bar.fill_color = UiTheme.ENERGY
	_energy_bar.custom_minimum_size = Vector2(300, 20)
	box.add_child(_energy_bar)
	_weapon_label = Label.new()
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.add_theme_font_size_override("font_size", 13)
	_weapon_label.add_theme_color_override("font_color", UiTheme.TEXT)
	box.add_child(_weapon_label)


func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-340, 16)
	box.custom_minimum_size = Vector2(324, 0)
	_root.add_child(box)
	var panel := PanelContainer.new()
	box.add_child(panel)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_score_label)
	_ping_label = Label.new()
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping_label.add_theme_font_size_override("font_size", 12)
	_ping_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_ping_label.visible = false
	box.add_child(_ping_label)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 2)
	box.add_child(_feed)


func _build_radar() -> void:
	_radar = Radar.new()
	_radar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_radar.position = Vector2(-Radar.SIZE - 16, -Radar.SIZE - 16)
	_root.add_child(_radar)
	_controls_label = Label.new()
	_controls_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_controls_label.position = Vector2(16, -32)
	_controls_label.add_theme_font_size_override("font_size", 12)
	_controls_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_root.add_child(_controls_label)


func _build_notifications() -> void:
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.position = Vector2(-220, 70)
	_toasts.custom_minimum_size = Vector2(440, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


func _build_death_label() -> void:
	_death_label = Label.new()
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 34)
	_death_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	_death_label.add_theme_constant_override("outline_size", 10)
	_death_label.visible = false
	_root.add_child(_death_label)


func _build_danger_frame() -> void:
	_danger_frame = Panel.new()
	_danger_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(1, 0.1, 0.1, 0.8)
	style.set_border_width_all(10)
	_danger_frame.add_theme_stylebox_override("panel", style)
	_danger_frame.modulate.a = 0.0
	_root.add_child(_danger_frame)


# --- 更新 ---

func _update_parts_panel(p: SimPlayer) -> void:
	for slot in SLOTS:
		var part := p.loadout.get_part(slot)
		var label: Label = _name_labels[slot]
		label.text = part.get_title() if part != null else tr("hud.none")
		label.add_theme_color_override("font_color", part.get_rarity_color() if part != null else UiTheme.TEXT_DIM)
		(_chips[slot] as ColorRect).color = part.accent if part != null else Color(0.25, 0.27, 0.32)
	var s := p.stats
	var jump := "%.1f" % s.jump_velocity if s.jump_velocity > 0.0 else tr("hud.cannot_jump")
	var vision := "%.0f m" % s.vision_range if s.vision_range > 0.0 else tr("hud.blind")
	var damage := "%.0f" % s.weapon_damage if s.can_fire() else tr("hud.unarmed")
	if s.can_fire() and s.pellets > 1:
		damage += " x%d" % s.pellets
	_stats_label.text = "%s %.1f   %s %s\n%s %s   %s %s" % [
		tr("hud.stat.speed"), s.move_speed, tr("hud.stat.jump"), jump,
		tr("hud.stat.vision"), vision, tr("hud.stat.damage"), damage]


func _update_weapon_label(p: SimPlayer) -> void:
	var part := p.loadout.get_part(RobotPart.Slot.ARMS)
	if part == null:
		_weapon_label.text = tr("hud.unarmed")
		return
	var dash_state := tr("hud.dash_ready") if p.stats.can_dash() and p.dash_cd <= 0.0 and p.energy >= p.stats.dash_cost else tr("hud.dash_wait")
	_weapon_label.text = "%s    %s %s" % [part.get_title(), tr("hud.stat.dash"), dash_state]


func _retranslate() -> void:
	_title_label.text = tr("hud.parts")
	for slot in SLOTS:
		(_slot_titles[slot] as Label).text = tr("slot.%s" % RobotPart.slot_key(slot))
	_health_bar.label_text = tr("hud.health")
	_energy_bar.label_text = tr("hud.energy")
	_controls_label.text = tr("hud.controls")
