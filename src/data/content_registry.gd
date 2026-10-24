extends Node
## パーツと敵の定義を集めたレジストリ（autoload: Content）。
## ID → 定義の引き当て、ネットワーク用の番号（インデックス）、サーバーとのコンテンツ照合を担う。
##
## 新しいパーツ/敵は `content/` に .tres を足して、下の PART_PATHS / ENEMY_PATHS に1行足す。
## ディレクトリを走査しないのは、Web 書き出しでは .tres が .remap に置き換わって列挙が不安定なため。

const PART_PATHS: Array[String] = [
	"res://content/parts/eye_standard.tres",
	"res://content/parts/eye_scope.tres",
	"res://content/parts/eye_night.tres",
	"res://content/parts/eye_oracle.tres",
	"res://content/parts/legs_standard.tres",
	"res://content/parts/legs_roller.tres",
	"res://content/parts/legs_spring.tres",
	"res://content/parts/legs_tank.tres",
	"res://content/parts/arms_blaster.tres",
	"res://content/parts/arms_scatter.tres",
	"res://content/parts/arms_pulse.tres",
	"res://content/parts/arms_rail.tres",
	"res://content/parts/core_standard.tres",
	"res://content/parts/core_reactor.tres",
	"res://content/parts/core_plate.tres",
	"res://content/parts/core_glass.tres",
	"res://content/parts/core_singularity.tres",
]

const ENEMY_PATHS: Array[String] = [
	"res://content/enemies/scout.tres",
	"res://content/enemies/gunner.tres",
	"res://content/enemies/brute.tres",
]

## ドロップ抽選の重み（RobotPart.Rarity の順）
const RARITY_WEIGHTS: Array[int] = [60, 28, 9, 3]

var _loaded: bool = false
var _parts: Array[RobotPart] = []
var _parts_by_id: Dictionary = {}
var _enemies: Array[EnemyDef] = []
var _enemies_by_id: Dictionary = {}
var _hash: int = 0


func _ready() -> void:
	_ensure_loaded()


func part(id: StringName) -> RobotPart:
	_ensure_loaded()
	return _parts_by_id.get(id)


## 全パーツ（スロット順 → 定義順）
func all_parts() -> Array[RobotPart]:
	_ensure_loaded()
	return _parts


func parts_for_slot(slot: RobotPart.Slot) -> Array[RobotPart]:
	_ensure_loaded()
	var result: Array[RobotPart] = []
	for p in _parts:
		if p.get_slot() == slot:
			result.append(p)
	return result


func starter_parts() -> Array[RobotPart]:
	_ensure_loaded()
	var result: Array[RobotPart] = []
	for p in _parts:
		if p.starter:
			result.append(p)
	return result


## ネットワーク上の番号。-1 は「なし」
func part_index(id: StringName) -> int:
	_ensure_loaded()
	var p: RobotPart = _parts_by_id.get(id)
	return _parts.find(p) if p else -1


func part_at(index: int) -> RobotPart:
	_ensure_loaded()
	return _parts[index] if index >= 0 and index < _parts.size() else null


func enemy(id: StringName) -> EnemyDef:
	_ensure_loaded()
	return _enemies_by_id.get(id)


func all_enemies() -> Array[EnemyDef]:
	_ensure_loaded()
	return _enemies


func enemy_index(id: StringName) -> int:
	_ensure_loaded()
	var e: EnemyDef = _enemies_by_id.get(id)
	return _enemies.find(e) if e else -1


func enemy_at(index: int) -> EnemyDef:
	_ensure_loaded()
	return _enemies[index] if index >= 0 and index < _enemies.size() else null


## 全定義の内容から作るハッシュ。サーバーとクライアントでバランスや順序が食い違っていないかの検証に使う
func content_hash() -> int:
	_ensure_loaded()
	return _hash


## レア度の重みでドロップするパーツを選ぶ（スターターは除く）。
## bias が大きいほどレア度が高いほど重くなり、レアが出やすくなる
func roll_part_drop(rng: DetRng, bias: int = 0) -> RobotPart:
	_ensure_loaded()
	var weights: Array[float] = []
	var total := 0.0
	for p in _parts:
		var w := 0.0
		if not p.starter:
			w = float(RARITY_WEIGHTS[p.rarity]) * pow(1.0 + 0.5 * bias, float(p.rarity))
		weights.append(w)
		total += w
	if total <= 0.0:
		return null
	var roll := rng.next_float() * total
	for i in _parts.size():
		roll -= weights[i]
		if roll <= 0.0 and weights[i] > 0.0:
			return _parts[i]
	return _parts[_parts.size() - 1]


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for path in PART_PATHS:
		var res := load(path) as RobotPart
		if res == null:
			Log.error("content", "failed to load part: %s" % path)
			continue
		if res.id == &"" or _parts_by_id.has(res.id):
			Log.error("content", "part has empty or duplicate id: %s (%s)" % [res.id, path])
			continue
		_parts.append(res)
		_parts_by_id[res.id] = res
	for path in ENEMY_PATHS:
		var res := load(path) as EnemyDef
		if res == null:
			Log.error("content", "failed to load enemy: %s" % path)
			continue
		if res.id == &"" or _enemies_by_id.has(res.id):
			Log.error("content", "enemy has empty or duplicate id: %s (%s)" % [res.id, path])
			continue
		_enemies.append(res)
		_enemies_by_id[res.id] = res
	var sig := PackedStringArray()
	for p in _parts:
		sig.append(p.signature())
	for e in _enemies:
		sig.append(e.signature())
	_hash = Hashing.fnv1a_string("\n".join(sig))
	Log.info("content", "loaded %d parts, %d enemies (hash %08x)" % [_parts.size(), _enemies.size(), _hash])
