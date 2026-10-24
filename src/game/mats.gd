class_name Mats
extends RefCounted
## コードで作るマテリアルの共有キャッシュ。同じ見た目のマテリアルを1つにまとめて描画コストを抑える。

static var _cache: Dictionary = {}


## 通常のマテリアル
static func solid(color: Color, metallic: float = 0.3, roughness: float = 0.55) -> StandardMaterial3D:
	var key := "solid|%s|%.2f|%.2f" % [color.to_html(true), metallic, roughness]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		_cache[key] = m
	return _cache[key]


## 光るマテリアル（照明の影響を受けない）
static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "glow|%s|%.2f" % [color.to_html(true), energy]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_cache[key] = m
	return _cache[key]


## 完全に光だけで描く（弾・ビームなど）
static func unshaded(color: Color, additive: bool = false) -> StandardMaterial3D:
	var key := "unshaded|%s|%s" % [color.to_html(true), additive]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		if additive:
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		elif color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cache[key] = m
	return _cache[key]


## 半透明のガラス
static func glass(color: Color) -> StandardMaterial3D:
	var key := "glass|%s" % color.to_html(true)
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.2
		m.roughness = 0.1
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = 0.8
		_cache[key] = m
	return _cache[key]


static func mesh(shape: Mesh, material: Material, parent: Node3D, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cylinder(radius: float, height: float, radial_segments: int = 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = radial_segments
	m.rings = 1
	return m


static func sphere(radius: float, segments: int = 16) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(4, segments / 2)
	return m
