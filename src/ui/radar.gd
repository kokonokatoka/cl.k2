class_name Radar
extends Control
## 右下のレーダー。自分の目に見えている範囲の敵・味方・拾い物と壁を表示する（見えないものは出さない）。

const SIZE := 170.0
## レーダーが映すワールドの半径[m]
const RANGE := 22.0

var _geometry: WorldGeometry
var _frame: RenderFrame
var _visible_range: float = 7.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_geometry(geometry: WorldGeometry) -> void:
	_geometry = geometry


func update_frame(frame: RenderFrame, vision_range: float) -> void:
	_frame = frame
	_visible_range = vision_range
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.8))
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_BORDER, false, 1.0)
	if _frame == null or _frame.local == null:
		return
	var center := size * 0.5
	var scale := SIZE * 0.5 / RANGE
	var origin := _frame.local.pos
	var sight := maxf(_visible_range, 2.5) + 1.0

	# 視界の円
	draw_arc(center, minf(sight, RANGE) * scale, 0.0, TAU, 40, Color(UiTheme.ACCENT, 0.35), 1.0)

	if _geometry != null:
		for i in _geometry.box_count:
			var lo := _geometry.box_min(i)
			var hi := _geometry.box_max(i)
			var top_left := center + (Vector2(lo.x, lo.y) - Vector2(origin.x, origin.z)) * scale
			var rect := Rect2(top_left, (hi - lo) * scale)
			var height := _geometry.box_top(i)
			var tint := Color(0.5, 0.58, 0.7, 0.55) if height > 1.2 else Color(0.3, 0.75, 0.65, 0.4)
			draw_rect(rect, tint)

	for pickup in _frame.pickups:
		if _in_sight(pickup.pos, origin, sight):
			var color := Color(1, 0.85, 0.3)
			if pickup.type_id == &"health":
				color = Color(1, 0.4, 0.45)
			elif pickup.type_id == &"energy":
				color = Color(0.3, 0.9, 1)
			draw_rect(Rect2(_to_radar(pickup.pos, origin, center, scale) - Vector2(2, 2), Vector2(4, 4)), color)
	for enemy in _frame.enemies:
		if _in_sight(enemy.pos, origin, sight):
			draw_circle(_to_radar(enemy.pos, origin, center, scale), 3.5, Color(1.0, 0.3, 0.3))
	for player in _frame.players:
		if player.is_local or not player.alive or not _in_sight(player.pos, origin, sight):
			continue
		draw_circle(_to_radar(player.pos, origin, center, scale), 3.5, Color(0.45, 0.75, 1.0))

	# 自分: 向きを示す三角
	var forward := Vector2(-sin(_frame.local.yaw), -cos(_frame.local.yaw))
	var side := Vector2(-forward.y, forward.x)
	draw_colored_polygon(PackedVector2Array([
		center + forward * 7.0, center - forward * 4.0 + side * 4.5, center - forward * 4.0 - side * 4.5,
	]), UiTheme.ACCENT)


func _in_sight(pos: Vector3, origin: Vector3, sight: float) -> bool:
	return Vector2(pos.x - origin.x, pos.z - origin.z).length() <= sight


func _to_radar(pos: Vector3, origin: Vector3, center: Vector2, scale: float) -> Vector2:
	return center + Vector2(pos.x - origin.x, pos.z - origin.z) * scale
