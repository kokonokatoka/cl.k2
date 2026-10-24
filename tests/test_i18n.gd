extends TestCase
## 翻訳: コードで使っているキーが翻訳表にあること、表の抜けがないこと。


func test_every_entry_has_all_languages() -> void:
	for key: String in Strings.TABLE:
		var entry: Array = Strings.TABLE[key]
		assert_eq(entry.size(), I18n.LANGUAGES.size(), "language count for %s" % key)
		for text in entry:
			assert_false(String(text).is_empty(), "empty translation for %s" % key)


func test_every_tr_key_used_in_code_exists() -> void:
	var regex := RegEx.new()
	regex.compile("\\btr\\(&?\"([A-Za-z0-9_.]+)\"\\)")
	var missing: PackedStringArray = []
	for path in _script_paths("res://src"):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			# コメント中の例（tr("ui.play") など）は数えない
			if line.strip_edges().begins_with("#"):
				continue
			for match in regex.search_all(line):
				var key := match.get_string(1)
				if not Strings.TABLE.has(key):
					missing.append("%s (%s)" % [key, path.get_file()])
	assert_eq(missing.size(), 0, "keys missing from Strings.TABLE: %s" % ", ".join(missing))


func test_content_has_translated_names_and_descriptions() -> void:
	for part in Content.all_parts():
		assert_true(Strings.TABLE.has("part.%s.name" % part.id), "name for %s" % part.id)
		assert_true(Strings.TABLE.has("part.%s.desc" % part.id), "description for %s" % part.id)
	for enemy in Content.all_enemies():
		assert_true(Strings.TABLE.has("enemy.%s.name" % enemy.id), "name for %s" % enemy.id)


func test_remappable_actions_have_labels() -> void:
	for action in InputActions.REMAPPABLE:
		assert_true(Strings.TABLE.has("action.%s" % action), "label for %s" % action)


func test_slot_keys_exist() -> void:
	for slot in RobotPart.Slot.values():
		assert_true(Strings.TABLE.has("slot.%s" % RobotPart.slot_key(slot)))


func test_switching_language_changes_part_titles() -> void:
	var part := Content.part(&"arms_rail")
	I18n.set_language("en")
	assert_eq(part.get_title(), "Railgun")
	I18n.set_language("ja")
	assert_eq(part.get_title(), "レールガン")
	I18n.set_language("en")


func test_unknown_language_falls_back() -> void:
	I18n.set_language("xx")
	assert_true(I18n.LANGUAGES.has(I18n.current_language()))
	I18n.set_language("en")


func _script_paths(root: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".gd"):
			result.append("%s/%s" % [root, file])
	for sub in dir.get_directories():
		result.append_array(_script_paths("%s/%s" % [root, sub]))
	return result
