extends SceneTree
## ヘッドレステストランナー。
##
##   godot --headless --path . --import                                  # 初回のみ（グローバルクラスの登録）
##   godot --headless --path . -s res://tests/run_tests.gd               # 全部
##   godot --headless --path . -s res://tests/run_tests.gd -- --filter=sim   # ファイル名か「ファイル.メソッド」に含まれる文字列で絞る
##
## 失敗があれば終了コード 1。tests/test_*.gd のうち `test_` で始まるメソッドを実行する。

const TEST_DIR := "res://tests"


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr("--filter=".length())

	# _initialize の時点では autoload はまだツリーに入っておらず _ready も走っていない。1フレーム待つ。
	await process_frame

	# このスクリプトはメインループとして autoload の登録より先に読み込まれるため、autoload は名前で直接参照できない。
	# （テスト本体は後から load されるので、そちらでは Log / Settings などをそのまま使える）
	# テストがユーザーの設定・セーブを書き換えないようにする。
	root.get_node("Log").set("level", 2)  # Log.Level.WARN
	root.get_node("Settings").call("use_path", "user://test_settings.cfg")
	root.get_node("Save").call("use_path", "user://test_profile.json")

	var started := Time.get_ticks_msec()
	var total := 0
	var failed := 0
	var assertions := 0
	var failure_lines: PackedStringArray = []

	for file in _list_test_files():
		var script: GDScript = load("%s/%s" % [TEST_DIR, file])
		if script == null:
			failed += 1
			failure_lines.append("%s: failed to load (parse error?)" % file)
			continue
		var probe: TestCase = script.new()
		var methods: PackedStringArray = []
		for method in script.get_script_method_list():
			if String(method["name"]).begins_with("test_"):
				methods.append(method["name"])
		methods.sort()
		for method in methods:
			var label := "%s.%s" % [file.get_basename(), method]
			if filter != "" and not label.contains(filter):
				continue
			var test: TestCase = script.new()
			test.tree = self
			test.before_each()
			total += 1
			await test.call(method)
			test.after_each()
			assertions += test.assertion_count
			if test.failures.is_empty():
				print("  ok    %s" % label)
			else:
				failed += 1
				print("  FAIL  %s" % label)
				for message in test.failures:
					failure_lines.append("%s: %s" % [label, message])
		probe = null

	_cleanup()
	print("")
	for line in failure_lines:
		print("  ✗ %s" % line)
	print("%d tests, %d assertions, %d failed (%.1fs)" % [total, assertions, failed, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failed > 0 or total == 0 else 0)


func _list_test_files() -> PackedStringArray:
	var files: PackedStringArray = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return files
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()
	return files


func _cleanup() -> void:
	for file_name: String in ["test_settings.cfg", "test_profile.json", "test_profile.json.tmp", "test_profile.json.corrupt"]:
		var path := "user://" + file_name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
