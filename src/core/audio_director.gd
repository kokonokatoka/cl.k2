extends Node
## 効果音と音楽の再生（autoload: Audio）。音は SfxLibrary のレシピから初回再生時に合成してキャッシュする。
## ヘッドレス（専用サーバー・テスト）では何もしない。
##
##   Audio.play_ui(&"ui_click")
##   Audio.play_at(&"explode_small", position)          # ワールド上の位置から
##   Audio.play_global(&"shot_blaster")                 # 自分の発砲など、位置に依らない音

const WORLD_VOICES := 20
const UI_VOICES := 6

var _enabled: bool = false
var _streams: Dictionary = {}
var _world_players: Array[AudioStreamPlayer3D] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _music_building: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_enabled = not Cfg.is_headless()
	if not _enabled:
		return
	_rng.randomize()
	for i in WORLD_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.bus = AudioBuses.SFX
		player.unit_size = 14.0
		player.max_distance = 70.0
		player.attenuation_filter_cutoff_hz = 20500.0
		add_child(player)
		_world_players.append(player)
	for i in UI_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = AudioBuses.UI
		add_child(player)
		_ui_players.append(player)
	for i in 8:
		var player := AudioStreamPlayer.new()
		player.bus = AudioBuses.SFX
		add_child(player)
		_sfx_players.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = AudioBuses.MUSIC
	add_child(_music_player)


## 全部の効果音を 1 フレームに 1 つずつ先に合成しておく（最初に鳴らすときのカクつきを避ける）
func warm_up() -> void:
	if not _enabled:
		return
	for sound in SfxLibrary.names():
		_stream(sound)
		await get_tree().process_frame


func play_ui(sound: StringName, volume_db: float = 0.0) -> void:
	if not _enabled:
		return
	_play(_ui_players, sound, volume_db, 1.0)


## 位置に依らない効果音（SFX バス）
func play_global(sound: StringName, volume_db: float = 0.0, pitch_jitter: float = 0.05) -> void:
	if not _enabled:
		return
	_play(_sfx_players, sound, volume_db, 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))


## ワールド上の位置から鳴る効果音（距離で小さくなる）
func play_at(sound: StringName, position: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if not _enabled:
		return
	var player := _free_player_3d()
	if player == null:
		return
	player.stream = _stream(sound)
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func start_music() -> void:
	if not _enabled or _music_player.playing:
		return
	if _music_stream == null:
		if not _music_building:
			_music_building = true
			_music_stream = await MusicSynth.build(get_tree())
			_music_building = false
		else:
			return
	_music_player.stream = _music_stream
	_music_player.volume_db = -6.0
	_music_player.play()


func stop_music() -> void:
	if _enabled and _music_player.playing:
		_music_player.stop()


func _unhandled_input(event: InputEvent) -> void:
	# WebブラウザのAutoplay規制対策: ユーザーの初操作時に音楽を再開
	if _enabled and _music_stream != null and _music_player != null and not _music_player.playing:
		if event is InputEventMouseButton or event is InputEventKey:
			_music_player.play()


func _play(pool: Array[AudioStreamPlayer], sound: StringName, volume_db: float, pitch: float) -> void:
	for player in pool:
		if not player.playing:
			player.stream = _stream(sound)
			player.volume_db = volume_db
			player.pitch_scale = pitch
			player.play()
			return
	# 全部使用中: 先頭を奪う
	pool[0].stream = _stream(sound)
	pool[0].volume_db = volume_db
	pool[0].pitch_scale = pitch
	pool[0].play()


func _free_player_3d() -> AudioStreamPlayer3D:
	for player in _world_players:
		if not player.playing:
			return player
	return null


func _stream(sound: StringName) -> AudioStreamWAV:
	if not _streams.has(sound):
		_streams[sound] = SfxSynth.render(SfxLibrary.recipe(sound))
	return _streams[sound]
