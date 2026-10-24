class_name WorldView
extends Node3D
## 3D のワールドの見た目。アリーナを作り、毎フレーム RenderFrame に合わせて各ビューを増減・移動させる。
## 見た目だけを担当し、状態は持たない。シミュレーションのイベントは handle_event で演出・効果音にする。

const COVER_STYLES := {
	WorldGeometry.Kind.WALL: {"base": Color(0.12, 0.13, 0.17), "rim": Color(0.95, 0.5, 0.2)},
	WorldGeometry.Kind.LOW: {"base": Color(0.14, 0.2, 0.2), "rim": Color(0.25, 0.95, 0.75)},
	WorldGeometry.Kind.MID: {"base": Color(0.15, 0.18, 0.26), "rim": Color(0.35, 0.65, 1.0)},
	WorldGeometry.Kind.TALL: {"base": Color(0.2, 0.15, 0.24), "rim": Color(0.95, 0.4, 0.8)},
}
const WEAPON_COLORS := {
	&"blaster": Color(1.0, 0.75, 0.25),
	&"scatter": Color(1.0, 0.5, 0.2),
	&"pulse": Color(0.45, 0.95, 1.0),
	&"rail": Color(0.9, 0.55, 1.0),
}

var effects: EffectsLayer
var local_id: int = 0
## (id: int) -> Color。ロボットの色（セッションが決める）
var color_provider: Callable

var _arena: Node3D
var _robots: Dictionary = {}
var _enemies: Dictionary = {}
var _projectiles: Dictionary = {}
var _pickups: Dictionary = {}
var _cover_materials: Dictionary = {}
var _sun: DirectionalLight3D


func _ready() -> void:
	effects = EffectsLayer.new()
	effects.name = "Effects"
	add_child(effects)
	_setup_environment()
	Events.settings_changed.connect(_on_setting_changed)


## アリーナ（床と遮蔽物）を作る
func build_arena(geometry: WorldGeometry) -> void:
	if _arena != null:
		_arena.queue_free()
	_arena = Node3D.new()
	_arena.name = "Arena"
	add_child(_arena)

	var floor_size := geometry.half_size * 2.0 + 8.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_size, floor_size)
	var floor_material := ShaderMaterial.new()
	floor_material.shader = load("res://shaders/arena_floor.gdshader")
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_material
	_arena.add_child(floor_mesh)

	for i in geometry.box_count:
		var min_corner := geometry.box_min(i)
		var max_corner := geometry.box_max(i)
		var top := geometry.box_top(i)
		var kind: int = geometry.box_kinds[i]
		var box := MeshInstance3D.new()
		box.mesh = Mats.box(Vector3(max_corner.x - min_corner.x, top, max_corner.y - min_corner.y))
		box.material_override = _cover_material(kind, top)
		box.position = Vector3((min_corner.x + max_corner.x) * 0.5, top * 0.5, (min_corner.y + max_corner.y) * 0.5)
		_arena.add_child(box)

	# 出現位置の目印（床の発光リング）
	for point in geometry.player_spawns:
		var pad := Mats.mesh(Mats.cylinder(1.2, 0.02, 24), Mats.unshaded(Color(0.4, 0.8, 1.0, 0.25), true), _arena, point + Vector3(0, 0.02, 0))
		pad.name = "SpawnPad"


## 毎フレーム。frame に合わせてビューを作る・動かす・消す
func update_frame(frame: RenderFrame, delta: float) -> void:
	_sync(frame.players, _robots, delta, _make_robot)
	if color_provider.is_valid():
		for id in _robots:
			(_robots[id] as RobotView).set_tint(color_provider.call(id))
	_sync(frame.enemies, _enemies, delta, _make_enemy)
	_sync(frame.projectiles, _projectiles, delta, _make_projectile)
	_sync(frame.pickups, _pickups, delta, _make_pickup)


func robot_view(id: int) -> RobotView:
	return _robots.get(id)


## 画面に出ているすべてのビューを捨てる（セッション終了時）
func clear_views() -> void:
	for dict in [_robots, _enemies, _projectiles, _pickups]:
		for view: Node in dict.values():
			view.queue_free()
		dict.clear()


