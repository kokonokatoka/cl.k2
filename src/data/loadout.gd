class_name Loadout
extends RefCounted
## 4スロット分の装備状態。性能値の組み立てと、ID との相互変換（ネットワーク・セーブ用）を担う。

## RobotPart.Slot -> RobotPart（空きスロットはキーなし）
var _parts: Dictionary = {}


func get_part(slot: RobotPart.Slot) -> RobotPart:
	return _parts.get(slot)


func has_slot(slot: RobotPart.Slot) -> bool:
	return _parts.has(slot)


func equip(part: RobotPart) -> void:
	_parts[part.get_slot()] = part


func unequip(slot: RobotPart.Slot) -> void:
	_parts.erase(slot)


func is_equipped(part: RobotPart) -> bool:
	return _parts.get(part.get_slot()) == part


func parts() -> Array[RobotPart]:
	var result: Array[RobotPart] = []
	for slot in RobotPart.Slot.values():
		if _parts.has(slot):
			result.append(_parts[slot])
	return result


func duplicate_loadout() -> Loadout:
	var copy := Loadout.new()
	copy._parts = _parts.duplicate()
	return copy


## 初期値 → 各パーツの apply() → 全パーツの modifiers（ADD → MULT）の順に組み立てる
func build_stats(extra_modifiers: Array = []) -> RobotStats:
	var stats := RobotStats.new()
	var all_modifiers: Array = []
	for part in parts():
		part.apply(stats)
		all_modifiers.append_array(part.modifiers)
	all_modifiers.append_array(extra_modifiers)
	stats.apply_modifiers(all_modifiers)
	return stats


## {slot: id} の辞書（空きスロットは含まない）
func to_ids() -> Dictionary:
	var ids := {}
	for slot in _parts:
		ids[int(slot)] = String(_parts[slot].id)
	return ids


## 不明な ID は無視する（古いセーブ・新旧クライアントの差を吸収する）
static func from_ids(ids: Dictionary) -> Loadout:
	var loadout := Loadout.new()
	for slot in ids:
		var part := Content.part(StringName(ids[slot]))
		if part != null and int(part.get_slot()) == int(slot):
			loadout.equip(part)
	return loadout


## スロット順に並べたパーツ番号（-1 = 空き）。スナップショット用
func to_indices() -> PackedInt32Array:
	var indices := PackedInt32Array()
	for slot in RobotPart.Slot.values():
		var part: RobotPart = _parts.get(slot)
		indices.append(Content.part_index(part.id) if part else -1)
	return indices


static func from_indices(indices: PackedInt32Array) -> Loadout:
	var loadout := Loadout.new()
	for i in mini(indices.size(), RobotPart.Slot.size()):
		var part := Content.part_at(indices[i])
		if part != null and int(part.get_slot()) == i:
			loadout.equip(part)
	return loadout
