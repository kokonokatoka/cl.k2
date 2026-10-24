extends Node
## 起動オプション（autoload: Cfg）。`godot --path . -- --server --port=8910` のように `--` の後ろで渡す。
## 同名の環境変数 `CK_<KEY>`（例: CK_PORT）でも指定できる（コマンドライン優先）。
## 一覧は docs/ARCHITECTURE.md を参照。

## "key" -> "value"（フラグは ""）
var _args: Dictionary = {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var eq := body.find("=")
		if eq >= 0:
			_args[body.substr(0, eq)] = body.substr(eq + 1)
		else:
			_args[body] = ""


func has(key: String) -> bool:
	return _args.has(key) or OS.has_environment(_env_name(key))


func get_string(key: String, default: String = "") -> String:
	if _args.has(key):
		return _args[key]
	var env_name := _env_name(key)
	return OS.get_environment(env_name) if OS.has_environment(env_name) else default


func get_int(key: String, default: int = 0) -> int:
	var text := get_string(key)
	return text.to_int() if text.is_valid_int() else default


func get_float(key: String, default: float = 0.0) -> float:
	var text := get_string(key)
	return text.to_float() if text.is_valid_float() else default


## `--flag` または `--flag=true|1|yes`
func get_bool(key: String, default: bool = false) -> bool:
	if not has(key):
		return default
	return get_string(key).to_lower() in ["", "1", "true", "yes", "on"]


## 専用サーバーとして起動するか（`--server` またはエクスポート機能タグ `dedicated_server`）
func is_server() -> bool:
	return get_bool("server") or OS.has_feature("dedicated_server")


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _env_name(key: String) -> String:
	return "CK_" + key.to_upper().replace("-", "_")
