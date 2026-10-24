extends TestCase
## 結合テスト: 実際の Godot プロセスを起動して、本物の WebSocket で通信する。
##   専用サーバー 1 つ ＋ ボットクライアント（自動操縦）複数。擬似的な遅延・ジッタ・ロスも掛ける。
## 各プロセスは結果を JSON に書いて終了する（ユーザーデータ領域の e2e_*.json）。1 テストに十数秒かかる。

const BOT_SECONDS := 9.0

var _pids: Array[int] = []
var _files: Array[String] = []


func after_each() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	for path in _files:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_pids.clear()
	_files.clear()


func _project_args() -> PackedStringArray:
	return PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://")])


func _result_path(name: String) -> String:
	var path := ProjectSettings.globalize_path("user://e2e_%s.json" % name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_files.append(path)
	return path


func _spawn(extra: Array, label: String) -> int:
	var args := _project_args()
	args.append("--")
	args.append_array(PackedStringArray(extra))
	var pid := OS.create_process(OS.get_executable_path(), args)
	assert_true(pid > 0, "could not start %s" % label)
	_pids.append(pid)
	return pid


func _wait_for_exit(pid: int, timeout_seconds: float) -> bool:
	var waited := 0.0
	while OS.is_process_running(pid) and waited < timeout_seconds:
		await wait(0.25)
		waited += 0.25
	return not OS.is_process_running(pid)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


func _port() -> int:
	return 20000 + int(Time.get_ticks_usec() % 9000)


func test_two_bots_play_together_over_real_sockets() -> void:
	var port := _port()
	var server_result := _result_path("server")
	var bot_a := _result_path("bot_a")
	var bot_b := _result_path("bot_b")
	var url := "ws://127.0.0.1:%d" % port
	# 小さなアリーナなら、ボットどうしが必ず互いの視界に入る
	var server := _spawn(["--server", "--port=%d" % port, "--seed=21", "--arena=14", "--enemies=2",
		"--duration=%d" % int(BOT_SECONDS + 5.0), "--result=%s" % server_result, "--log=warn"], "server")
	await wait(2.0)
	var a := _spawn(["--bot-client", "--connect=%s" % url, "--name=BotA", "--bot-seed=1", "--duration=%f" % BOT_SECONDS,
		"--result=%s" % bot_a, "--latency=40", "--jitter=15", "--loss=0.03", "--log=warn"], "bot A")
	var b := _spawn(["--bot-client", "--connect=%s" % url, "--name=BotB", "--bot-seed=2", "--duration=%f" % BOT_SECONDS,
		"--result=%s" % bot_b, "--latency=70", "--jitter=25", "--loss=0.03", "--log=warn"], "bot B")
	assert_true(await _wait_for_exit(a, BOT_SECONDS + 12.0), "bot A finished")
	assert_true(await _wait_for_exit(b, BOT_SECONDS + 12.0), "bot B finished")
	assert_true(await _wait_for_exit(server, 15.0), "server finished")

	var ra := _read(bot_a)
	var rb := _read(bot_b)
	var rs := _read(server_result)
	assert_false(ra.is_empty() or rb.is_empty() or rs.is_empty(), "all three wrote results")
	if ra.is_empty() or rb.is_empty() or rs.is_empty():
		return
	print("    server: ", JSON.stringify(rs))
	print("    bot A : ", JSON.stringify(ra))
	print("    bot B : ", JSON.stringify(rb))

	for r in [ra, rb]:
		assert_true(r["connected"], "joined the match")
		assert_true(r["snapshots"] > BOT_SECONDS * 8.0, "kept receiving snapshots (%d)" % r["snapshots"])
		assert_true(r["max_players_seen"] >= 2, "saw the other bot")
		assert_true(r["distance"] > 5.0, "moved around (%.1f m)" % r["distance"])
		assert_true(r["events"] > 0, "received game events")
		assert_true(r["chat_received"] >= 1, "chat reached the other players")
		assert_true(r["snaps"] <= 5, "few hard corrections on a lossy link (%d)" % r["snaps"])
		assert_true(r["max_error"] < 4.0, "bounded prediction error (%.2f m)" % r["max_error"])
		assert_true(r["ping_ms"] > 0, "ping measured")
	assert_true(rs["joins"] >= 2)
	assert_true(rs["players_peak"] >= 2)
	assert_eq(rs["rejects"], 0)
	assert_true(rs["ticks"] > 60 * (BOT_SECONDS + 3.0) * 0.8, "the server kept its tick rate (%d ticks)" % rs["ticks"])
	assert_true(rs["avg_tick_ms"] < 8.0, "server tick cost %.2f ms" % rs["avg_tick_ms"])
	assert_true(rs["snapshots"] > 100)


func test_a_client_with_a_different_protocol_version_is_refused() -> void:
	var port := _port()
	var server_result := _result_path("server_reject")
	var bot := _result_path("bot_reject")
	var server := _spawn(["--server", "--port=%d" % port, "--seed=3", "--duration=7", "--result=%s" % server_result, "--log=error"], "server")
	await wait(2.0)
	var client := _spawn(["--bot-client", "--connect=ws://127.0.0.1:%d" % port, "--protocol-override=%d" % (NetProtocol.VERSION + 1),
		"--duration=5", "--result=%s" % bot, "--log=error"], "old client")
	assert_true(await _wait_for_exit(client, 12.0), "the refused client exits")
	assert_true(await _wait_for_exit(server, 12.0))
	var r := _read(bot)
	assert_false(r.is_empty())
	if r.is_empty():
		return
	assert_false(r["connected"], "never joined")
	assert_eq(r["ended_reason"], "version_mismatch")
	assert_eq(_read(server_result).get("rejects", 0), 1)


func test_connecting_to_nothing_fails_cleanly() -> void:
	var bot := _result_path("bot_nothing")
	var client := _spawn(["--bot-client", "--connect=ws://127.0.0.1:%d" % (_port() + 1), "--duration=6", "--result=%s" % bot, "--log=error"], "lonely client")
	assert_true(await _wait_for_exit(client, 15.0), "the client gives up and exits")
	var r := _read(bot)
	assert_false(r.is_empty())
	if not r.is_empty():
		assert_false(r["connected"])
		assert_ne(r["ended_reason"], "")
