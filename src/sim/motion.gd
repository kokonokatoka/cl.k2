class_name Motion
extends RefCounted
## 決定論的な衝突処理。円 vs ボックスのスライド、足元の高さ、弾（線分）vs ボックス。
## 状態を持たない静的関数だけなので、巻き戻して再生しても結果が同じになる。


## 円を delta だけ動かし、乗り越えられない高さのボックスから押し出す。新しい位置を返す（y は触らない）。
## feet_y: 足元の高さ。top が feet_y + step 以下のボックスは「段差」として無視する。
static func move_circle(geo: WorldGeometry, pos: Vector3, delta: Vector2, radius: float, step: float = SimConfig.STEP_HEIGHT) -> Vector3:
	var distance := delta.length()
	var steps := maxi(1, ceili(distance / (radius * 0.8)))
	var piece := delta / float(steps)
	var x := pos.x
	var z := pos.z
	for n in steps:
		x += piece.x
		z += piece.y
		var pushed := _push_out(geo, x, z, radius, pos.y + step)
		x = pushed.x
		z = pushed.y
	# 念のためアリーナの外へ出ないようにする（外周は壁だが、数値誤差の保険）
	var limit := geo.half_size - radius
	x = clampf(x, -limit, limit)
	z = clampf(z, -limit, limit)
	return Vector3(x, pos.y, z)


## 足元（circle の中心付近）を支える高さ。0 = 床。ボックスの天面が feet_y + step 以下ならそこに立てる
static func support_height(geo: WorldGeometry, pos: Vector3, radius: float, step: float = SimConfig.STEP_HEIGHT) -> float:
	var height := 0.0
	var reach := radius * 0.35
	for i in geo.boxes_in_rect(pos.x - reach, pos.z - reach, pos.x + reach, pos.z + reach):
		var o := i * WorldGeometry.STRIDE
		var top := geo.box_data[o + 4]
		if top > pos.y + step or top <= height:
			continue
		var qx := clampf(pos.x, geo.box_data[o], geo.box_data[o + 2])
		var qz := clampf(pos.z, geo.box_data[o + 1], geo.box_data[o + 3])
		if (pos.x - qx) * (pos.x - qx) + (pos.z - qz) * (pos.z - qz) <= reach * reach:
			height = top
	return height


## from→to の線分が最初に壁に当たる t（0〜1）。当たらなければ -1。
## 弾は高さが top より低いときだけ当たる（低い遮蔽物は飛び越える）。
static func segment_hit_geometry(geo: WorldGeometry, from: Vector3, to: Vector3) -> float:
	var best := -1.0
	var dx := to.x - from.x
	var dz := to.z - from.z
	var dy := to.y - from.y
	var ids := geo.boxes_in_rect(minf(from.x, to.x), minf(from.z, to.z), maxf(from.x, to.x), maxf(from.z, to.z))
	for i in ids:
		var o := i * WorldGeometry.STRIDE
		var top := geo.box_data[o + 4]
		if from.y >= top and to.y >= top:
			continue
		var t0 := 0.0
		var t1 := 1.0
		if absf(dx) < 1e-9:
			if from.x < geo.box_data[o] or from.x > geo.box_data[o + 2]:
				continue
		else:
			var ta := (geo.box_data[o] - from.x) / dx
			var tb := (geo.box_data[o + 2] - from.x) / dx
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				continue
		if absf(dz) < 1e-9:
			if from.z < geo.box_data[o + 1] or from.z > geo.box_data[o + 3]:
				continue
		else:
			var tc := (geo.box_data[o + 1] - from.z) / dz
			var td := (geo.box_data[o + 3] - from.z) / dz
			t0 = maxf(t0, minf(tc, td))
			t1 = minf(t1, maxf(tc, td))
			if t0 > t1:
				continue
		# 高さ: 入った時点で天面より上なら、天面まで降りてくる t から当たる
		var y_at_entry := from.y + dy * t0
		if y_at_entry >= top:
			if dy >= 0.0:
				continue
			t0 = maxf(t0, (top - from.y) / dy)
			if t0 > t1:
				continue
		if best < 0.0 or t0 < best:
			best = t0
	return best


## 見通しが通っているか（AI の射線チェック用）
static func has_line_of_sight(geo: WorldGeometry, from: Vector3, to: Vector3) -> bool:
	return segment_hit_geometry(geo, from, to) < 0.0


static func _push_out(geo: WorldGeometry, px: float, pz: float, radius: float, walkable_top: float) -> Vector2:
	var x := px
	var z := pz
	for _iteration in 3:
		var moved := false
		for i in geo.boxes_in_rect(x - radius, z - radius, x + radius, z + radius):
			var o := i * WorldGeometry.STRIDE
			if geo.box_data[o + 4] <= walkable_top:
				continue
			var min_x := geo.box_data[o]
			var min_z := geo.box_data[o + 1]
			var max_x := geo.box_data[o + 2]
			var max_z := geo.box_data[o + 3]
			var dx := x - clampf(x, min_x, max_x)
			var dz := z - clampf(z, min_z, max_z)
			var d2 := dx * dx + dz * dz
			if d2 >= radius * radius:
				continue
			moved = true
			if d2 > 1e-10:
				var d := sqrt(d2)
				x += dx / d * (radius - d)
				z += dz / d * (radius - d)
			else:
				# 中心がボックスの中にある。いちばん浅い面から押し出す
				var to_left := x - min_x
				var to_right := max_x - x
				var to_near := z - min_z
				var to_far := max_z - z
				var shallowest := minf(minf(to_left, to_right), minf(to_near, to_far))
				if shallowest == to_left:
					x = min_x - radius
				elif shallowest == to_right:
					x = max_x + radius
				elif shallowest == to_near:
					z = min_z - radius
				else:
					z = max_z + radius
		if not moved:
			break
	return Vector2(x, z)
