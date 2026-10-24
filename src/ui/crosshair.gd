class_name DynamicCrosshair
extends Control
## AAAタクティカル照準レティクル（クロスヘア）。
## マウスカーソルまたはゲームパッドの照準位置にダイジェティックに追従する。
## 発砲時のリコイル拡散、敵へのターゲットロック、ヒットマーカー（Xマーク）、
## キルマーカー、照準周囲のエネルギー残量リングを完全統合。

const BASE_RADIUS := 16.0
const MAX_RECOIL_RADIUS := 36.0
const HITMARKER_DURATION := 0.14
const KILLMARKER_DURATION := 0.35

var session: GameSession
var camera: Camera3D

var _aim_pos: Vector2 = Vector2.ZERO
var _current_radius: float = BASE_RADIUS
var _target_radius: float = BASE_RADIUS
var _recoil_impulse: float = 0.0

var _is_target_locked: bool = false
var _target_distance: float = 0.0
var _hitmarker_timer: float = 0.0
var _killmarker_timer: float = 0.0
var _last_hit_was_kill: bool = false

var _energy_fraction: float = 1.0
var _cooldown_fraction: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func bind(game_session: GameSession, cam: Camera3D) -> void:
	session = game_session
	camera = cam


func trigger_recoil(amount: float = 1.0) -> void:
	_recoil_impulse = clampf(_recoil_impulse + amount * 12.0, 0.0, MAX_RECOIL_RADIUS - BASE_RADIUS)


func trigger_hit(is_kill: bool = false) -> void:
	if is_kill:
		_killmarker_timer = KILLMARKER_DURATION
		_last_hit_was_kill = true
	else:
		_hitmarker_timer = HITMARKER_DURATION
	queue_redraw()


func update_crosshair(delta: float, aim_screen_pos: Vector2, is_locked: bool, dist: float, energy_ratio: float, cd_ratio: float) -> void:
	_aim_pos = aim_screen_pos
	_is_target_locked = is_locked
	_target_distance = dist
	_energy_fraction = energy_ratio
	_cooldown_fraction = cd_ratio

	# リコイルの減衰
	_recoil_impulse = maxf(0.0, _recoil_impulse - delta * 42.0)
	_current_radius = BASE_RADIUS + _recoil_impulse

	if _hitmarker_timer > 0.0:
		_hitmarker_timer = maxf(0.0, _hitmarker_timer - delta)
	if _killmarker_timer > 0.0:
		_killmarker_timer = maxf(0.0, _killmarker_timer - delta)

	queue_redraw()


