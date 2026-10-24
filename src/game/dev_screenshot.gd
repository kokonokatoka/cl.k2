class_name DevScreenshot
extends Node
## 開発用: 指定フレーム後に画面を PNG で保存して終了する（`--screenshot=パス [--screenshot-frames=N]`）。
## シーン切り替えで消えないよう root に置く。

var path: String = ""
var frames: int = 120
var quit_after: bool = true

var _count: int = 0


func _process(_delta: float) -> void:
	_count += 1
	if _count < frames:
		return
	set_process(false)
	var image := get_viewport().get_texture().get_image()
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var error := image.save_png(path)
	Log.info("dev", "screenshot saved to %s (%dx%d, error %d)" % [path, image.get_width(), image.get_height(), error])
	if quit_after:
		get_tree().quit()
