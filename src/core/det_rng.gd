class_name DetRng
extends RefCounted
## 決定論的な乱数（mulberry32）。エンジンの版や OS が違っても同じ並びになる。
## シミュレーション・アリーナ生成・ドロップ抽選など、再現性が欲しい箇所は RandomNumberGenerator ではなくこちらを使う。

const MASK := 0xFFFFFFFF

var _state: int = 0


func _init(seed_value: int = 1) -> void:
	_state = seed_value & MASK


func get_state() -> int:
	return _state


func next_u32() -> int:
	_state = (_state + 0x6D2B79F5) & MASK
	var t := _state
	t = ((t ^ (t >> 15)) * (t | 1)) & MASK
	t = (t ^ ((t + (((t ^ (t >> 7)) * (t | 61)) & MASK)) & MASK)) & MASK
	return (t ^ (t >> 14)) & MASK


## [0, 1)
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


func range_float(from: float, to: float) -> float:
	return from + (to - from) * next_float()


## from 以上 to 以下（両端を含む）
func range_int(from: int, to: int) -> int:
	return from + int(next_u32() % (to - from + 1))


func chance(probability: float) -> bool:
	return next_float() < probability


func pick(items: Array) -> Variant:
	return items[int(next_u32() % items.size())]


## [-1, 1)
func next_signed() -> float:
	return next_float() * 2.0 - 1.0


## 2つの整数から別の整数を作る（弾ごとのばらつき用シードなど）
static func mix(a: int, b: int) -> int:
	var h := ((a * 0x9E3779B1) ^ (b * 0x85EBCA6B)) & MASK
	h = ((h ^ (h >> 16)) * 0x85EBCA6B) & MASK
	h = ((h ^ (h >> 13)) * 0xC2B2AE35) & MASK
	return (h ^ (h >> 16)) & MASK
