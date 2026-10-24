class_name InterpolationBuffer
extends RefCounted
## 他のエンティティの位置を、サーバー時刻のサンプル列から滑らかに復元する。
## 少し過去の時刻（描画の遅れ）を指定してもらい、前後2つのサンプルの間を補間する。
## サンプルが足りないときは、最後の速度で短時間だけ外挿して、止まって見えるのを避ける。

const MAX_SAMPLES := 24
## これ以上先は外挿しない[秒]
const MAX_EXTRAPOLATION := 0.25

class Sample:
	extends RefCounted
	var time: float = 0.0
	var entity: RenderFrame.Entity

var _samples: Array[Sample] = []


func is_empty() -> bool:
	return _samples.is_empty()


func last_time() -> float:
	return _samples[_samples.size() - 1].time if not _samples.is_empty() else -INF


func count() -> int:
	return _samples.size()


func push(time: float, entity: RenderFrame.Entity) -> void:
	# 古い・重複したサンプルは捨てる（順序が入れ替わって届いた場合）
	if not _samples.is_empty() and time <= _samples[_samples.size() - 1].time:
		return
	var sample := Sample.new()
	sample.time = time
	sample.entity = entity
	_samples.append(sample)
	if _samples.size() > MAX_SAMPLES:
		_samples.remove_at(0)


## render_time（サーバー時刻）の見た目を返す。サンプルが無ければ null
func sample_at(render_time: float) -> RenderFrame.Entity:
	if _samples.is_empty():
		return null
	var first := _samples[0]
	var last := _samples[_samples.size() - 1]
	if render_time <= first.time:
		return _copy(first.entity)
	if render_time >= last.time:
		return _extrapolate(last, render_time)
	for i in range(_samples.size() - 1, 0, -1):
		var after := _samples[i]
		var before := _samples[i - 1]
		if render_time >= before.time:
			var span := after.time - before.time
			var t := (render_time - before.time) / span if span > 0.0 else 1.0
			return _blend(before.entity, after.entity, t)
	return _copy(first.entity)


func _blend(a: RenderFrame.Entity, b: RenderFrame.Entity, t: float) -> RenderFrame.Entity:
	var e := _copy(a)
	e.pos = a.pos.lerp(b.pos, t)
	e.yaw = lerp_angle(a.yaw, b.yaw, t)
	e.health_fraction = lerpf(a.health_fraction, b.health_fraction, t)
	e.velocity = a.velocity.lerp(b.velocity, t)
	# 離散的な値は新しいほうに寄せる
	if t >= 0.5:
		e.alive = b.alive
		e.flags = b.flags
		e.state = b.state
		e.loadout = b.loadout
	return e


func _extrapolate(sample: Sample, render_time: float) -> RenderFrame.Entity:
	var e := _copy(sample.entity)
	var ahead := minf(render_time - sample.time, MAX_EXTRAPOLATION)
	var velocity := e.velocity
	if velocity == Vector3.ZERO and _samples.size() >= 2:
		var previous := _samples[_samples.size() - 2]
		var span := sample.time - previous.time
		if span > 0.0:
			velocity = (sample.entity.pos - previous.entity.pos) / span
	e.pos += velocity * ahead
	return e


func _copy(source: RenderFrame.Entity) -> RenderFrame.Entity:
	var e := RenderFrame.Entity.new()
	e.kind = source.kind
	e.id = source.id
	e.pos = source.pos
	e.yaw = source.yaw
	e.velocity = source.velocity
	e.health_fraction = source.health_fraction
	e.alive = source.alive
	e.type_id = source.type_id
	e.state = source.state
	e.flags = source.flags
	e.display_name = source.display_name
	e.is_local = source.is_local
	e.loadout = source.loadout
	e.owned_by_local = source.owned_by_local
	return e
