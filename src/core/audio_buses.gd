class_name AudioBuses
extends RefCounted
## オーディオバスの用意と音量設定。default_bus_layout.tres を手で持たず、コードで作る。

const MASTER := &"Master"
const MUSIC := &"Music"
const SFX := &"SFX"
const UI := &"UI"


## Music / SFX / UI バスがなければ Master の下に作る
static func ensure() -> void:
	for bus_name in [MUSIC, SFX, UI]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, MASTER)


## 0.0〜1.0 の線形音量を設定する（0 でミュート）
static func set_linear(bus_name: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
