class_name OverheadLabels
extends Control
## 頭上の名前と体力バー。ワールドの位置を画面へ投影して 1 枚の Control に描く（ノードを増やさない）。
## 視界オーバーレイより下の層に置くので、暗闇の中の相手の名前は見えない。

const BAR_SIZE := Vector2(46, 5)

var _frame: RenderFrame
var _camera: Camera3D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func update_frame(frame: RenderFrame, camera: Camera3D) -> void:
	_frame = frame
	_camera = camera
	queue_redraw()


func _draw() -> void:
	if _frame == null or _camera == null:
		return
	var font := get_theme_default_font()
	for player in _frame.players:
		if player.is_local or not player.alive:
			continue
		var anchor := player.pos + Vector3(0, 1.9 + _ride_height_of(player), 0)
		var at := _project(anchor)
		if at == Vector2.INF:
			continue
		draw_string_outline(font, at + Vector2(-60, -12), player.display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, at + Vector2(-60, -12), player.display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, UiTheme.TEXT)
		_draw_bar(at, player.health_fraction, UiTheme.HEALTH)
	for enemy in _frame.enemies:
		if enemy.health_fraction >= 0.999:
			continue
		var at := _project(enemy.pos + Vector3(0, 2.0, 0))
		if at != Vector2.INF:
			_draw_bar(at, enemy.health_fraction, Color(1.0, 0.5, 0.25))


func _draw_bar(center: Vector2, fraction: float, color: Color) -> void:
	var top_left := center - Vector2(BAR_SIZE.x * 0.5, 0)
	draw_rect(Rect2(top_left - Vector2(1, 1), BAR_SIZE + Vector2(2, 2)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(top_left, Vector2(BAR_SIZE.x * clampf(fraction, 0.0, 1.0), BAR_SIZE.y)), color)


func _project(world_position: Vector3) -> Vector2:
	if _camera.is_position_behind(world_position):
		return Vector2.INF
	return _camera.unproject_position(world_position)


## 装備している足の長さ（頭上の位置を持ち上げる）
func _ride_height_of(player: RenderFrame.Entity) -> float:
	if player.loadout.size() > RobotPart.Slot.LEGS:
		var part := Content.part_at(player.loadout[RobotPart.Slot.LEGS])
		if part is LegPart:
			return part.ride_height
	return 0.0
