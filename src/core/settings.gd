extends Node
## ユーザー設定（autoload: Settings）。`user://settings.cfg` に保存し、変更を即座に反映する。
## キーは "audio/master" のような "セクション/名前" 形式。型と範囲は SCHEMA で検証する（壊れた設定ファイル対策）。

const SCHEMA := {
	"audio/master": {"default": 0.8, "min": 0.0, "max": 1.0},
	"audio/music": {"default": 0.6, "min": 0.0, "max": 1.0},
	"audio/sfx": {"default": 0.9, "min": 0.0, "max": 1.0},
	"audio/ui": {"default": 0.8, "min": 0.0, "max": 1.0},
	"video/fullscreen": {"default": false},
	"video/vsync": {"default": true},
	"video/msaa": {"default": 1, "min": 0, "max": 3},
	"video/shadows": {"default": true},
	"video/ui_scale": {"default": 1.0, "min": 0.75, "max": 1.5},
	"video/show_fps": {"default": false},
	"game/language": {"default": "auto", "options": ["auto", "en", "ja"]},
	"game/screen_shake": {"default": 1.0, "min": 0.0, "max": 1.0},
	"game/camera_lookahead": {"default": 1.0, "min": 0.0, "max": 1.0},
	"game/damage_numbers": {"default": true},
	"player/name": {"default": ""},
	"player/color": {"default": "e8913a"},
	"net/server": {"default": "ws://127.0.0.1:8910"},
}

const SAVE_DELAY := 0.4

var path: String = "user://settings.cfg"

var _values: Dictionary = {}
## アクション名 -> 割り当て（キーボード/マウス分）。InputActions 参照
var _bindings: Dictionary = {}
var _save_timer: Timer


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	load_settings()
	apply_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _save_timer != null and not _save_timer.is_stopped():
		save()


## テストなどで保存先を変える。読み直す
func use_path(new_path: String) -> void:
	path = new_path
	load_settings()


func get_value(key: String) -> Variant:
	return _values.get(key, SCHEMA[key]["default"])


func get_float(key: String) -> float:
	return float(get_value(key))


func get_int(key: String) -> int:
	return int(get_value(key))


func get_bool(key: String) -> bool:
	return bool(get_value(key))


func get_string(key: String) -> String:
	return String(get_value(key))


func set_value(key: String, value: Variant) -> void:
	if not SCHEMA.has(key):
		Log.warn("settings", "unknown key: %s" % key)
		return
	var coerced: Variant = _coerce(key, value)
	if _values.get(key, SCHEMA[key]["default"]) == coerced:
		return
	_values[key] = coerced
	_apply(key)
	Events.settings_changed.emit(key)
	_schedule_save()


func reset_to_defaults() -> void:
	_values.clear()
	_bindings.clear()
	apply_all()
	for key in SCHEMA:
		Events.settings_changed.emit(key)
	_schedule_save()


func get_bindings() -> Dictionary:
	return _bindings


## action のキーボード/マウス割り当てを置き換える。空配列は「割り当てなし」
func set_binding(action: StringName, bindings: Array) -> void:
	_bindings[String(action)] = bindings
	InputActions.install(_bindings)
	_schedule_save()


func reset_binding(action: StringName) -> void:
	_bindings.erase(String(action))
	InputActions.install(_bindings)
	_schedule_save()


func reset_all_bindings() -> void:
	_bindings.clear()
	InputActions.install(_bindings)
	_schedule_save()


func load_settings() -> void:
	_values.clear()
	_bindings.clear()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		for key in SCHEMA:
			var section: String = key.get_slice("/", 0)
			var name: String = key.get_slice("/", 1)
			if config.has_section_key(section, name):
				_values[key] = _coerce(key, config.get_value(section, name))
		if config.has_section("input"):
			for action in config.get_section_keys("input"):
				var value: Variant = config.get_value("input", action)
				if InputActions.DEFAULTS.has(StringName(action)) and value is Array:
					_bindings[action] = value


func save() -> void:
	var config := ConfigFile.new()
	for key in _values:
		config.set_value(key.get_slice("/", 0), key.get_slice("/", 1), _values[key])
	for action in _bindings:
		config.set_value("input", action, _bindings[action])
	var err := config.save(path)
	if err != OK:
		Log.warn("settings", "failed to save %s (error %d)" % [path, err])


func apply_all() -> void:
	AudioBuses.ensure()
	InputActions.install(_bindings)
	for key in SCHEMA:
		_apply(key)


func _apply(key: String) -> void:
	match key:
		"audio/master":
			AudioBuses.set_linear(AudioBuses.MASTER, get_float(key))
		"audio/music":
			AudioBuses.set_linear(AudioBuses.MUSIC, get_float(key))
		"audio/sfx":
			AudioBuses.set_linear(AudioBuses.SFX, get_float(key))
		"audio/ui":
			AudioBuses.set_linear(AudioBuses.UI, get_float(key))
		"video/fullscreen":
			if not Cfg.is_headless():
				var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if get_bool(key) else DisplayServer.WINDOW_MODE_WINDOWED
				if DisplayServer.window_get_mode() != mode:
					DisplayServer.window_set_mode(mode)
		"video/vsync":
			if not Cfg.is_headless():
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_ENABLED if get_bool(key) else DisplayServer.VSYNC_DISABLED)
		"video/msaa":
			get_viewport().msaa_3d = get_int(key) as Viewport.MSAA
		"video/ui_scale":
			get_window().content_scale_factor = get_float(key)
		"game/language":
			I18n.set_language(get_string(key))


func _schedule_save() -> void:
	if _save_timer != null and is_inside_tree():
		_save_timer.start()


func _coerce(key: String, value: Variant) -> Variant:
	var spec: Dictionary = SCHEMA[key]
	var default: Variant = spec["default"]
	match typeof(default):
		TYPE_BOOL:
			return bool(value) if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] else default
		TYPE_INT:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return default
			return clampi(int(value), int(spec["min"]), int(spec["max"]))
		TYPE_FLOAT:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(value)):
				return default
			return clampf(float(value), float(spec["min"]), float(spec["max"]))
		TYPE_STRING:
			if typeof(value) != TYPE_STRING:
				return default
			if spec.has("options") and not (spec["options"] as Array).has(value):
				return default
			return String(value).substr(0, 128)
	return default
