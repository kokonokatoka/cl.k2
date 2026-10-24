class_name MusicSynth
extends RefCounted
## ゲーム中の環境音楽（暗めのパッドと、遠くで鳴る高音）をコードで合成してループ素材にする。
## 長いので、数フレームに分けて作る（起動時にカクつかせない）。

const RATE: int = 11025
const BAR_SECONDS: float = 3.0
## Am - F - C - G。各和音の構成音[Hz]
const CHORDS: Array = [
	[110.0, 164.8, 220.0, 261.6],
	[87.3, 130.8, 174.6, 220.0],
	[130.8, 196.0, 261.6, 329.6],
	[98.0, 146.8, 196.0, 246.9],
]
const PINGS: Array = [440.0, 523.3, 659.3, 783.99, 880.0]
const SAMPLES_PER_FRAME: int = 24000


## ループできる AudioStreamWAV を返す（await して使う）
static func build(tree: SceneTree) -> AudioStreamWAV:
	var bars := CHORDS.size()
	var count := int(BAR_SECONDS * bars * RATE)
	var mix := PackedFloat32Array()
	mix.resize(count)
	var budget := 0

	# パッド: 和音ごとに、ゆっくり立ち上がってゆっくり消える
	for bar in bars:
		for freq: float in CHORDS[bar]:
			var start := int(bar * BAR_SECONDS * RATE)
			var length := int(BAR_SECONDS * RATE)
			var phase := 0.0
			var detune := 1.0 + 0.003 * float(int(freq) % 3 - 1)
			for i in length:
				phase += freq * detune / RATE
				var u := float(i) / float(length)
				# 小節の端で 0 になる山形のエンベロープ（ループの継ぎ目を消す）
				var envelope := sin(PI * u)
				var sample := sin(TAU * phase) * 0.6 + sin(TAU * phase * 2.0) * 0.18
				var index := (start + i) % count
				mix[index] += sample * envelope * 0.07
			budget += length
			if budget >= SAMPLES_PER_FRAME:
				budget = 0
				await tree.process_frame

	# 風: ローパスを通したノイズをゆっくり波打たせる
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var filtered := 0.0
	for i in count:
		filtered += (rng.randf() * 2.0 - 1.0 - filtered) * 0.025
		var swell := 0.5 + 0.5 * sin(TAU * float(i) / float(count) * 2.0)
		mix[i] += filtered * (0.5 + 0.5 * swell) * 0.35
		if i % SAMPLES_PER_FRAME == 0 and i > 0:
			await tree.process_frame

	# 遠くの高音: 決まった位置に長く尾を引く音
	var ping_rng := RandomNumberGenerator.new()
	ping_rng.seed = 5
	for k in 7:
		var freq: float = PINGS[ping_rng.randi() % PINGS.size()]
		var start := int(float(k) / 7.0 * count) + ping_rng.randi_range(0, 4000)
		var length := int(2.4 * RATE)
		for i in length:
			var u := float(i) / float(length)
			var sample := sin(TAU * freq * float(i) / RATE) * exp(-4.0 * u) * minf(1.0, float(i) / 200.0)
			mix[(start + i) % count] += sample * 0.045
		await tree.process_frame

	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream
