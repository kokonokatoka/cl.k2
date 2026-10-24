class_name SfxLibrary
extends RefCounted
## 効果音のレシピ集。名前 -> SfxSynth のレシピ。音を足すときはここに1つ足して Audio.play_*(&"名前") で鳴らす。

## 連続した音（アルペジオ）のレイヤーを作る
static func _arpeggio(freqs: Array, step: float, wave: String, volume: float, note_length: float = 0.18, decay: float = 5.0) -> Array:
	var layers: Array = []
	for i in freqs.size():
		layers.append({"wave": wave, "f0": freqs[i], "vol": volume, "start": step * i, "length": note_length, "decay": decay, "attack": 0.004})
	return layers


static func names() -> Array[StringName]:
	return [
		&"shot_blaster", &"shot_scatter", &"shot_pulse", &"shot_rail", &"shot_enemy",
		&"hit_enemy", &"hit_player", &"hit_world", &"explode_small", &"explode_big",
		&"jump", &"land", &"dash", &"equip", &"pickup_orb", &"pickup_part", &"pickup_rare",
		&"windup", &"enemy_spawn", &"respawn", &"low_health",
		&"ui_click", &"ui_hover", &"ui_back", &"ui_error", &"ui_confirm",
	]


static func recipe(sound: StringName) -> Dictionary:
	match sound:
		&"shot_blaster":
			return {"duration": 0.16, "gain": 0.9, "layers": [
				{"wave": "square", "f0": 900.0, "f1": 200.0, "vol": 0.35, "decay": 5.0, "lp": 0.5},
				{"wave": "noise", "vol": 0.25, "length": 0.04, "decay": 5.0, "lp": 0.6}]}
		&"shot_scatter":
			return {"duration": 0.32, "gain": 1.0, "layers": [
				{"wave": "noise", "vol": 0.8, "decay": 4.0, "lp": 0.7, "lp_end": 0.05},
				{"wave": "sine", "f0": 160.0, "f1": 45.0, "vol": 0.7, "decay": 3.0}]}
		&"shot_pulse":
			return {"duration": 0.09, "gain": 0.8, "layers": [
				{"wave": "tri", "f0": 1500.0, "f1": 800.0, "vol": 0.5, "decay": 5.0},
				{"wave": "noise", "vol": 0.1, "length": 0.02, "decay": 4.0}]}
		&"shot_rail":
			return {"duration": 0.55, "gain": 1.0, "layers": [
				{"wave": "saw", "f0": 2600.0, "f1": 70.0, "vol": 0.4, "decay": 3.5, "lp": 0.35},
				{"wave": "noise", "vol": 0.6, "length": 0.18, "decay": 4.0, "lp": 0.4, "lp_end": 0.05},
				{"wave": "sine", "f0": 90.0, "f1": 35.0, "vol": 0.8, "decay": 2.5}]}
		&"shot_enemy":
			return {"duration": 0.2, "gain": 0.8, "layers": [
				{"wave": "fm", "f0": 360.0, "f1": 140.0, "vol": 0.4, "decay": 4.0, "fm_ratio": 1.5, "fm_index": 3.0}]}
		&"hit_enemy":
			return {"duration": 0.1, "gain": 0.9, "layers": [
				{"wave": "noise", "vol": 0.5, "length": 0.05, "decay": 4.0, "lp": 0.5},
				{"wave": "sine", "f0": 700.0, "f1": 250.0, "vol": 0.5, "length": 0.08, "decay": 4.0}]}
		&"hit_player":
			return {"duration": 0.28, "gain": 1.0, "layers": [
				{"wave": "noise", "vol": 0.6, "length": 0.14, "decay": 3.0, "lp": 0.3},
				{"wave": "square", "f0": 170.0, "f1": 55.0, "vol": 0.5, "decay": 3.0, "lp": 0.3}]}
		&"hit_world":
			return {"duration": 0.07, "gain": 0.7, "layers": [
				{"wave": "noise", "vol": 0.5, "decay": 5.0, "lp": 0.9, "lp_end": 0.4}]}
		&"explode_small":
			return {"duration": 0.5, "gain": 1.0, "layers": [
				{"wave": "noise", "vol": 0.9, "decay": 3.5, "lp": 0.5, "lp_end": 0.03},
				{"wave": "sine", "f0": 130.0, "f1": 40.0, "vol": 0.8, "decay": 3.0}]}
		&"explode_big":
			return {"duration": 0.9, "gain": 1.1, "layers": [
				{"wave": "noise", "vol": 1.0, "decay": 3.0, "lp": 0.35, "lp_end": 0.02},
				{"wave": "sine", "f0": 90.0, "f1": 28.0, "vol": 1.0, "decay": 2.5},
				{"wave": "saw", "f0": 200.0, "f1": 40.0, "vol": 0.3, "decay": 4.0, "lp": 0.2}]}
		&"jump":
			return {"duration": 0.16, "gain": 0.7, "layers": [
				{"wave": "sine", "f0": 280.0, "f1": 640.0, "vol": 0.5, "decay": 3.0}]}
		&"land":
			return {"duration": 0.14, "gain": 0.8, "layers": [
				{"wave": "noise", "vol": 0.4, "length": 0.07, "decay": 4.0, "lp": 0.3},
				{"wave": "sine", "f0": 120.0, "f1": 60.0, "vol": 0.6, "decay": 4.0}]}
		&"dash":
			return {"duration": 0.3, "gain": 0.8, "layers": [
				{"wave": "noise", "vol": 0.6, "decay": 3.0, "lp": 0.08, "lp_end": 0.5, "attack": 0.04}]}
		&"equip":
			return {"duration": 0.14, "gain": 0.8, "layers": [
				{"wave": "square", "f0": 220.0, "vol": 0.3, "length": 0.04, "decay": 3.0, "lp": 0.4},
				{"wave": "square", "f0": 440.0, "vol": 0.3, "start": 0.05, "length": 0.07, "decay": 3.0, "lp": 0.4}]}
		&"pickup_orb":
			return {"duration": 0.24, "gain": 0.8, "layers": _arpeggio([740.0, 1100.0], 0.07, "sine", 0.5, 0.16)}
		&"pickup_part":
			return {"duration": 0.5, "gain": 0.9, "layers": _arpeggio([523.3, 659.3, 784.0], 0.08, "tri", 0.5, 0.25)}
		&"pickup_rare":
			var layers := _arpeggio([523.3, 659.3, 784.0, 1046.5], 0.09, "tri", 0.45, 0.4, 3.5)
			layers.append({"wave": "sine", "f0": 2093.0, "vol": 0.18, "start": 0.3, "length": 0.5, "decay": 3.0})
			return {"duration": 0.85, "gain": 0.9, "layers": layers}
		&"windup":
			return {"duration": 0.7, "gain": 0.8, "layers": [
				{"wave": "saw", "f0": 180.0, "f1": 900.0, "vol": 0.3, "decay": 0.8, "lp": 0.3, "attack": 0.1}]}
		&"enemy_spawn":
			return {"duration": 0.45, "gain": 0.7, "layers": [
				{"wave": "sine", "f0": 120.0, "f1": 900.0, "vol": 0.4, "decay": 2.0, "attack": 0.05},
				{"wave": "noise", "vol": 0.1, "decay": 3.0, "lp": 0.1}]}
		&"respawn":
			return {"duration": 0.6, "gain": 0.85, "layers": _arpeggio([392.0, 523.3, 659.3, 784.0], 0.09, "sine", 0.45, 0.3, 3.5)}
		&"low_health":
			return {"duration": 0.3, "gain": 0.6, "layers": [
				{"wave": "sine", "f0": 880.0, "vol": 0.4, "length": 0.1, "decay": 2.0},
				{"wave": "sine", "f0": 880.0, "vol": 0.4, "start": 0.16, "length": 0.1, "decay": 2.0}]}
		&"ui_click":
			return {"duration": 0.07, "gain": 0.7, "layers": [
				{"wave": "sine", "f0": 1000.0, "f1": 760.0, "vol": 0.5, "decay": 4.0}]}
		&"ui_hover":
			return {"duration": 0.04, "gain": 0.4, "layers": [
				{"wave": "sine", "f0": 1500.0, "vol": 0.4, "decay": 4.0}]}
		&"ui_back":
			return {"duration": 0.1, "gain": 0.7, "layers": [
				{"wave": "sine", "f0": 620.0, "f1": 380.0, "vol": 0.5, "decay": 3.0}]}
		&"ui_error":
			return {"duration": 0.2, "gain": 0.7, "layers": [
				{"wave": "square", "f0": 160.0, "vol": 0.35, "decay": 3.0, "lp": 0.3}]}
		&"ui_confirm":
			return {"duration": 0.2, "gain": 0.7, "layers": _arpeggio([660.0, 990.0], 0.07, "sine", 0.5, 0.14)}
	return {"duration": 0.05, "layers": []}
