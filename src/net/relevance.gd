class_name Relevance
extends RefCounted
## 「このプレイヤーに何を送るか」の関連性（interest management）。
## 目パーツの視界と連動する: 視界の外にいる敵の位置は、サーバーがそもそも送らない（壁抜け・透視チートの対策にもなる）。

## 視界が 0（目なし）でも、これだけの距離は常に送る
const MIN_RADIUS: float = 3.0
## 視界の外側の余白（画面端で急に現れないように）
const MARGIN: float = 4.0
## 弾は速いので、さらに広めに送る
const PROJECTILE_EXTRA: float = 6.0


static func radius_for(player: SimPlayer) -> float:
	return maxf(player.stats.vision_range, MIN_RADIUS) * 1.15 + MARGIN


static func is_relevant(player: SimPlayer, at: Vector3, extra: float = 0.0) -> bool:
	var radius := radius_for(player) + extra
	var dx := at.x - player.pos.x
	var dz := at.z - player.pos.z
	return dx * dx + dz * dz <= radius * radius
