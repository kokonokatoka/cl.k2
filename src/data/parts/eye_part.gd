class_name EyePart
extends RobotPart
## 目パーツ: 視界の広さと色味を決める。視界の外の敵はサーバーも送ってこない（関連性）。

## 視界の半径[m]。0 で真っ暗
@export_range(0.0, 40.0, 0.1) var vision_range: float = 7.0
## 視界に重ねる色（アルファ = 強さ）
@export var vision_tint: Color = Color(0, 0, 0, 0)


func get_slot() -> Slot:
	return Slot.EYES


func apply(stats: RobotStats) -> void:
	stats.vision_range = vision_range
	stats.vision_tint = vision_tint
