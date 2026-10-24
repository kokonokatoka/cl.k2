class_name TagTable
extends RefCounted
## SimEvent.tag や弾の種類などの「名前」を、通信用の小さな番号に対応づける。
## 並びは固定の語＋コンテンツ（武器・敵・パーツ）の定義順。サーバーとクライアントで content_hash が一致していれば同じ並びになる。

const FIXED: Array[StringName] = [&"", &"player", &"health", &"energy", &"enemy"]

static var _tags: Array[StringName] = []
static var _index: Dictionary = {}


static func index_of(tag: StringName) -> int:
	_ensure()
	return _index.get(tag, 0)


static func at(index: int) -> StringName:
	_ensure()
	return _tags[index] if index >= 0 and index < _tags.size() else &""


## コンテンツが変わったあと（テストなど）に作り直す
static func rebuild() -> void:
	_tags = []
	_index = {}
	_ensure()


static func _ensure() -> void:
	if not _tags.is_empty():
		return
	for tag in FIXED:
		_add(tag)
	for part in Content.all_parts():
		if part is ArmPart:
			_add(part.weapon_kind)
	for enemy in Content.all_enemies():
		_add(enemy.id)
	for part in Content.all_parts():
		_add(part.id)
	assert(_tags.size() < 256, "tag table must fit in one byte")


static func _add(tag: StringName) -> void:
	if not _index.has(tag):
		_index[tag] = _tags.size()
		_tags.append(tag)
