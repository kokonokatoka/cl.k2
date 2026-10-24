class_name SimMath
extends RefCounted
## シミュレーション用の算術。座標系は Y 上、前方は yaw=0 のとき -Z。


## yaw（ラジアン）が向いている水平方向の単位ベクトル
static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## from→to の線分と、縦向きの円柱（底面中心 cx,cz・半径 r・高さ y0〜y1）の最初の交点の t（0〜1）。
## 当たらなければ -1。線分が最初から円柱の中なら 0。
static func segment_vs_cylinder(from: Vector3, to: Vector3, cx: float, cz: float, r: float, y0: float, y1: float) -> float:
	var dx := to.x - from.x
	var dz := to.z - from.z
	var fx := from.x - cx
	var fz := from.z - cz
	var a := dx * dx + dz * dz
	var c := fx * fx + fz * fz - r * r
	var t_enter := 0.0
	var t_exit := 1.0
	if a < 1e-12:
		if c > 0.0:
			return -1.0
	else:
		var b := 2.0 * (fx * dx + fz * dz)
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return -1.0
		var root := sqrt(disc)
		var t1 := (-b - root) / (2.0 * a)
		var t2 := (-b + root) / (2.0 * a)
		if t2 < 0.0 or t1 > 1.0:
			return -1.0
		t_enter = maxf(t1, 0.0)
		t_exit = minf(t2, 1.0)
	# 高さの範囲と重なる t の区間
	var dy := to.y - from.y
	if absf(dy) < 1e-9:
		if from.y < y0 or from.y > y1:
			return -1.0
	else:
		var ta := (y0 - from.y) / dy
		var tb := (y1 - from.y) / dy
		t_enter = maxf(t_enter, minf(ta, tb))
		t_exit = minf(t_exit, maxf(ta, tb))
	if t_enter > t_exit:
		return -1.0
	return t_enter


static func wrap_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)


## 角度 a から b へ、最短回り込みで t だけ近づく
static func lerp_angle_short(a: float, b: float, t: float) -> float:
	return a + wrap_angle(b - a) * t
