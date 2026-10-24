class_name CorePart
extends RobotPart
## コアパーツ: 体力・エネルギー・装甲。ダッシュと射撃はエネルギーを使うので、再生量が火力に直結する。

@export var max_health: float = 100.0
@export var max_energy: float = 100.0
@export var energy_regen: float = 14.0
## 被ダメージから引く固定値（最低でも1割は通る）
@export var armor: float = 0.0


func get_slot() -> Slot:
	return Slot.CORE


func apply(stats: RobotStats) -> void:
	stats.max_health = max_health
	stats.max_energy = max_energy
	stats.energy_regen = energy_regen
	stats.armor = armor
