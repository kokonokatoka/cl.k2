class_name RobotStats
extends RefCounted
## ロボットの最終的な性能値。初期値は「パーツが何も付いていない状態（むき出しの胴体）」。
## 組み立て順: 初期値 → 各パーツの apply() → StatModifier の ADD → MULT（Loadout.build_stats 参照）。

# --- 足: 足なしは胴体で這いずる。ジャンプ・ダッシュ不可 ---
var move_speed: float = 1.5
var acceleration: float = 20.0
var jump_velocity: float = 0.0
## 足の長さ。胴体をこの高さに持ち上げる（被弾判定の上端にも効く）
var ride_height: float = 0.0
var dash_speed: float = 0.0
var dash_time: float = 0.0
var dash_cost: float = 0.0
var dash_cooldown: float = 0.5

# --- 目: 目なしは何も見えない ---
## 視界の半径[m]。0 で真っ暗
var vision_range: float = 0.0
var vision_tint: Color = Color(0, 0, 0, 0)

# --- 腕: 腕なしは撃てない（fire_interval = 0） ---
var weapon_kind: StringName = &""
var weapon_damage: float = 0.0
var fire_interval: float = 0.0
var projectile_speed: float = 0.0
var projectile_life: float = 0.0
var pellets: int = 1
## 弾のばらつき（片側のラジアン）
var spread: float = 0.0
var shot_cost: float = 0.0
## 貫通する敵の数
var pierce: int = 0

# --- コア: 体力とエネルギー ---
var max_health: float = 60.0
var max_energy: float = 40.0
var energy_regen: float = 6.0
var armor: float = 0.0

## StatModifier で触れる数値の性能値
const MODIFIABLE: PackedStringArray = [
	"move_speed", "acceleration", "jump_velocity", "ride_height",
	"dash_speed", "dash_time", "dash_cost", "dash_cooldown",
	"vision_range",
	"weapon_damage", "fire_interval", "projectile_speed", "projectile_life",
	"spread", "shot_cost",
	"max_health", "max_energy", "energy_regen", "armor",
]


func can_fire() -> bool:
	return fire_interval > 0.0


func can_dash() -> bool:
	return dash_speed > 0.0 and dash_time > 0.0


## 同じ性能値かどうか（テスト・ネットワーク検証用）
func signature() -> String:
	var parts := PackedStringArray()
	for stat in MODIFIABLE:
		parts.append("%s=%.4f" % [stat, float(get(stat))])
	parts.append("pellets=%d" % pellets)
	parts.append("pierce=%d" % pierce)
	parts.append("weapon=%s" % weapon_kind)
	return ";".join(parts)


func apply_modifiers(modifiers: Array) -> void:
	# ADD を先に、MULT を後に。同じ種類同士は順不同で結果が変わらない
	for m: StatModifier in modifiers:
		if m.op == StatModifier.Op.ADD:
			_modify(m, func(current: float) -> float: return current + m.value)
	for m: StatModifier in modifiers:
		if m.op == StatModifier.Op.MULT:
			_modify(m, func(current: float) -> float: return current * m.value)


func _modify(m: StatModifier, fn: Callable) -> void:
	if not MODIFIABLE.has(String(m.stat)):
		Log.warn("stats", "unknown stat in modifier: %s" % m.stat)
		return
	set(m.stat, fn.call(float(get(m.stat))))
