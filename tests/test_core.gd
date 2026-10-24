extends TestCase
## コア: 決定論的乱数、ハッシュ、起動オプション、設定、セーブ。


func test_det_rng_is_reproducible() -> void:
	var a := DetRng.new(12345)
	var b := DetRng.new(12345)
	for i in 100:
		assert_eq(a.next_u32(), b.next_u32())


func test_det_rng_known_vector() -> void:
	# mulberry32(seed=1) の先頭3つ。JavaScript の参照実装で求めた値（エンジン非依存の確認）
	var rng := DetRng.new(1)
	assert_eq(rng.next_u32(), 2693262067)
	assert_eq(rng.next_u32(), 11749833)
	assert_eq(rng.next_u32(), 2265367787)


func test_det_rng_ranges() -> void:
	var rng := DetRng.new(99)
	var seen_low := false
	var seen_high := false
	for i in 500:
		var f := rng.next_float()
		assert_true(f >= 0.0 and f < 1.0)
		var n := rng.range_int(3, 6)
		assert_true(n >= 3 and n <= 6)
		seen_low = seen_low or n == 3
		seen_high = seen_high or n == 6
	assert_true(seen_low and seen_high, "both ends reachable")


func test_det_rng_seeds_diverge() -> void:
	assert_ne(DetRng.new(1).next_u32(), DetRng.new(2).next_u32())


func test_det_rng_mix_is_deterministic_and_spread() -> void:
	assert_eq(DetRng.mix(5, 9), 4209343293, "matches the JavaScript reference")
	assert_eq(DetRng.mix(9, 5), 2130504130)
	assert_ne(DetRng.mix(5, 9), DetRng.mix(9, 5))
	assert_ne(DetRng.mix(5, 9), DetRng.mix(5, 10))


func test_fnv1a_known_vectors() -> void:
	assert_eq(Hashing.fnv1a_string(""), 0x811C9DC5)
	assert_eq(Hashing.fnv1a_string("a"), 0xE40C292C)
	assert_eq(Hashing.fnv1a_string("foobar"), 0xBF9CF968)


func test_settings_coerce_and_clamp() -> void:
	Settings.set_value("audio/master", 5.0)
	assert_near(Settings.get_float("audio/master"), 1.0, 1e-6, "clamped to max")
	Settings.set_value("audio/master", -1.0)
	assert_near(Settings.get_float("audio/master"), 0.0, 1e-6, "clamped to min")
	Settings.set_value("audio/master", "loud")
	assert_near(Settings.get_float("audio/master"), 0.8, 1e-6, "wrong type falls back to default")
	Settings.set_value("game/language", "klingon")
	assert_eq(Settings.get_string("game/language"), "auto", "unknown option falls back")
	Log.level = Log.Level.SILENT
	Settings.set_value("no/such_key", 1)
	Log.level = Log.Level.WARN


func test_settings_roundtrip_through_file() -> void:
	Settings.set_value("audio/sfx", 0.25)
	Settings.set_value("player/name", "Tester")
	Settings.set_binding(&"jump", [{"k": KEY_J}])
	Settings.save()
	Settings.load_settings()
	assert_near(Settings.get_float("audio/sfx"), 0.25)
	assert_eq(Settings.get_string("player/name"), "Tester")
	assert_eq(Settings.get_bindings()["jump"][0]["k"], KEY_J)
	Settings.reset_to_defaults()
	Settings.save()


func test_input_actions_installed_with_events() -> void:
	InputActions.install({})
	for action: StringName in InputActions.DEFAULTS:
		assert_true(InputMap.has_action(action), "missing action %s" % action)
		assert_false(InputMap.action_get_events(action).is_empty(), "no events for %s" % action)


func test_rebinding_replaces_keyboard_but_keeps_gamepad() -> void:
	InputActions.install({"jump": [{"k": KEY_J}]})
	var events := InputMap.action_get_events(&"jump")
	var has_j := false
	var has_space := false
	var has_pad := false
	for e in events:
		if e is InputEventKey:
			has_j = has_j or e.physical_keycode == KEY_J
			has_space = has_space or e.physical_keycode == KEY_SPACE
		if e is InputEventJoypadButton:
			has_pad = true
	assert_true(has_j)
	assert_false(has_space, "old key removed")
	assert_true(has_pad, "gamepad binding kept")
	InputActions.install({})


func test_binding_describe_and_capture() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	assert_eq(InputActions.binding_from_event(key), {"k": KEY_F})
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	assert_eq(InputActions.binding_from_event(mouse), {"m": MOUSE_BUTTON_LEFT})
	key.pressed = false
	assert_true(InputActions.binding_from_event(key).is_empty(), "release is ignored")
	assert_ne(InputActions.describe({"k": KEY_F}), "")


func test_save_defaults_and_unlock() -> void:
	Save.use_path("user://test_profile.json")
	assert_false(Save.is_unlocked(&"arms_rail"))
	assert_true(Save.unlock_part(&"arms_rail"))
	assert_false(Save.unlock_part(&"arms_rail"), "second unlock is not new")
	Save.add_stat("kills", 3)
	Save.record_best("best_score", 120)
	Save.record_best("best_score", 80)
	Save.flush()
	Save.load_profile()
	assert_true(Save.is_unlocked(&"arms_rail"), "persisted")
	assert_near(Save.get_stat("kills"), 3.0)
	assert_near(Save.get_stat("best_score"), 120.0)
	assert_eq(Save.unlocked_parts().size(), 1)


func test_save_ignores_unknown_stat_keys() -> void:
	Save.use_path("user://test_profile.json")
	Save.add_stat("cheats", 99)
	assert_near(Save.get_stat("cheats"), 0.0)


func test_save_last_loadout_roundtrip() -> void:
	Save.use_path("user://test_profile.json")
	var loadout := Loadout.new()
	loadout.equip(Content.part(&"legs_spring"))
	loadout.equip(Content.part(&"core_glass"))
	Save.set_last_loadout(loadout)
	Save.flush()
	Save.load_profile()
	assert_eq(Save.last_loadout().to_ids(), loadout.to_ids())


func test_save_recovers_from_corrupt_file() -> void:
	Save.use_path("user://test_profile.json")
	var file := FileAccess.open("user://test_profile.json", FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	Log.level = Log.Level.SILENT
	Save.load_profile()
	Log.level = Log.Level.WARN
	assert_eq(Save.player_name(), "")
	assert_near(Save.get_stat("kills"), 0.0)


func test_save_sanitizes_wrong_types_and_migrates_v0() -> void:
	Save.use_path("user://test_profile.json")
	var file := FileAccess.open("user://test_profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"name": "A very long player name that exceeds the limit",
		"unlocked": ["arms_rail", 5, "arms_rail"],
		"stats": {"kills": "many", "deaths": 4},
	}))
	file.close()
	Save.load_profile()
	assert_eq(Save.player_name().length(), 16)
	assert_eq((Save.data["unlocked"] as Array).size(), 1, "dedupe + drop non-strings")
	assert_near(Save.get_stat("kills"), 0.0, 1e-6, "wrong type falls back")
	assert_near(Save.get_stat("deaths"), 4.0)
	assert_eq(int(Save.data["version"]), Save.SAVE_VERSION)


func test_cfg_parses_env_and_defaults() -> void:
	assert_eq(Cfg.get_int("definitely-not-set", 42), 42)
	assert_eq(Cfg.get_string("definitely-not-set", "x"), "x")
	assert_false(Cfg.get_bool("definitely-not-set"))
	assert_true(Cfg.get_bool("definitely-not-set", true))
