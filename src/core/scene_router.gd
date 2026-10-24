extends CanvasLayer
## シーン遷移（autoload: Router）。暗転しながらシーンを切り替える。ヘッドレスでは即座に切り替える。

const FADE_OUT := 0.16
const FADE_IN := 0.24

var _fade: ColorRect
var _busy: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.025, 0.04, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	add_child(_fade)


## path のシーンへ移る。遷移中の呼び出しは無視する
func go(path: String) -> void:
	if _busy:
		return
	_busy = true
	var animate := not Cfg.is_headless()
	if animate:
		_fade.mouse_filter = Control.MOUSE_FILTER_STOP
		var out := create_tween()
		out.tween_property(_fade, "modulate:a", 1.0, FADE_OUT)
		await out.finished
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		Log.error("router", "cannot change scene to %s (error %d)" % [path, error])
	await get_tree().process_frame
	await get_tree().process_frame
	if animate:
		var back := create_tween()
		back.tween_property(_fade, "modulate:a", 0.0, FADE_IN)
		await back.finished
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
