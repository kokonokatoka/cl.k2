extends Node
## 軽量ロガー（autoload: Log）。カテゴリ付きで標準出力に出し、直近の行はメモリにも残す（デバッグオーバーレイ用）。
## 使い方: Log.info("net", "connected") / Log.warn(...) / Log.error(...)

enum Level { DEBUG, INFO, WARN, ERROR, SILENT }

signal line_added(line: String)

const HISTORY_SIZE := 200
const LEVEL_NAMES: PackedStringArray = ["DEBUG", "INFO", "WARN", "ERROR"]

var level: Level = Level.INFO
var history: PackedStringArray = PackedStringArray()

var _start_msec: int = Time.get_ticks_msec()


func _ready() -> void:
	level = Level.DEBUG if OS.is_debug_build() else Level.INFO


func debug(category: String, message: String) -> void:
	_log(Level.DEBUG, category, message)


func info(category: String, message: String) -> void:
	_log(Level.INFO, category, message)


func warn(category: String, message: String) -> void:
	_log(Level.WARN, category, message)


func error(category: String, message: String) -> void:
	_log(Level.ERROR, category, message)


## 文字列（"debug" / "info" / "warn" / "error" / "silent"）からレベルを設定する
func set_level_by_name(level_name: String) -> void:
	var index := ["debug", "info", "warn", "error", "silent"].find(level_name.to_lower())
	if index >= 0:
		level = index as Level


func _log(lv: Level, category: String, message: String) -> void:
	if lv < level:
		return
	var seconds := float(Time.get_ticks_msec() - _start_msec) / 1000.0
	var line := "%8.2f %-5s %-8s %s" % [seconds, LEVEL_NAMES[lv], category, message]
	history.append(line)
	if history.size() > HISTORY_SIZE:
		history.remove_at(0)
	match lv:
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
		_:
			print(line)
	line_added.emit(line)
