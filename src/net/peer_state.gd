class_name PeerState
extends RefCounted
## サーバーが接続ごとに持つ状態。入力キュー・レート制限・確認応答など。

var id: int = 0
var joined: bool = false
var player_name: String = ""
var color_hex: String = "e8913a"
var connected_msec: int = 0
var last_input_msec: int = 0
var ping_ms: int = 0

var queue: Array[PlayerInput] = []
## キューが溢れて捨てた入力の数（通信が詰まっている・速度チートの目安）
var dropped: int = 0
var last_input: PlayerInput
var repeat_count: int = 0
var last_enqueued_seq: int = 0

## メッセージ数の制限（トークンバケット）。連打・洪水攻撃への備え
var budget: float = BUDGET_MAX
var last_chat_msec: int = -100000

const BUDGET_MAX := 240.0
const BUDGET_REFILL_PER_SECOND := 120.0


func _init(peer_id: int = 0) -> void:
	id = peer_id
	connected_msec = Time.get_ticks_msec()
	last_input_msec = connected_msec


func refill(delta: float) -> void:
	budget = minf(BUDGET_MAX, budget + BUDGET_REFILL_PER_SECOND * delta)


## 1 メッセージ分の予算を使う。足りなければ false（その通信は無視する）
func spend(cost: float = 1.0) -> bool:
	if budget < cost:
		return false
	budget -= cost
	return true


## 入力をキューに入れる。古い番号・重複は捨てる（入力は冗長に送られてくる）
func enqueue(input: PlayerInput) -> bool:
	if input.seq <= last_enqueued_seq:
		return false
	last_enqueued_seq = input.seq
	queue.append(input)
	last_input_msec = Time.get_ticks_msec()
	# 溜まりすぎたら古いものを捨てる（速度チート・遅延の累積を防ぐ）
	while queue.size() > SimConfig.INPUT_QUEUE_MAX:
		queue.pop_front()
		dropped += 1
	return true


## 次のティックで使う入力。無ければ最後の入力を少しだけ繰り返し、それも尽きたら何も押していない扱い
func take() -> PlayerInput:
	if not queue.is_empty():
		last_input = queue.pop_front()
		repeat_count = 0
		return last_input
	if last_input != null and repeat_count < SimConfig.INPUT_REPEAT_MAX:
		repeat_count += 1
		return last_input
	return null