func _draw() -> void:
	if _aim_pos == Vector2.ZERO:
		return

	var center := _aim_pos
	var primary_color := Color(1.0, 0.35, 0.35, 0.95) if _is_target_locked else Color(0.2, 0.85, 1.0, 0.85)
	var secondary_color := Color(primary_color.r, primary_color.g, primary_color.b, 0.4)
	var r := _current_radius

	# 1. 中央ドット
	draw_circle(center, 1.5, primary_color)

	# 2. 4方向のシェブロン / スリット
	var gap := r * 0.55
	var length := r * 0.75
	var thickness := 1.5

	# 上
	draw_line(center - Vector2(0, gap), center - Vector2(0, gap + length), primary_color, thickness)
	# 下
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + length), primary_color, thickness)
	# 左
	draw_line(center - Vector2(gap, 0), center - Vector2(gap + length, 0), primary_color, thickness)
	# 右
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + length, 0), primary_color, thickness)

	# 3. 照準円弧（4分割リング）
	var arc_rad := r * 0.9
	var segments := 16
	for i in 4:
		var start_angle := i * (PI * 0.5) + PI * 0.12
		var end_angle := (i + 1) * (PI * 0.5) - PI * 0.12
		draw_arc(center, arc_rad, start_angle, end_angle, 6, secondary_color, 1.2, true)

	# 4. エネルギー残量リング（右側円弧ゲージ）
	if _energy_fraction < 0.99:
		var en_rad := r + 6.0
		var en_start := -PI * 0.4
		var en_span := PI * 0.8
		# 背景枠
		draw_arc(center, en_rad, en_start, en_start + en_span, 12, Color(0.05, 0.1, 0.15, 0.5), 2.5, true)
		# 有効値
		var en_color := Color(0.25, 0.95, 0.7) if _energy_fraction > 0.3 else Color(1.0, 0.35, 0.25)
		draw_arc(center, en_rad, en_start, en_start + en_span * clampf(_energy_fraction, 0.0, 1.0), 12, en_color, 2.5, true)

	# 5. ターゲットロック演出
	if _is_target_locked:
		var lock_size := r * 1.5
		var bracket_len := 6.0
		var lock_col := Color(1.0, 0.25, 0.25, 0.9)
		# 左上
		draw_line(center + Vector2(-lock_size, -lock_size), center + Vector2(-lock_size + bracket_len, -lock_size), lock_col, 2.0)
		draw_line(center + Vector2(-lock_size, -lock_size), center + Vector2(-lock_size, -lock_size + bracket_len), lock_col, 2.0)
		# 右上
		draw_line(center + Vector2(lock_size, -lock_size), center + Vector2(lock_size - bracket_len, -lock_size), lock_col, 2.0)
		draw_line(center + Vector2(lock_size, -lock_size), center + Vector2(lock_size, -lock_size + bracket_len), lock_col, 2.0)
		# 左下
		draw_line(center + Vector2(-lock_size, lock_size), center + Vector2(-lock_size + bracket_len, lock_size), lock_col, 2.0)
		draw_line(center + Vector2(-lock_size, lock_size), center + Vector2(-lock_size, lock_size - bracket_len), lock_col, 2.0)
		# 右下
		draw_line(center + Vector2(lock_size, lock_size), center + Vector2(lock_size - bracket_len, lock_size), lock_col, 2.0)
		draw_line(center + Vector2(lock_size, lock_size), center + Vector2(lock_size, lock_size - bracket_len), lock_col, 2.0)

		# 距離表示
		var font := get_theme_default_font()
		var dist_text := "%04.1fm" % _target_distance
		draw_string(font, center + Vector2(-20, lock_size + 14), dist_text, HORIZONTAL_ALIGNMENT_CENTER, 40, 10, lock_col)

	# 6. ヒットマーカー（命中時の白「X」）
	if _hitmarker_timer > 0.0:
		var alpha := _hitmarker_timer / HITMARKER_DURATION
		var hit_col := Color(1.0, 1.0, 1.0, alpha)
		var h_len := 9.0
		var h_gap := 4.0
		draw_line(center + Vector2(h_gap, h_gap), center + Vector2(h_gap + h_len, h_gap + h_len), hit_col, 2.0)
		draw_line(center + Vector2(-h_gap, h_gap), center + Vector2(-h_gap - h_len, h_gap + h_len), hit_col, 2.0)
		draw_line(center + Vector2(h_gap, -h_gap), center + Vector2(h_gap + h_len, -h_gap - h_len), hit_col, 2.0)
		draw_line(center + Vector2(-h_gap, -h_gap), center + Vector2(-h_gap - h_len, -h_gap - h_len), hit_col, 2.0)

	# 7. キルマーカー（撃破時の赤「X」＋キル表示）
	if _killmarker_timer > 0.0:
		var alpha := _killmarker_timer / KILLMARKER_DURATION
		var kill_col := Color(1.0, 0.15, 0.2, alpha)
		var k_len := 14.0
		var k_gap := 5.0
		draw_line(center + Vector2(k_gap, k_gap), center + Vector2(k_gap + k_len, k_gap + k_len), kill_col, 3.0)
		draw_line(center + Vector2(-k_gap, k_gap), center + Vector2(-k_gap - k_len, k_gap + k_len), kill_col, 3.0)
		draw_line(center + Vector2(k_gap, -k_gap), center + Vector2(k_gap + k_len, -k_gap - k_len), kill_col, 3.0)
		draw_line(center + Vector2(-k_gap, -k_gap), center + Vector2(-k_gap - k_len, -k_gap - k_len), kill_col, 3.0)
		var font := get_theme_default_font()
		draw_string(font, center + Vector2(-40, -r - 12), "TARGET NEUTRALIZED", HORIZONTAL_ALIGNMENT_CENTER, 80, 10, kill_col)
