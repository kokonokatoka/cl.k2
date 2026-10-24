extends TestCase
## データ層: 性能値の組み立て、パーツ、ロードアウト、コンテンツ定義の整合性。


func test_bare_chassis_is_weak() -> void:
	var stats := Loadout.new().build_stats()
	assert_near(stats.move_speed, 1.5)
	assert_near(stats.vision_range, 0.0, 1e-6, "no eyes = blind")
	assert_false(stats.can_fire(), "no arms = cannot fire")
	assert_false(stats.can_dash(), "no legs = cannot dash")
	assert_near(stats.jump_velocity, 0.0)


func test_parts_write_their_slot() -> void:
	var loadout := Loadout.new()
	loadout.equip(Content.part(&"legs_roller"))
	loadout.equip(Content.part(&"arms_scatter"))
	var stats := loadout.build_stats()
	assert_near(stats.move_speed, 10.0)
	assert_eq(stats.pellets, 6)
	assert_eq(stats.weapon_kind, &"scatter")
	assert_near(stats.vision_range, 0.0, 1e-6, "eyes still empty")


func test_equip_replaces_same_slot() -> void:
	var loadout := Loadout.new()
	loadout.equip(Content.part(&"eye_standard"))
	loadout.equip(Content.part(&"eye_night"))
	assert_eq(loadout.get_part(RobotPart.Slot.EYES).id, &"eye_night")
	assert_eq(loadout.parts().size(), 1)


func test_modifiers_apply_add_before_mult() -> void:
	var stats := RobotStats.new()
	stats.move_speed = 10.0
	stats.apply_modifiers([
		StatModifier.mult(&"move_speed", 2.0),
		StatModifier.add(&"move_speed", 5.0),
	])
	# (10 + 5) * 2。並び順に依らず ADD が先
	assert_near(stats.move_speed, 30.0)


func test_unknown_modifier_is_ignored() -> void:
	var stats := RobotStats.new()
	var before := stats.signature()
	Log.level = Log.Level.SILENT
	stats.apply_modifiers([StatModifier.add(&"not_a_stat", 1.0)])
	Log.level = Log.Level.WARN
	assert_eq(stats.signature(), before)


func test_part_modifiers_flow_into_loadout_stats() -> void:
	var loadout := Loadout.new()
	loadout.equip(Content.part(&"arms_blaster"))
	var base_damage := loadout.build_stats().weapon_damage
	loadout.equip(Content.part(&"eye_scope"))
	assert_true(loadout.build_stats().weapon_damage > base_damage, "scope eye boosts damage")


func test_loadout_id_roundtrip() -> void:
	var loadout := Loadout.new()
	for part in Content.starter_parts():
		loadout.equip(part)
	var restored := Loadout.from_ids(loadout.to_ids())
	assert_eq(restored.to_ids(), loadout.to_ids())
	assert_eq(restored.build_stats().signature(), loadout.build_stats().signature())


func test_loadout_index_roundtrip() -> void:
	var loadout := Loadout.new()
	loadout.equip(Content.part(&"eye_oracle"))
	loadout.equip(Content.part(&"core_plate"))
	var restored := Loadout.from_indices(loadout.to_indices())
	assert_eq(restored.to_ids(), loadout.to_ids())
	var indices := Loadout.new().to_indices()
	assert_eq(indices.size(), RobotPart.Slot.size())
	assert_eq(indices[0], -1)


func test_loadout_ignores_unknown_and_mismatched_ids() -> void:
	var restored := Loadout.from_ids({RobotPart.Slot.EYES: "no_such_part", RobotPart.Slot.LEGS: "eye_standard"})
	assert_eq(restored.parts().size(), 0, "unknown id and slot mismatch are dropped")


func test_content_ids_unique_and_loaded() -> void:
	var seen := {}
	for part in Content.all_parts():
		assert_false(seen.has(part.id), "duplicate id %s" % part.id)
		seen[part.id] = true
	assert_eq(Content.all_parts().size(), Content.PART_PATHS.size(), "every manifest path loaded")
	assert_eq(Content.all_enemies().size(), Content.ENEMY_PATHS.size())


func test_every_slot_has_a_starter() -> void:
	for slot in RobotPart.Slot.values():
		var starters := Content.starter_parts().filter(func(p: RobotPart) -> bool: return p.get_slot() == slot)
		assert_eq(starters.size(), 1, "slot %s needs exactly one starter" % RobotPart.slot_name(slot))


func test_part_index_roundtrip() -> void:
	for part in Content.all_parts():
		assert_eq(Content.part_at(Content.part_index(part.id)), part)
	assert_eq(Content.part_index(&"nope"), -1)
	assert_null(Content.part_at(999))


func test_content_hash_is_stable() -> void:
	assert_ne(Content.content_hash(), 0)
	assert_eq(Content.content_hash(), Content.content_hash())


func test_part_signature_differs_between_parts() -> void:
	var signatures := {}
	for part in Content.all_parts():
		signatures[part.signature()] = true
	assert_eq(signatures.size(), Content.all_parts().size())


func test_drop_roll_never_returns_starter_and_favours_bias() -> void:
	var rng := DetRng.new(7)
	var rare_plain := 0
	var rare_biased := 0
	for i in 600:
		var plain := Content.roll_part_drop(rng, 0)
		var biased := Content.roll_part_drop(rng, 4)
		assert_false(plain.starter)
		assert_false(biased.starter)
		rare_plain += int(plain.rarity >= RobotPart.Rarity.EPIC)
		rare_biased += int(biased.rarity >= RobotPart.Rarity.EPIC)
	assert_true(rare_biased > rare_plain, "bias should shift drops towards epic+ (%d vs %d)" % [rare_biased, rare_plain])


func test_game_rules_dict_roundtrip() -> void:
	var rules := GameRules.new()
	rules.respawn_delay = 9.5
	rules.pvp = false
	var restored := GameRules.from_dict(rules.to_dict())
	assert_near(restored.respawn_delay, 9.5)
	assert_false(restored.pvp)
	assert_eq(restored.cover_count, rules.cover_count)


func test_enemy_defs_are_sane() -> void:
	for def in Content.all_enemies():
		assert_true(def.max_health > 0.0, "%s health" % def.id)
		assert_true(def.move_speed > 0.0, "%s speed" % def.id)
		assert_true(def.radius > 0.0 and def.height > 0.0, "%s size" % def.id)
