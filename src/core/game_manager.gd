extends Node
## ゲーム全体の流れ（autoload: Game）。メニュー ↔ ゲーム ↔ 専用サーバーの切り替えと、シーン間の引き継ぎ。

enum State { BOOT, MENU, PLAYING, SERVER }

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"

signal state_changed(previous: State, current: State)

var state: State = State.BOOT
## 次のゲームシーンへの引き継ぎ（mode: "solo" / "online"、seed、url など）
var pending: Dictionary = {}
## 動いている専用サーバー（--server のとき）
var server: Node
## メニューに戻ったときに 1 度だけ出すメッセージ（接続エラーなど）。表示したら空にする
var menu_notice: String = ""


func go_menu() -> void:
	_set_state(State.MENU)
	pending = {}
	Router.go(MENU_SCENE)


func start_solo(arena_seed: int = 0) -> void:
	pending = {"mode": "solo", "seed": arena_seed if arena_seed != 0 else int(Time.get_ticks_usec() & 0x7FFFFFFF)}
	_set_state(State.PLAYING)
	Router.go(GAME_SCENE)


func start_online(url: String) -> void:
	pending = {"mode": "online", "url": url}
	_set_state(State.PLAYING)
	Router.go(GAME_SCENE)


## 専用サーバーを起動する（ビューなし）。ポートなどは起動オプションから
func start_server() -> void:
	_set_state(State.SERVER)
	server = GameServer.new()
	server.name = "GameServer"
	add_child(server)
	server.start(Cfg.get_int("port", NetProtocol.DEFAULT_PORT), Cfg.get_int("max-players", 16), Cfg.get_int("seed", 0))


## ビューなしの自動操縦クライアントを起動する（結合テスト用）
func start_bot_client(url: String) -> void:
	_set_state(State.PLAYING)
	var bot := BotClient.new()
	bot.name = "BotClient"
	add_child(bot)
	bot.start(url, Cfg.get_string("name", "Bot"))


func quit_game() -> void:
	Save.flush()
	Settings.save()
	get_tree().quit()


func _set_state(next: State) -> void:
	if next == state:
		return
	var previous := state
	state = next
	state_changed.emit(previous, next)
