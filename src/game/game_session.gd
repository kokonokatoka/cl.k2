class_name GameSession
extends Node
## ビューから見た「いまのゲーム」の共通の口。実体は LocalSession（ソロ）と ClientSession（オンライン）。
## ビューや UI はこのクラスだけを知っていればよい。

## シミュレーションで起きたこと（効果音・エフェクト・キルフィード用）。ネットワーク経由のものも同じ形で来る
signal sim_event(event: SimEvent)
signal chat_received(sender: String, text: String)
## 「接続しました」などの通知
signal notice(text: String, kind: int)
signal ended(reason: String)
## 世界の形と自分のプレイヤーが揃って、描画を始められる（オンラインでは接続とスナップショット待ち）
signal ready_to_play

var local_id: int = 0
## 自分のプレイヤー。オンラインでは予測中のもの（体力などはサーバーの値が入る）
var local_player: SimPlayer
var rules: GameRules = GameRules.new()
var geometry: WorldGeometry
## (seq: int) -> PlayerInput。入力の取得元（実機はキーボード/パッド、テストでは Bot）
var input_provider: Callable
## ポーズ中など。ソロはシミュレーションが止まる。オンラインは止められないので入力だけ無効になる
var paused: bool = false


func is_online() -> bool:
	return false


func is_ready() -> bool:
	return local_player != null and geometry != null


## 接続待ちなどの間に画面へ出す文言のキー（準備できていれば空）
func status_key() -> String:
	return ""


## alpha: 直前のティックと今のティックの間の位置（0〜1）。描画の滑らかさのため
func sample(_alpha: float) -> RenderFrame:
	return RenderFrame.new()


func request_equip(_part_id: StringName) -> void:
	pass


func request_unequip(_slot: RobotPart.Slot) -> void:
	pass


func send_chat(_text: String) -> void:
	pass


## [{id, name, score, kills, deaths, ping, local}]。スコア順
func scoreboard() -> Array[Dictionary]:
	return []


func ping_ms() -> int:
	return 0


## ロボットの色。名前と同じく、他のプレイヤーのぶんは通信で届く
func player_color(id: int) -> Color:
	return Color.from_hsv(fposmod(float(id) * 0.61803, 1.0), 0.55, 0.95)


## 表示用のプレイヤー名（キルフィード・チャットなど）
func player_name(id: int) -> String:
	for row in scoreboard():
		if row["id"] == id:
			return row["name"]
	return "?"


## 後片付け。セッションを閉じる前に呼ぶ
func shutdown(_reason: String = "") -> void:
	pass


## 開発用コンソールのコマンド。ソロだけが実装する。結果のメッセージを返す
func dev_command(_command: String, _args: PackedStringArray) -> String:
	return "not available in this session"


## このスロットに装備できる所持パーツ（定義順）
func owned_parts_for(slot: RobotPart.Slot) -> Array[RobotPart]:
	var result: Array[RobotPart] = []
	if local_player == null:
		return result
	for part in Content.parts_for_slot(slot):
		if local_player.inventory.has(part.id):
			result.append(part)
	return result


## 所持パーツと「なし」を順番に切り替える（step = 1 で次、-1 で前）
func cycle_slot(slot: RobotPart.Slot, step: int = 1) -> void:
	if local_player == null:
		return
	var options: Array = owned_parts_for(slot)
	options.append(null)
	var index := options.find(local_player.loadout.get_part(slot))
	var next: RobotPart = options[posmod(index + step, options.size())]
	if next != null:
		request_equip(next.id)
	else:
		request_unequip(slot)


## 描画用の RenderFrame に載せる、プレイヤーの共通部分
static func make_player_entity(p: SimPlayer, alpha: float, local_player_id: int) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = RenderFrame.Entity.Kind.PLAYER
	e.id = p.id
	e.pos = p.prev_pos.lerp(p.pos, alpha)
	e.yaw = lerp_angle(p.prev_yaw, p.yaw, alpha)
	e.velocity = p.vel
	e.alive = p.alive
	e.health_fraction = clampf(p.health / maxf(p.stats.max_health, 1.0), 0.0, 1.0)
	e.display_name = p.player_name
	e.is_local = p.id == local_player_id
	e.loadout = p.loadout.to_indices()
	if p.dash_time > 0.0:
		e.flags |= RenderFrame.Entity.FLAG_DASHING
	if p.invuln > 0.0:
		e.flags |= RenderFrame.Entity.FLAG_INVULN
	return e
