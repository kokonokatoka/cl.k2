class_name RobotPart
extends Resource
## 換装パーツの基底データ。
## スロットごとのサブクラス（EyePart / LegPart / ArmPart / CorePart）が apply() で性能値を書き換える。
## `id` はネットワークとセーブで使う永続的な識別子。一度公開したら変えないこと。

enum Slot { EYES, LEGS, ARMS, CORE }
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const RARITY_COLORS: Array[Color] = [
	Color(0.75, 0.78, 0.82),
	Color(0.35, 0.65, 1.0),
	Color(0.75, 0.4, 1.0),
	Color(1.0, 0.72, 0.2),
]

@export var id: StringName = &""
@export var display_name: String = "Part"
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
## 初期所持（ソロ開始・サーバー参加時に最初から持っている）
@export var starter: bool = false
## ソケットに取り付ける見た目（任意）
@export var visual: PackedScene
## UI で使う色
@export var accent: Color = Color(0.9, 0.9, 0.9)
## 追加の性能補正（任意）
@export var modifiers: Array[StatModifier] = []


## 取り付け先のスロット。サブクラスで必ずオーバーライドする
func get_slot() -> Slot:
	return Slot.EYES


## 装備中のパーツが性能値の基準を書き込む。サブクラスでオーバーライドする
func apply(_stats: RobotStats) -> void:
	pass


## 翻訳があればそれを、なければ display_name を返す
func get_title() -> String:
	var key := "part.%s.name" % id
	var translated := String(TranslationServer.translate(key))
	return display_name if translated == key else translated


func get_description() -> String:
	var key := "part.%s.desc" % id
	var translated := String(TranslationServer.translate(key))
	return description if translated == key else translated


func get_rarity_color() -> Color:
	return RARITY_COLORS[rarity]


## このパーツが性能値にもたらす違いを一意に表す文字列。
## サーバーとクライアントでパーツ定義がずれていないかの検証に使う（Loadout が全部入りの性能値を比較する）。
func signature() -> String:
	var stats := RobotStats.new()
	apply(stats)
	stats.apply_modifiers(modifiers)
	return "%s|%d|%s" % [id, get_slot(), stats.signature()]


static func slot_name(slot: Slot) -> String:
	return Slot.keys()[slot].capitalize()


static func slot_key(slot: Slot) -> String:
	return Slot.keys()[slot].to_lower()
