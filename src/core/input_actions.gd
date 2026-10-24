class_name InputActions
extends RefCounted
## 入力アクションの定義と、キー割り当て（リバインド）の適用。
## project.godot の [input] ではなくコードで持つ。既定の割り当てとユーザー設定を同じ場所で扱うため。
##
## 割り当ては辞書で表す: {"k": 物理キー} / {"m": マウスボタン} / {"jb": パッドボタン} / {"ja": パッド軸, "v": 向き}

const AXIS_DEADZONE := 0.2

const DEFAULTS := {
	&"move_left": [{"k": KEY_A}, {"k": KEY_LEFT}, {"ja": JOY_AXIS_LEFT_X, "v": -1.0}],
	&"move_right": [{"k": KEY_D}, {"k": KEY_RIGHT}, {"ja": JOY_AXIS_LEFT_X, "v": 1.0}],
	&"move_forward": [{"k": KEY_W}, {"k": KEY_UP}, {"ja": JOY_AXIS_LEFT_Y, "v": -1.0}],
	&"move_back": [{"k": KEY_S}, {"k": KEY_DOWN}, {"ja": JOY_AXIS_LEFT_Y, "v": 1.0}],
	&"aim_left": [{"ja": JOY_AXIS_RIGHT_X, "v": -1.0}],
	&"aim_right": [{"ja": JOY_AXIS_RIGHT_X, "v": 1.0}],
	&"aim_up": [{"ja": JOY_AXIS_RIGHT_Y, "v": -1.0}],
	&"aim_down": [{"ja": JOY_AXIS_RIGHT_Y, "v": 1.0}],
	&"jump": [{"k": KEY_SPACE}, {"jb": JOY_BUTTON_A}],
	&"dash": [{"k": KEY_SHIFT}, {"m": MOUSE_BUTTON_RIGHT}, {"jb": JOY_BUTTON_LEFT_SHOULDER}],
	&"fire": [{"m": MOUSE_BUTTON_LEFT}, {"ja": JOY_AXIS_TRIGGER_RIGHT, "v": 1.0}, {"jb": JOY_BUTTON_RIGHT_SHOULDER}],
	&"swap_eyes": [{"k": KEY_1}, {"jb": JOY_BUTTON_DPAD_UP}],
	&"swap_legs": [{"k": KEY_2}, {"jb": JOY_BUTTON_DPAD_RIGHT}],
	&"swap_arms": [{"k": KEY_3}, {"jb": JOY_BUTTON_DPAD_DOWN}],
	&"swap_core": [{"k": KEY_4}, {"jb": JOY_BUTTON_DPAD_LEFT}],
	&"scoreboard": [{"k": KEY_TAB}, {"jb": JOY_BUTTON_BACK}],
	&"chat": [{"k": KEY_ENTER}, {"k": KEY_T}],
	&"pause": [{"k": KEY_ESCAPE}, {"jb": JOY_BUTTON_START}],
	&"toggle_debug": [{"k": KEY_F3}],
	&"toggle_console": [{"k": KEY_QUOTELEFT}],
}

## 設定画面でキー割り当てを変えられるアクション
const REMAPPABLE: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right",
	&"jump", &"dash", &"fire",
	&"swap_eyes", &"swap_legs", &"swap_arms", &"swap_core",
	&"scoreboard",
]


## 全アクションを登録し直す。overrides は {"アクション名": [割り当て, ...]}（キーボード/マウス分のみ）
static func install(overrides: Dictionary = {}) -> void:
	for action: StringName in DEFAULTS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, AXIS_DEADZONE)
		for binding: Dictionary in effective_bindings(action, overrides):
			var event := event_from(binding)
			if event != null:
				InputMap.action_add_event(action, event)


## ユーザー設定（キーボード/マウス）＋既定のパッド割り当て
static func effective_bindings(action: StringName, overrides: Dictionary = {}) -> Array:
	var keyboard_mouse: Array = []
	var gamepad: Array = []
	for binding: Dictionary in DEFAULTS[action]:
		if binding.has("jb") or binding.has("ja"):
			gamepad.append(binding)
		else:
			keyboard_mouse.append(binding)
	var result: Array = []
	if overrides.has(String(action)):
		result.append_array(overrides[String(action)])
	else:
		result.append_array(keyboard_mouse)
	result.append_array(gamepad)
	return result


static func default_keyboard_mouse(action: StringName) -> Array:
	var result: Array = []
	for binding: Dictionary in DEFAULTS[action]:
		if not (binding.has("jb") or binding.has("ja")):
			result.append(binding)
	return result


static func event_from(binding: Dictionary) -> InputEvent:
	if binding.has("k"):
		var key := InputEventKey.new()
		key.physical_keycode = int(binding["k"]) as Key
		return key
	if binding.has("m"):
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(binding["m"]) as MouseButton
		return mouse
	if binding.has("jb"):
		var button := InputEventJoypadButton.new()
		button.button_index = int(binding["jb"]) as JoyButton
		return button
	if binding.has("ja"):
		var motion := InputEventJoypadMotion.new()
		motion.axis = int(binding["ja"]) as JoyAxis
		motion.axis_value = float(binding.get("v", 1.0))
		return motion
	return null


## 押されたイベントから割り当てを作る（リバインドの入力待ち用）。対象外のイベントは空の辞書
static func binding_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return {"k": code}
	if event is InputEventMouseButton and event.pressed:
		return {"m": int(event.button_index)}
	return {}


static func describe(binding: Dictionary) -> String:
	if binding.has("k"):
		var code := int(binding["k"])
		var label := ""
		# 物理キーを、いまのキーボード配列でのキー名に変換する（ヘッドレスでは未対応）
		if DisplayServer.get_name() != "headless":
			label = OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code as Key))
		if label.is_empty():
			label = OS.get_keycode_string(code as Key)
		return label
	if binding.has("m"):
		match int(binding["m"]):
			MOUSE_BUTTON_LEFT: return TranslationServer.translate("input.mouse_left")
			MOUSE_BUTTON_RIGHT: return TranslationServer.translate("input.mouse_right")
			MOUSE_BUTTON_MIDDLE: return TranslationServer.translate("input.mouse_middle")
		return "Mouse %d" % int(binding["m"])
	if binding.has("jb"):
		return "Pad %d" % int(binding["jb"])
	if binding.has("ja"):
		return "Axis %d" % int(binding["ja"])
	return "?"
