class_name SimEvent
extends RefCounted
## シミュレーションで起きたこと。効果音・エフェクト・キルフィード・ネットワーク送信が購読する。
## シミュレーション自身は結果を見た目に反映せず、イベントを積むだけ。

enum Type {
	SHOT,         ## a=撃ったプレイヤー, tag=武器の種類, pos=銃口
	ENEMY_SHOT,   ## a=敵ID, pos=銃口
	HIT,          ## a=攻撃者(プレイヤーID/0), b=被弾者, value=ダメージ, tag="player"か敵ID, pos=命中位置
	HIT_WORLD,    ## 弾が壁に当たった。pos=命中位置
	KILL,         ## a=倒したプレイヤー(0=敵・なし), b=倒された者, value=得点, tag="player"か敵ID, pos
	RESPAWN,      ## a=プレイヤー, pos
	JUMP,         ## a=プレイヤー, pos
	LAND,         ## a=プレイヤー, pos
	DASH,         ## a=プレイヤー, pos
	PICKUP,       ## a=拾ったプレイヤー, tag=パーツID/"health"/"energy", value=1(新規)/0(重複), pos
	ENEMY_SPAWN,  ## a=敵ID, tag=敵の種類, pos
	ENEMY_WINDUP, ## a=敵ID, pos（突進の予兆）
}

var type: Type = Type.SHOT
var pos: Vector3 = Vector3.ZERO
var a: int = 0
var b: int = 0
var value: float = 0.0
var tag: StringName = &""


static func make(event_type: Type, at: Vector3, a_id: int = 0, b_id: int = 0, amount: float = 0.0, label: StringName = &"") -> SimEvent:
	var e := SimEvent.new()
	e.type = event_type
	e.pos = at
	e.a = a_id
	e.b = b_id
	e.value = amount
	e.tag = label
	return e
