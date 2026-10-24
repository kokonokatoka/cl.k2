class_name WorldGeometry
extends RefCounted
## 静的な世界。床（y=0）と軸並行ボックスだけで構成する。衝突はすべて Motion が計算し、Godot の物理は使わない。
## ボックスは「床から top までの中身が詰まった直方体」。数値は PackedFloat32Array に平たく持つ（高速化）。
## 範囲検索は一様グリッドで絞る。

enum Kind { WALL, LOW, MID, TALL }

const STRIDE: int = 5  # min_x, min_z, max_x, max_z, top
const CELL: float = 4.0

var half_size: float = 30.0
var box_data: PackedFloat32Array = PackedFloat32Array()
var box_kinds: PackedByteArray = PackedByteArray()
var box_count: int = 0

var player_spawns: PackedVector3Array = PackedVector3Array()
var enemy_spawns: PackedVector3Array = PackedVector3Array()
var pickup_spots: PackedVector3Array = PackedVector3Array()

var _origin: float = 0.0
var _grid_width: int = 0
var _cells: Array[PackedInt32Array] = []


func _init(arena_half_size: float = 30.0) -> void:
	half_size = arena_half_size


func add_box(min_x: float, min_z: float, max_x: float, max_z: float, top: float, kind: Kind = Kind.MID) -> int:
	box_data.append_array([min_x, min_z, max_x, max_z, top])
	box_kinds.append(kind)
	box_count += 1
	return box_count - 1


func box_min(i: int) -> Vector2:
	return Vector2(box_data[i * STRIDE], box_data[i * STRIDE + 1])


func box_max(i: int) -> Vector2:
	return Vector2(box_data[i * STRIDE + 2], box_data[i * STRIDE + 3])


func box_top(i: int) -> float:
	return box_data[i * STRIDE + 4]


## ボックスを全部足したあとに呼ぶ。検索用のグリッドを作る
func finalize() -> void:
	var extent := half_size + 6.0
	_origin = extent
	_grid_width = int(ceil(extent * 2.0 / CELL)) + 1
	_cells.clear()
	_cells.resize(_grid_width * _grid_width)
	for i in _cells.size():
		_cells[i] = PackedInt32Array()
	for i in box_count:
		var o := i * STRIDE
		var x0 := _cell_index(box_data[o])
		var z0 := _cell_index(box_data[o + 1])
		var x1 := _cell_index(box_data[o + 2])
		var z1 := _cell_index(box_data[o + 3])
		for cz in range(z0, z1 + 1):
			for cx in range(x0, x1 + 1):
				_cells[cz * _grid_width + cx].append(i)


## 矩形（XZ）に触れうるボックスの番号。重複を含みうる（呼び出し側は重複を気にしなくてよい作り）
func boxes_in_rect(min_x: float, min_z: float, max_x: float, max_z: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	if _cells.is_empty():
		return result
	var x0 := _cell_index(min_x)
	var z0 := _cell_index(min_z)
	var x1 := _cell_index(max_x)
	var z1 := _cell_index(max_z)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			result.append_array(_cells[cz * _grid_width + cx])
	return result


## 円（XZ）が、乗り越えられない高さのボックスと重ならない場所か
func is_free(x: float, z: float, radius: float) -> bool:
	for i in boxes_in_rect(x - radius, z - radius, x + radius, z + radius):
		var o := i * STRIDE
		var qx := clampf(x, box_data[o], box_data[o + 2])
		var qz := clampf(z, box_data[o + 1], box_data[o + 3])
		if (x - qx) * (x - qx) + (z - qz) * (z - qz) < radius * radius:
			return false
	return absf(x) <= half_size - radius and absf(z) <= half_size - radius


func _cell_index(value: float) -> int:
	return clampi(int(floor((value + _origin) / CELL)), 0, _grid_width - 1)
