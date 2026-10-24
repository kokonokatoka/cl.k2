class_name Radar
extends Control
## AAAタクティカル・ホログラフィック・ソナーレーダー。
## 円形コンパスリング、同心円グリッド、回転走査スキャナー、
## ハイテク遮蔽物ワイヤーフレーム＆ターゲットインジケーターを搭載。

const SIZE := 180.0
const RANGE := 22.0

var _geometry: WorldGeometry
var _frame: RenderFrame
var _visible_range: float = 7.0
var _sweep_angle: float = 0.0

func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_geometry(geometry: WorldGeometry) -> void:
	_geometry = geometry


func update_frame(frame: RenderFrame, vision_range: float) -> void:
	_frame = frame
	_visible_range = vision_range


func _process(delta: float) -> void:
	_sweep_angle = fmod(_sweep_angle + delta * 2.2, TAU)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := SIZE * 0.46
	var scale := radius / RANGE

	# 1. 円形ベースプレート（半透明サイバーダーク）
	draw_circle(center, radius, Color(0.015, 0.03, 0.05, 0.88))

	# 2. 同心円グリッド（5m, 10m, 15m, 20m）
	var grid_color := Color(0.12, 0.28, 0.42, 0.4)
	for d in [5.0, 10.0, 15.0, 20.0]:
		draw_arc(center, d * scale, 0.0, TAU, 36, grid_color, 1.0)

	# 3. 十字レティクル
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), grid_color, 1.0)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), grid_color, 1.0)

	# 4. 外周コンパスリング＆目盛り
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.2, 0.55, 0.8, 0.75), 1.5)
	draw_arc(center, radius + 3.0, 0.0, TAU, 64, Color(0.1, 0.3, 0.5, 0.4), 1.0)

	# 方位目盛り（4方向のティックマーク）
	var tick_len := 4.0
	draw_line(center + Vector2(0, -radius), center + Vector2(0, -radius + tick_len), Color(0.3, 0.85, 1.0), 2.0)
	draw_line(center + Vector2(0, radius), center + Vector2(0, radius - tick_len), Color(0.2, 0.55, 0.8), 1.5)
	draw_line(center + Vector2(-radius, 0), center + Vector2(-radius + tick_len, 0), Color(0.2, 0.55, 0.8), 1.5)
	draw_line(center + Vector2(radius, 0), center + Vector2(radius - tick_len, 0), Color(0.2, 0.55, 0.8), 1.5)

	# 方位文字 "N"
	var font := get_theme_default_font()
	draw_string(font, center + Vector2(-4, -radius - 5), "N", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.3, 0.85, 1.0))

	# 5. 回転走査スキャナービーム（走査線）
	var sweep_dir := Vector2(cos(_sweep_angle), sin(_sweep_angle))
	draw_line(center, center + sweep_dir * radius, Color(0.2, 0.9, 1.0, 0.5), 1.5)
	# スイープグラデーション（扇型の淡い残像）
	for i in range(1, 8):
		var ang := _sweep_angle - float(i) * 0.05
		var a_dir := Vector2(cos(ang), sin(ang))
		var a_color := Color(0.15, 0.7, 0.9, 0.25 * (1.0 - float(i) / 8.0))
		draw_line(center, center + a_dir * radius, a_color, 1.5)

	if _frame == null or _frame.local == null:
		return

	var origin := _frame.local.pos
	var sight := maxf(_visible_range, 2.5) + 1.0

	# 6. 視界範囲（プレイヤーの光学センサー視認可能限界）
	draw_arc(center, minf(sight, RANGE) * scale, 0.0, TAU, 48, Color(0.95, 0.6, 0.15, 0.5), 1.2)

	# 7. 遮蔽物（壁）の描画
	if _geometry != null:
		for i in _geometry.box_count:
			var lo := _geometry.box_min(i)
			var hi := _geometry.box_max(i)
			var top_left := center + (Vector2(lo.x, lo.y) - Vector2(origin.x, origin.z)) * scale
			var box_sz := (hi - lo) * scale
			var rect := Rect2(top_left, box_sz)
			
			# 円形レーダー内にクリップされるように簡易判定
			if (rect.position + rect.size * 0.5 - center).length() < radius + 15.0:
				var height := _geometry.box_top(i)
				var is_high := height > 1.2
				var fill_c := Color(0.1, 0.2, 0.35, 0.45) if is_high else Color(0.08, 0.3, 0.25, 0.35)
				var border_c := Color(0.25, 0.55, 0.8, 0.6) if is_high else Color(0.2, 0.7, 0.5, 0.5)
				draw_rect(rect, fill_c)
				draw_rect(rect, border_c, false, 1.0)

	# 8. 拾得アイテム（ダイアモンド形状）
	for pickup in _frame.pickups:
		if _in_sight(pickup.pos, origin, sight):
			var p_pos := _to_radar(pickup.pos, origin, center, scale)
			if (p_pos - center).length() <= radius:
				var p_color := Color(1.0, 0.8, 0.2, 0.9)
				if pickup.type_id == &"health": p_color = Color(1.0, 0.3, 0.4, 0.9)
				elif pickup.type_id == &"energy": p_color = Color(0.2, 0.85, 1.0, 0.9)
				
				# 菱形描画
				var d := 3.5
				var poly := PackedVector2Array([
					p_pos + Vector2(0, -d), p_pos + Vector2(d, 0),
					p_pos + Vector2(0, d), p_pos + Vector2(-d, 0)
				])
				draw_colored_polygon(poly, p_color)

	# 9. 敵エネミー（赤い警告マーカー ＆ 菱形ターゲット）
	for enemy in _frame.enemies:
		if _in_sight(enemy.pos, origin, sight):
			var e_pos := _to_radar(enemy.pos, origin, center, scale)
			if (e_pos - center).length() <= radius:
				var ed := 4.0
				var poly := PackedVector2Array([
					e_pos + Vector2(0, -ed), e_pos + Vector2(ed, 0),
					e_pos + Vector2(0, ed), e_pos + Vector2(-ed, 0)
				])
				draw_colored_polygon(poly, Color(1.0, 0.2, 0.25, 0.95))
				draw_polyline(poly, Color(1.0, 0.8, 0.8, 0.8), 1.0)

	# 10. 他プレイヤー（シアンの円）
	for player in _frame.players:
		if player.is_local or not player.alive or not _in_sight(player.pos, origin, sight):
			continue
		var pl_pos := _to_radar(player.pos, origin, center, scale)
		if (pl_pos - center).length() <= radius:
			draw_circle(pl_pos, 4.0, Color(0.2, 0.8, 1.0, 0.95))
			draw_arc(pl_pos, 6.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.6), 1.0)

	# 11. 自機: 洗練されたステルス戦闘機型デルタアロー（中央に配置）
	var forward := Vector2(-sin(_frame.local.yaw), -cos(_frame.local.yaw))
	var side := Vector2(-forward.y, forward.x)
	var arrow_poly := PackedVector2Array([
		center + forward * 8.0,
		center - forward * 5.0 + side * 5.0,
		center - forward * 2.5, # 後部インセット
		center - forward * 5.0 - side * 5.0,
	])
	draw_colored_polygon(arrow_poly, Color(0.95, 0.65, 0.15, 1.0))
	draw_polyline(arrow_poly, Color(1.0, 1.0, 1.0, 0.9), 1.2)


func _to_radar(pos: Vector3, origin: Vector3, center: Vector2, scale: float) -> Vector2:
	return center + Vector2(pos.x - origin.x, pos.z - origin.z) * scale


func _in_sight(pos: Vector3, origin: Vector3, sight: float) -> bool:
	return Vector2(pos.x - origin.x, pos.z - origin.z).length() <= sight
