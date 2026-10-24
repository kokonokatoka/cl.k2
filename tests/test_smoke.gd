class_name TestSmoke
extends TestCase

## プロジェクト内の全リソース（.gd, .tscn, .tres）のロード可否を網羅検証するスモークテスト。
## 参照切れや構文エラー、未定義シンボルによる破損を防止する。

const SEARCH_DIRS := [
	"res://src",
	"res://scenes",
	"res://content",
	"res://shaders"
]

func test_all_project_resources_load_cleanly() -> void:
	var files: Array[String] = []
	for dir in SEARCH_DIRS:
		_collect_files(dir, files)
	
	assert_true(files.size() > 0, "found resources to test")
	
	var checked_count := 0
	for path in files:
		var res: Resource = load(path)
		assert_true(res != null, "resource loads successfully: %s" % path)
		if res != null:
			checked_count += 1
	
	assert_eq(checked_count, files.size(), "all collected resources loaded without failure")


func _collect_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != ".." and not name.begins_with("."):
			var full_path := "%s/%s" % [dir_path, name]
			if dir.current_is_dir():
				_collect_files(full_path, out)
			else:
				var ext := name.get_extension().to_lower()
				if ext in ["gd", "tscn", "tres", "gdshader"]:
					out.append(full_path)
		name = dir.get_next()
	dir.list_dir_end()
