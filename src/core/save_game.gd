extends Node
## プレイヤーのプロフィールとソロの進行状況（autoload: Save）。`user://profile.json` にバージョン付きで保存する。
## 形式を変えるときは SAVE_VERSION を上げて _migrate() に変換処理を足す（古いセーブを壊さない）。

const SAVE_VERSION := 1
const STAT_KEYS: PackedStringArray = ["kills", "deaths", "enemies", "matches", "playtime", "best_score"]

## 変更からこの秒数まとめて待ってから書き出す（撃破のたびにディスクへ書かない）
const SAVE_DELAY := 1.0

var path: String = "user://profile.json"
## 現在のプロフィール（直接触らず、下のメソッドを使う）
var data: Dictionary = {}

var _dirty: bool = false
var _save_timer: Timer


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(flush)
	add_child(_save_timer)
	load_profile()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func use_path(new_path: String) -> void:
	flush()
	path = new_path
	load_profile()


## 溜まっている変更があれば今すぐ書き出す。セッション終了時・終了時に呼ぶ
func flush() -> void:
	if _dirty:
		_dirty = false
		save_profile()


func load_profile() -> void:
	_dirty = false
	data = _default_profile()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		Log.warn("save", "profile is corrupt, starting fresh: %s" % path)
		_backup_corrupt_file()
		return
	data = _sanitize(_migrate(json.data))


func save_profile() -> bool:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		Log.warn("save", "cannot write %s (error %d)" % [tmp_path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	# 書き込み途中で落ちても元のセーブが壊れないよう、一時ファイルから置き換える
	if DirAccess.rename_absolute(tmp_path, path) != OK:
		var direct := FileAccess.open(path, FileAccess.WRITE)
		if direct == null:
			return false
		direct.store_string(JSON.stringify(data, "\t"))
		direct.close()
		DirAccess.remove_absolute(tmp_path)
	return true


func player_name() -> String:
	return String(data["name"])


func set_player_name(value: String) -> void:
	data["name"] = value.strip_edges().substr(0, 16)
	_changed()


func is_unlocked(part_id: StringName) -> bool:
	return (data["unlocked"] as Array).has(String(part_id))


## 初めて手に入れたパーツなら true
func unlock_part(part_id: StringName) -> bool:
	if is_unlocked(part_id):
		return false
	(data["unlocked"] as Array).append(String(part_id))
	_changed()
	return true


func unlocked_parts() -> Array[RobotPart]:
	var result: Array[RobotPart] = []
	for id in data["unlocked"]:
		var part := Content.part(StringName(id))
		if part != null:
			result.append(part)
	return result


func add_stat(key: String, amount: float = 1.0) -> void:
	if not STAT_KEYS.has(key):
		return
	data["stats"][key] = float(data["stats"].get(key, 0.0)) + amount
	_changed()


func record_best(key: String, value: float) -> void:
	if value > float(data["stats"].get(key, 0.0)):
		data["stats"][key] = value
		_changed()


func get_stat(key: String) -> float:
	return float(data["stats"].get(key, 0.0))


func set_last_loadout(loadout: Loadout) -> void:
	data["last_loadout"] = loadout.to_ids()
	_changed()


func last_loadout() -> Loadout:
	var ids := {}
	for slot in data["last_loadout"]:
		ids[int(slot)] = data["last_loadout"][slot]
	return Loadout.from_ids(ids)


func _changed() -> void:
	_dirty = true
	if _save_timer != null and _save_timer.is_inside_tree():
		_save_timer.start()
	Events.profile_changed.emit()


func _default_profile() -> Dictionary:
	var stats := {}
	for key in STAT_KEYS:
		stats[key] = 0.0
	return {
		"version": SAVE_VERSION,
		"name": "",
		"unlocked": [],
		"stats": stats,
		"last_loadout": {},
	}


## 古い形式を現行へ変換する。バージョンごとに段階的に上げる
func _migrate(raw: Dictionary) -> Dictionary:
	var version := int(raw.get("version", 0))
	if version < 1:
		# v0（バージョン欄なし）→ v1: 欄の追加のみ。_sanitize が不足分を埋める
		raw["version"] = 1
	if version > SAVE_VERSION:
		Log.warn("save", "profile is from a newer version (%d > %d); keeping known fields" % [version, SAVE_VERSION])
	return raw


## 不足や型違いを既定値で埋める
func _sanitize(raw: Dictionary) -> Dictionary:
	var result := _default_profile()
	if typeof(raw.get("name")) == TYPE_STRING:
		result["name"] = String(raw["name"]).substr(0, 16)
	if typeof(raw.get("unlocked")) == TYPE_ARRAY:
		for id in raw["unlocked"]:
			if typeof(id) == TYPE_STRING and not (result["unlocked"] as Array).has(id):
				(result["unlocked"] as Array).append(id)
	if typeof(raw.get("stats")) == TYPE_DICTIONARY:
		for key in STAT_KEYS:
			var value: Variant = raw["stats"].get(key)
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				result["stats"][key] = float(value)
	if typeof(raw.get("last_loadout")) == TYPE_DICTIONARY:
		for slot in raw["last_loadout"]:
			if str(slot).is_valid_int() and typeof(raw["last_loadout"][slot]) == TYPE_STRING:
				result["last_loadout"][str(slot)] = raw["last_loadout"][slot]
	return result


func _backup_corrupt_file() -> void:
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".corrupt")
