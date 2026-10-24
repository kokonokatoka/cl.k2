class_name StatModifier
extends Resource
## 性能値への加算・乗算。パーツの追加効果、バフ、パークなどで使う。
## 適用順は「パーツの apply() → 全 ADD → 全 MULT」。

enum Op { ADD, MULT }

## RobotStats のプロパティ名（例: "move_speed"）
@export var stat: StringName = &""
@export var op: Op = Op.ADD
@export var value: float = 0.0


static func add(stat_name: StringName, amount: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat = stat_name
	m.op = Op.ADD
	m.value = amount
	return m


static func mult(stat_name: StringName, factor: float) -> StatModifier:
	var m := StatModifier.new()
	m.stat = stat_name
	m.op = Op.MULT
	m.value = factor
	return m
