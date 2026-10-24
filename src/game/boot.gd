extends Node
## 起動時に最初に動くシーン。起動オプションを見て、メニュー・ソロ・専用サーバーなどへ振り分ける。

const MECHA_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	Log.info("boot", "C.K.1.2 booting (headless=%s)" % Cfg.is_headless())
	if Cfg.has("log"):
		Log.set_level_by_name(Cfg.get_string("log"))
	_install_screenshot_helper()
	# 他の autoload の準備が済むのを 1 フレーム待ってから振り分ける
	await get_tree().process_frame
	if Cfg.is_server():
		Game.start_server()
	elif Cfg.get_bool("bot-client"):
		Game.start_bot_client(Cfg.get_string("connect", "ws://127.0.0.1:%d" % NetProtocol.DEFAULT_PORT))
	elif Cfg.get_bool("mecha"):
		# 別設計の 3D メカ組み立てプロトタイプ（scenes/main.tscn）
		get_tree().change_scene_to_file.call_deferred(MECHA_SCENE)
	elif Cfg.has("connect"):
		Game.start_online(Cfg.get_string("connect"))
	elif Cfg.get_bool("solo"):
		Game.start_solo(Cfg.get_int("seed", 0))
	else:
		Game.go_menu()


func _install_screenshot_helper() -> void:
	if not Cfg.has("screenshot"):
		return
	var helper := DevScreenshot.new()
	helper.path = Cfg.get_string("screenshot")
	helper.frames = Cfg.get_int("screenshot-frames", 150)
	get_tree().root.add_child.call_deferred(helper)
