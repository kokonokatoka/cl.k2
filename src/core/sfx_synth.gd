class_name SfxSynth
extends RefCounted
## 効果音をコードで合成する。音声ファイルを同梱せずに済み、リポジトリが軽くなる（調整もレシピの数値を変えるだけ）。
##
## レシピ: {"duration": 秒, "gain": 全体の音量, "layers": [レイヤー, ...]}
## レイヤー: wave（sine/square/saw/tri/noise/fm）, f0→f1（指数スイープ）, vol, attack, decay（減衰の速さ）,
##   start/length（開始位置と長さ[秒]）, lp→lp_end（ローパス。1 でなし、小さいほど暗い）, fm_ratio/fm_index

const RATE: int = 22050


static func render(recipe: Dictionary) -> AudioStreamWAV:
	var duration: float = recipe.get("duration", 0.3)
	var count := maxi(1, int(duration * RATE))
	var mix := PackedFloat32Array()
	mix.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for layer: Dictionary in recipe["layers"]:
		_add_layer(mix, layer, rng)
	var gain: float = recipe.get("gain", 0.8)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		# tanh で頭打ちにする（重ねても割れない）
		bytes.encode_s16(i * 2, int(tanh(mix[i] * gain) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream


static func _add_layer(mix: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var wave: String = layer.get("wave", "sine")
	var start := float(layer.get("start", 0.0))
	var start_index := int(start * RATE)
	var length := float(layer.get("length", float(mix.size()) / RATE - start))
	var count := mini(int(length * RATE), mix.size() - start_index)
	if count <= 0:
		return
	var f0 := float(layer.get("f0", 440.0))
	var f1 := float(layer.get("f1", f0))
	var volume := float(layer.get("vol", 0.5))
	var attack := maxf(0.0005, float(layer.get("attack", 0.003)))
	var decay := float(layer.get("decay", 4.0))
	var lp0 := float(layer.get("lp", 1.0))
	var lp1 := float(layer.get("lp_end", lp0))
	var fm_ratio := float(layer.get("fm_ratio", 2.0))
	var fm_index := float(layer.get("fm_index", 2.0))
	var ratio := f1 / maxf(f0, 1.0)
	var phase := 0.0
	var fm_phase := 0.0
	var filtered := 0.0
	for i in count:
		var u := float(i) / float(count)
		var t := float(i) / RATE
		var f := f0 * pow(ratio, u)
		phase += f / RATE
		var s := 0.0
		match wave:
			"sine":
				s = sin(TAU * phase)
			"square":
				s = 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0
			"saw":
				s = 2.0 * fposmod(phase, 1.0) - 1.0
			"tri":
				s = absf(4.0 * fposmod(phase, 1.0) - 2.0) - 1.0
			"noise":
				s = rng.randf() * 2.0 - 1.0
			"fm":
				fm_phase += f * fm_ratio / RATE
				s = sin(TAU * phase + fm_index * sin(TAU * fm_phase))
		var coefficient := lerpf(lp0, lp1, u)
		if coefficient < 1.0:
			filtered += (s - filtered) * coefficient
			s = filtered
		var envelope := minf(1.0, t / attack) * exp(-decay * u)
		mix[start_index + i] += s * envelope * volume