## シミュレーションのイベントを演出と効果音にする
func handle_event(event: SimEvent) -> void:
	match event.type:
		SimEvent.Type.SHOT:
			var color: Color = WEAPON_COLORS.get(event.tag, Color(1, 0.8, 0.4))
			effects.muzzle_flash(event.pos, color)
			if event.a == local_id:
				Audio.play_global(StringName("shot_%s" % event.tag), -4.0)
			else:
				Audio.play_at(StringName("shot_%s" % event.tag), event.pos, -2.0)
		SimEvent.Type.ENEMY_SHOT:
			effects.muzzle_flash(event.pos, Color(1, 0.3, 0.45))
			Audio.play_at(&"shot_enemy", event.pos, -4.0)
		SimEvent.Type.HIT:
			var victim_is_player: bool = event.tag == &"player"
			effects.spark(event.pos, Color(1.0, 0.85, 0.5), 7)
			if victim_is_player:
				var view := robot_view(event.b)
				if view != null:
					view.hit_flash()
				Audio.play_at(&"hit_player", event.pos)
			else:
				Audio.play_at(&"hit_enemy", event.pos, -3.0)
			if Settings.get_bool("game/damage_numbers") and (event.a == local_id or event.b == local_id):
				var color := Color(1.0, 0.4, 0.4) if event.b == local_id else Color(1.0, 0.95, 0.6)
				effects.damage_number(event.pos, event.value, color)
		SimEvent.Type.HIT_WORLD:
			effects.spark(event.pos, Color(0.7, 0.85, 1.0), 4, 3.0, 0.05)
			Audio.play_at(&"hit_world", event.pos, -8.0)
		SimEvent.Type.KILL:
			if event.tag == &"player":
				effects.explosion(event.pos, Color(1.0, 0.6, 0.3), 1.4)
				Audio.play_at(&"explode_big", event.pos)
			else:
				var def := Content.enemy(event.tag)
				var color := def.color if def != null else Color(1, 0.4, 0.3)
				var big := def != null and def.scale > 1.2
				effects.explosion(event.pos, color, 1.5 if big else 0.8)
				Audio.play_at(&"explode_big" if big else &"explode_small", event.pos, -2.0)
		SimEvent.Type.RESPAWN:
			effects.shockwave(event.pos, Color(0.4, 0.85, 1.0), 2.5, 0.7)
			Audio.play_at(&"respawn", event.pos)
		SimEvent.Type.JUMP:
			effects.dust(event.pos, 4)
			Audio.play_at(&"jump", event.pos, -8.0)
		SimEvent.Type.LAND:
			effects.dust(event.pos, 7)
			Audio.play_at(&"land", event.pos, -6.0)
		SimEvent.Type.DASH:
			effects.shockwave(event.pos, Color(0.6, 0.85, 1.0), 1.4, 0.3)
			Audio.play_at(&"dash", event.pos, -4.0)
		SimEvent.Type.PICKUP:
			var part := Content.part(event.tag)
			var color := Color(1.0, 0.4, 0.45) if event.tag == &"health" else Color(0.3, 0.9, 1.0)
			var sound := &"pickup_orb"
			if part != null:
				color = part.get_rarity_color()
				sound = &"pickup_rare" if part.rarity >= RobotPart.Rarity.EPIC else &"pickup_part"
			effects.pickup_burst(event.pos, color)
			if event.a == local_id:
				Audio.play_global(sound, -2.0, 0.0)
			else:
				Audio.play_at(sound, event.pos, -6.0)
		SimEvent.Type.ENEMY_SPAWN:
			var def := Content.enemy(event.tag)
			effects.shockwave(event.pos, def.color if def != null else Color(1, 0.3, 0.3), 2.0, 0.6)
			Audio.play_at(&"enemy_spawn", event.pos, -10.0)
		SimEvent.Type.ENEMY_WINDUP:
			Audio.play_at(&"windup", event.pos, -2.0, 0.0)


func _sync(entities: Array[RenderFrame.Entity], views: Dictionary, delta: float, factory: Callable) -> void:
	var seen := {}
	for entity in entities:
		seen[entity.id] = true
		var view: Node3D = views.get(entity.id)
		if view == null:
			view = factory.call(entity)
			views[entity.id] = view
			add_child(view)
		view.call("apply", entity, delta)
	for id in views.keys():
		if not seen.has(id):
			views[id].queue_free()
			views.erase(id)


func _make_robot(entity: RenderFrame.Entity) -> Node3D:
	var view := RobotView.new()
	view.name = "Robot%d" % entity.id
	return view


func _make_enemy(entity: RenderFrame.Entity) -> Node3D:
	var view := EnemyView.new()
	view.setup(Content.enemy(entity.type_id))
	return view


func _make_projectile(entity: RenderFrame.Entity) -> Node3D:
	var view := ProjectileView.new()
	view.setup(entity.type_id)
	return view


func _make_pickup(entity: RenderFrame.Entity) -> Node3D:
	var view := PickupView.new()
	view.setup(entity.type_id)
	return view


func _cover_material(kind: int, top: float) -> ShaderMaterial:
	var key := "%d|%.2f" % [kind, top]
	if not _cover_materials.has(key):
		var style: Dictionary = COVER_STYLES.get(kind, COVER_STYLES[WorldGeometry.Kind.MID])
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/cover_box.gdshader")
		material.set_shader_parameter("base_color", style["base"])
		material.set_shader_parameter("rim_color", style["rim"])
		material.set_shader_parameter("top", top)
		_cover_materials[key] = material
	return _cover_materials[key]


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.045, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.58, 0.78)
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	_sun.light_energy = 0.85
	_sun.shadow_enabled = Settings.get_bool("video/shadows")
	_sun.directional_shadow_max_distance = 45.0
	add_child(_sun)


func _on_setting_changed(key: String) -> void:
	if key == "video/shadows" and _sun != null:
		_sun.shadow_enabled = Settings.get_bool("video/shadows")
