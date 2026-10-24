class_name ArenaGenerator
extends RefCounted
## シードからアリーナを作る。点対称に遮蔽物を置くので、どの位置から始めても有利不利が出にくい。
## 同じシード・同じルールなら、サーバーとクライアントで必ず同じ形になる（DetRng を使うため）。

const WALL_THICKNESS: float = 1.5
const WALL_HEIGHT: float = 4.0
## 遮蔽物どうし・中央との最低間隔
const COVER_GAP: float = 2.4
const CENTER_CLEARANCE: float = 5.5


static func generate(seed_value: int, rules: GameRules) -> WorldGeometry:
	var half := rules.arena_half_size
	var geo := WorldGeometry.new(half)
	var rng := DetRng.new(seed_value)

	# 外周の壁
	geo.add_box(-half - WALL_THICKNESS, -half - WALL_THICKNESS, half + WALL_THICKNESS, -half, WALL_HEIGHT, WorldGeometry.Kind.WALL)
	geo.add_box(-half - WALL_THICKNESS, half, half + WALL_THICKNESS, half + WALL_THICKNESS, WALL_HEIGHT, WorldGeometry.Kind.WALL)
	geo.add_box(-half - WALL_THICKNESS, -half, -half, half, WALL_HEIGHT, WorldGeometry.Kind.WALL)
	geo.add_box(half, -half, half + WALL_THICKNESS, half, WALL_HEIGHT, WorldGeometry.Kind.WALL)

	# 遮蔽物（半分を置いて、点対称にもう半分を写す）
	var placed: Array[Rect2] = []
	var pairs := rules.cover_count / 2
	var attempts := 0
	while placed.size() < pairs * 2 and attempts < 600:
		attempts += 1
		var width := rng.range_float(1.6, 5.0)
		var depth := rng.range_float(1.6, 5.0)
		if rng.chance(0.3):
			# 細長い壁
			if rng.chance(0.5):
				width = rng.range_float(6.0, 9.0)
				depth = rng.range_float(1.0, 1.6)
			else:
				depth = rng.range_float(6.0, 9.0)
				width = rng.range_float(1.0, 1.6)
		var cx := rng.range_float(-half + 5.0, half - 5.0)
		var cz := rng.range_float(-half + 5.0, half - 5.0)
		var roll := rng.next_float()
		var height := 0.8 if roll < 0.35 else (1.8 if roll < 0.8 else 3.2)
		var kind := WorldGeometry.Kind.LOW if roll < 0.35 else (WorldGeometry.Kind.MID if roll < 0.8 else WorldGeometry.Kind.TALL)

		var rect := Rect2(cx - width * 0.5, cz - depth * 0.5, width, depth)
		var mirrored := Rect2(-cx - width * 0.5, -cz - depth * 0.5, width, depth)
		var keep_out := Rect2(-CENTER_CLEARANCE, -CENTER_CLEARANCE, CENTER_CLEARANCE * 2.0, CENTER_CLEARANCE * 2.0)
		if rect.intersects(keep_out) or mirrored.intersects(keep_out):
			continue
		if rect.grow(COVER_GAP).intersects(mirrored):
			continue
		var blocked := false
		for other in placed:
			if rect.grow(COVER_GAP).intersects(other) or mirrored.grow(COVER_GAP).intersects(other):
				blocked = true
				break
		if blocked:
			continue
		placed.append(rect)
		placed.append(mirrored)
		for r in [rect, mirrored]:
			geo.add_box(r.position.x, r.position.y, r.end.x, r.end.y, height, kind)

	geo.finalize()
	_place_points(geo, rng, rules)
	return geo


static func _place_points(geo: WorldGeometry, rng: DetRng, rules: GameRules) -> void:
	var half := geo.half_size
	# プレイヤーの出現位置: 外側寄りの円周上
	for i in 8:
		var angle := TAU * float(i) / 8.0 + 0.3
		geo.player_spawns.append(_find_free(geo, Vector2.from_angle(angle) * half * 0.7, 1.4))
	# 敵の出現位置: 壁際の円周上
	for i in 12:
		var angle := TAU * float(i) / 12.0
		geo.enemy_spawns.append(_find_free(geo, Vector2.from_angle(angle) * half * 0.86, 1.2))
	# 拾い物の置き場所: 点対称に2つずつ
	var wanted := rules.world_pickups
	var guard := 0
	while geo.pickup_spots.size() < wanted and guard < 300:
		guard += 1
		var radius := rng.range_float(7.0, half * 0.75)
		var angle := rng.range_float(0.0, TAU)
		var p := Vector2.from_angle(angle) * radius
		if not geo.is_free(p.x, p.y, 1.0) or not geo.is_free(-p.x, -p.y, 1.0):
			continue
		geo.pickup_spots.append(Vector3(p.x, 0.0, p.y))
		if geo.pickup_spots.size() < wanted:
			geo.pickup_spots.append(Vector3(-p.x, 0.0, -p.y))


## target 付近で、ボックスと重ならない場所を探す（渦巻き状に外へ）
static func _find_free(geo: WorldGeometry, target: Vector2, radius: float) -> Vector3:
	if geo.is_free(target.x, target.y, radius):
		return Vector3(target.x, 0.0, target.y)
	for ring in range(1, 40):
		for k in 12:
			var candidate := target + Vector2.from_angle(TAU * float(k) / 12.0) * float(ring) * 0.8
			if geo.is_free(candidate.x, candidate.y, radius):
				return Vector3(candidate.x, 0.0, candidate.y)
	return Vector3(target.x, 0.0, target.y)
