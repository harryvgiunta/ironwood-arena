extends Node3D
## Seamless frontier: all public positions are world-space with this root at identity.

const Geo = preload("res://scripts/geo.gd")
const WorldStyleKit = preload("res://scripts/world/world_style.gd")
const TreeKit = preload("res://scripts/world/tree_kit.gd")
const WorldScatter = preload("res://scripts/world/scatter.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const GrassField = preload("res://scripts/world/grass_field.gd")
const WorldEnvironmentKit = preload("res://scripts/world/environment_kit.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const WORLD_LIMIT := 145.0
const GRID_STEP := 2.0
const GRID_CELLS := 145
const GRID_SIDE := GRID_CELLS + 1
## The mob navigation field: one byte per square metre, marking the cells a
## walking body cannot enter. Mob AI moves against this instead of paying a
## physics query per body per frame (see `MobGround`).
const NAV_HALF := 150
const NAV_SIDE := NAV_HALF * 2
## Only obstacles that actually stand in a body's way are marked: a roof panel
## above head height never blocks a walk, and a kerb is stepped over.
const NAV_STEP_UP := 0.4
const NAV_HEAD := 1.4
const BRIDGE_HEIGHT := 3.0
const TREE_CANDIDATES := 1120
const TREE_CHUNK := 44.0
const BACKDROP_TREES := 520
const GRASS_SEED := 93617
const TREE_SEED := 73109

var player_spawn: Vector3 = Vector3(0.0, 3.0, 35.0)
var town_entry: Vector3 = Vector3(0.0, 3.0, 47.0)
var enemy_spawns: Array[Dictionary] = []
## Authored devil-court placements. Kept separate from `enemy_spawns` so the
## existing wolf/cinder spawn contract stays a stable 36 entries.
var devil_spawns: Array[Dictionary] = []
## Unholy Forest placements. A third table for the same reason: the legacy 36
## and the 16 devils stay measured contracts, and these mobs own the woodland.
var forest_spawns: Array[Dictionary] = []
## Crimson ranger clones: player-rig patrols with random kits.
var ranger_spawns: Array[Dictionary] = []
var interactables: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []
var map_paths: Array[PackedVector3Array] = []
var generation_stats: Dictionary = {}

# The Y component is the designed route elevation, not a sampled terrain value.
# Shared junctions have identical grades; the steepest designed route is under 18 degrees.
var _routes: Array[PackedVector3Array] = [
	PackedVector3Array([Vector3(0, 3, 48), Vector3(0, 3, 35), Vector3(0, 3, 4), Vector3(12, 3, -10), Vector3(32, 3, -10), Vector3(55, 5, -35), Vector3(55, 7, -60)]),
	PackedVector3Array([Vector3(0, 3, 4), Vector3(-30, 3, -8), Vector3(-55, 4, -25), Vector3(-55, 7, -60), Vector3(-35, 13, -85), Vector3(-15, 18, -100)]),
	PackedVector3Array([Vector3(55, 7, -60), Vector3(55, 7, -81), Vector3(30, 11, -85), Vector3(-15, 18, -100)]),
	PackedVector3Array([Vector3(-15, 3, 37), Vector3(0, 3, 35), Vector3(15, 3, 37)]),
	PackedVector3Array([Vector3(-15, 3, 21), Vector3(0, 3, 22), Vector3(15, 3, 21)])
]
var _heights := PackedFloat32Array()
var _nav := PackedByteArray()
var _rng := RandomNumberGenerator.new()
var _solids: StaticBody3D
var _wood: StandardMaterial3D
var _timber: StandardMaterial3D
var _plaster: StandardMaterial3D
var _roof: StandardMaterial3D
var _stone: StandardMaterial3D
var _gold: StandardMaterial3D
var _cyan: StandardMaterial3D
var _activated: Dictionary = {}
var style: WorldStyleKit
var _tree_variants: Dictionary = {}
var _tree_species: Dictionary = {}
var _rock_material: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 714209
	style = WorldStyleKit.frontier()
	var prop_tints: Dictionary = style.props.get("tints", {})
	_wood = TextureLibrary.building_material("wood", prop_tints.get("wood", Color.WHITE))
	_timber = TextureLibrary.building_material("timber", prop_tints.get("timber", Color.WHITE))
	_plaster = TextureLibrary.building_material("plaster", prop_tints.get("plaster", Color.WHITE))
	_roof = TextureLibrary.building_material("roof", prop_tints.get("roof", Color.WHITE))
	_stone = TextureLibrary.building_material("stone", prop_tints.get("stone", Color.WHITE))
	_rock_material = TextureLibrary.rock_material()
	_gold = Geo.material(Color("b99b55"), 0.3)
	_gold.metallic = 0.55
	_gold.roughness = 0.36
	_cyan = Geo.material(Color("558e92"), 0.2)
	_cyan.metallic = 0.2
	_cyan.roughness = 0.28
	_solids = StaticBody3D.new()
	_solids.name = "FrontierSolidObstacles"
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	add_child(_solids)
	Perf.begin("world.build")
	_build_lighting()
	_build_terrain()
	_build_map_data()
	_build_village()
	_build_water_and_bridge()
	_build_fort()
	_build_shrine()
	_build_waystone("forest", "Heartwood Waystone", Vector2(-55, -25))
	_build_waystone("ruins", "Watchfall Waystone", Vector2(55, -60))
	_build_waystone("ridge", "Suncrest Waystone", Vector2(-15, -100))
	_build_enemy_spawns()
	_build_devil_spawns()
	_build_forest_spawns()
	_build_ranger_spawns()
	_build_woodland()
	_build_backdrop_trees()
	_build_rocks()
	_build_ground_cover()
	_build_signposts()
	Perf.end()
	generation_stats["terrain_vertices"] = GRID_SIDE * GRID_SIDE
	generation_stats["terrain_triangles"] = (GRID_CELLS * GRID_CELLS - 1) * 2
	generation_stats["nodes"] = _count_nodes(self)
	generation_stats["obstacle_shapes"] = _solids.get_child_count()
	generation_stats["paths"] = map_paths.size()
	generation_stats["enemies"] = enemy_spawns.size()
	generation_stats["devils"] = devil_spawns.size()
	generation_stats["forests"] = forest_spawns.size()
	generation_stats["rangers"] = ranger_spawns.size()
	generation_stats["texture_count"] = TextureLibrary.texture_count()
	generation_stats["world_style"] = style.id


func _build_lighting() -> void:
	var built: Dictionary = WorldEnvironmentKit.build(self, style)
	generation_stats["sky_texture"] = String(style.sky.get("texture", ""))
	generation_stats["sun"] = built.get("sun") != null


func _route_sample(x: float, z: float) -> Vector2:
	var query := Vector2(x, z)
	var nearest: float = INF
	var grade: float = 3.0
	for route in _routes:
		for i in range(route.size() - 1):
			var a := Vector2(route[i].x, route[i].z)
			var b := Vector2(route[i + 1].x, route[i + 1].z)
			var span := b - a
			var along: float = clampf((query - a).dot(span) / span.length_squared(), 0.0, 1.0)
			var distance: float = query.distance_to(a + span * along)
			if distance < nearest:
				nearest = distance
				grade = lerpf(route[i].y, route[i + 1].y, along)
	return Vector2(nearest, grade)


func _raw_height(x: float, z: float) -> float:
	var height: float = 3.0 + sin(x * 0.037) * 2.4 + sin(z * 0.043 + x * 0.018) * 2.0
	height += 13.0 * exp(-((x + 18.0) * (x + 18.0) / 3000.0 + (z + 104.0) * (z + 104.0) / 1800.0))
	height += 5.5 * exp(-((x - 87.0) * (x - 87.0) / 1000.0 + (z + 45.0) * (z + 45.0) / 2600.0))
	var route := _route_sample(x, z)
	height = lerpf(height, route.y, 1.0 - smoothstep(3.8, 10.0, route.x))
	# Broad, flat usable clearings, rather than foundations hovering over hills.
	for clearing in [Vector4(0, 32, 3, 26), Vector4(-55, -25, 4, 11), Vector4(55, -60, 7, 20), Vector4(-15, -100, 18, 10)]:
		var distance: float = Vector2(x - clearing.x, z - clearing.y).length()
		height = lerpf(height, clearing.z, 1.0 - smoothstep(clearing.w, clearing.w + 9.0, distance))
	# A real depression under the pond and bridge. Roads stop at the bridge abutments.
	var pond_radius: float = Vector2((x - 22.0) / 10.0, (z + 10.0) / 34.0).length()
	height = lerpf(height, -1.2, 1.0 - smoothstep(0.62, 1.0, pond_radius))
	# Continuous steep foothills enclose the finite zone without floating scenery walls.
	var edge: float = maxf(absf(x), absf(z))
	height += smoothstep(114.0, 145.0, edge) * (42.0 + 5.0 * sin(x * 0.08) * cos(z * 0.065))
	return height


func _grid_height(ix: int, iz: int) -> float:
	if not _heights.is_empty():
		return _heights[iz * GRID_SIDE + ix]
	return _raw_height(-WORLD_LIMIT + float(ix) * GRID_STEP, -WORLD_LIMIT + float(iz) * GRID_STEP)


func terrain_height(x: float, z: float) -> float:
	# Barycentric interpolation uses exactly the diagonal of the rendered/collision mesh.
	var gx: float = clampf((x + WORLD_LIMIT) / GRID_STEP, 0.0, float(GRID_CELLS))
	var gz: float = clampf((z + WORLD_LIMIT) / GRID_STEP, 0.0, float(GRID_CELLS))
	var ix: int = mini(int(floor(gx)), GRID_CELLS - 1)
	var iz: int = mini(int(floor(gz)), GRID_CELLS - 1)
	var u: float = gx - float(ix)
	var v: float = gz - float(iz)
	var a: float = _grid_height(ix, iz)
	var b: float = _grid_height(ix + 1, iz)
	var c: float = _grid_height(ix, iz + 1)
	var d: float = _grid_height(ix + 1, iz + 1)
	if u + v <= 1.0:
		return a + u * (b - a) + v * (c - a)
	return d + (1.0 - u) * (c - d) + (1.0 - v) * (b - d)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, terrain_height(x, z), z)


func _build_terrain() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	_heights.resize(GRID_SIDE * GRID_SIDE)
	vertices.resize(GRID_SIDE * GRID_SIDE)
	colors.resize(GRID_SIDE * GRID_SIDE)
	for iz in range(GRID_SIDE):
		for ix in range(GRID_SIDE):
			var x: float = -WORLD_LIMIT + float(ix) * GRID_STEP
			var z: float = -WORLD_LIMIT + float(iz) * GRID_STEP
			var height: float = _raw_height(x, z)
			var index: int = iz * GRID_SIDE + ix
			_heights[index] = height
			vertices[index] = Vector3(x, height, z)
			var shade: float = (sin(x * 0.21) * cos(z * 0.18) + 1.0) * 0.5
			# Vertex colour is a light value/hue multiplier over the authored
			# terrain textures; the texture supplies the material colour.
			var color := Color(0.78, 0.84, 0.68).lerp(Color(0.96, 0.95, 0.78), shade * 0.7)
			if z < -75.0:
				color = color.lerp(Color(0.86, 0.84, 0.76), clampf((-z - 75.0) / 65.0, 0.0, 0.6))
			var road_distance: float = _route_sample(x, z).x
			var dirt: float = 1.0 - smoothstep(1.5, 3.4, road_distance)
			color = color.lerp(Color(1.0, 0.95, 0.84), dirt)
			if height < 1.0:
				color = Color(0.62, 0.58, 0.48)
				dirt = maxf(dirt, 0.55)
			color = color.lerp(Color(0.80, 0.82, 0.84), smoothstep(120.0, 140.0, maxf(absf(x), absf(z))))
			color.a = dirt
			colors[index] = color
	for iz in range(GRID_CELLS):
		for ix in range(GRID_CELLS):
			# One cell of the Wayfarer Inn floor is left open for the delve hatch:
			# the collision trimesh shares this mesh, so the hole is physical.
			if ix == 80 and iz == 93:
				continue
			var a: int = iz * GRID_SIDE + ix
			indices.append_array(PackedInt32Array([a, a + 1, a + GRID_SIDE, a + 1, a + GRID_SIDE + 1, a + GRID_SIDE]))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		var normal: Vector3 = (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := TextureLibrary.terrain_material(style)
	Geo.mesh_node(self, mesh, material).name = "ContinuousFrontierTerrain"
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)


func _build_map_data() -> void:
	player_spawn = _ground(town_entry.x, town_entry.z)
	for entry in [
		["Hearthstead", Vector2(0, 35)], ["Heartwood", Vector2(-55, -25)],
		["Watchfall Ruins", Vector2(55, -60)], ["Suncrest Ridge", Vector2(-15, -100)],
		["Willow Bridge", Vector2(22, -10)], ["The Sunken Delve", Vector2(16, 42)],
	]:
		var point: Vector2 = entry[1]
		var location := _ground(point.x, point.y)
		if entry[0] == "Willow Bridge":
			location.y = BRIDGE_HEIGHT
		landmarks.append({"name": String(entry[0]), "position": location})
	for route in _routes:
		var points := PackedVector3Array()
		for i in range(route.size() - 1):
			var count: int = maxi(1, int(ceil(route[i].distance_to(route[i + 1]) / 2.0)))
			for step in range(count):
				var point: Vector3 = route[i].lerp(route[i + 1], float(step) / float(count))
				point.y = terrain_height(point.x, point.z)
				if point.x >= 12.0 and point.x <= 32.0 and absf(point.z + 10.0) < 0.1:
					point.y = BRIDGE_HEIGHT
				points.append(point)
		var end: Vector3 = route[route.size() - 1]
		points.append(_ground(end.x, end.z))
		map_paths.append(points)


func region_at(world_position: Vector3) -> String:
	var p := Vector2(world_position.x, world_position.z)
	if p.distance_to(Vector2(0, 32)) < 29.0:
		return "Hearthstead · Safe Haven"
	if p.distance_to(Vector2(22, -10)) < 18.0:
		return "Willowwater Crossing"
	if p.distance_to(Vector2(55, -60)) < 26.0:
		return "Watchfall Ruins"
	if p.y < -77.0:
		return "Suncrest Ridge"
	if p.x < -25.0:
		return "Heartwood Forest"
	return "The Woodland Frontier"


func _root_at(label: String, point: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.position = point
	add_child(root)
	return root


func _box_collision(parent: Node3D, size: Vector3, point: Vector3, angle: float = 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = parent.transform * Transform3D(Basis(Vector3.UP, angle), point) if parent != self else Transform3D(Basis(Vector3.UP, angle), point)
	_add_solid(collision)


func _solid_box(parent: Node3D, size: Vector3, point: Vector3, material: Material, angle: float = 0.0) -> MeshInstance3D:
	var visual := Geo.box(parent, size, point, material)
	visual.rotation.y = angle
	_box_collision(parent, size, point, angle)
	return visual


func _build_village() -> void:
	var forester := _build_house(Vector2(-15, 42), 0.0, "ForesterHouse")
	var inn := _build_house(Vector2(15, 42), 0.0, "WayfarerInn")
	var fletcher := _build_house(Vector2(-15, 16), PI, "FletcherWorkshop")
	var store := _build_house(Vector2(15, 16), PI, "HearthsteadStore")
	var camp := _root_at("HearthsteadCampfire", _ground(4, 35))
	for i in range(9):
		var angle: float = float(i) * TAU / 9.0
		Geo.sphere(camp, 0.24, Vector3(cos(angle) * 0.85, 0.15, sin(angle) * 0.85), _stone, Vector3(1, 0.65, 1))
	for i in range(3):
		var angle: float = float(i) * PI / 3.0
		Geo.beam(camp, Vector3(cos(angle), 0.21, sin(angle)) * 0.7, Vector3(-cos(angle) * 0.7, 0.3, -sin(angle) * 0.7), 0.12, _timber)
	var flame := Geo.material(Color("ffb74c"))
	flame.emission_enabled = true
	flame.emission = Color("f88a30")
	flame.emission_energy_multiplier = 1.3
	Geo.cylinder(camp, 0.36, 0.0, 1.0, Vector3(0, 0.65, 0), flame, 7)
	Geo.cylinder(camp, 0.23, 0.0, 0.75, Vector3(0.2, 0.55, 0.1), flame, 5)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.4, 0)
	glow.light_color = Color("ffc075")
	glow.light_energy = 1.1
	glow.omni_range = 8.0
	camp.add_child(glow)
	interactables.append({"id": "camp", "name": "Hearthstead Campfire", "kind": "camp", "position": camp.position, "node": camp})
	for x in [-2.5, 2.5]:
		_solid_box(camp, Vector3(0.65, 0.55, 2.0), Vector3(x, 0.275, 0), _wood)
	# An open market canopy frames the square without blocking the northbound road.
	var market := _root_at("OpenMarket", _ground(-7, 28))
	for x in [-2.0, 2.0]:
		for z in [-1.5, 1.5]:
			_solid_box(market, Vector3(0.16, 3, 0.16), Vector3(x, 1.5, z), _timber)
	Geo.box(market, Vector3(4.5, 0.12, 3.5), Vector3(0, 3, 0), Geo.material(Color("688d83")))
	_solid_box(market, Vector3(3.6, 0.9, 0.85), Vector3(0, 0.45, -0.8), _wood)
	for i in range(5):
		Geo.sphere(market, 0.2, Vector3(-1.2 + float(i) * 0.5, 1.04, -0.8), _gold)
	_build_town_services(forester, fletcher, store)
	_build_delve_hatch(inn)


func _build_town_services(forester: Node3D, fletcher: Node3D, store: Node3D) -> void:
	# The three keepers live in the town's own buildings. Their counters face
	# the doorway; the interactable point sits on the customer side.
	_build_vendor_station(forester,Vector3(0.8,0,1.2),1,Color("8f4a38"),"SMITH BRANN","Smith Brann")
	_build_vendor_station(fletcher,Vector3(0,0,1.0),0,Color("3f6b57"),"STOREKEEPER ORLA","Storekeeper Orla")
	_build_vendor_station(store,Vector3(0,0,1.0),2,Color("4b4f72"),"QUARTERMASTER VEY","Quartermaster Vey")
	_build_stash_chest()
	_build_arena_portal()


func _build_vendor_station(house: Node3D, local_at: Vector3, vendor_index: int, accent: Color, label_text: String, display_name: String) -> void:
	var keeper := Node3D.new()
	keeper.name = "Keeper_%d" % vendor_index
	keeper.position = local_at
	house.add_child(keeper)
	var cloth := Geo.material(accent,0.72,0.62)
	var trim := Geo.material(Color("b99b55"),0.3,0.4)
	var skin := Geo.material(Color("c9a27a"),0.12,0.82)
	var dark := Geo.material(Color("262b31"),0.6,0.5)
	Geo.cylinder(keeper,0.32,0.46,1.12,Vector3(0,0.58,0),cloth,10)
	Geo.cylinder(keeper,0.30,0.30,0.10,Vector3(0,1.16,0),trim,10)
	Geo.sphere(keeper,0.23,Vector3(0,1.40,0),skin,Vector3(1,1.08,1))
	Geo.cylinder(keeper,0.27,0.30,0.20,Vector3(0,1.58,0),dark,8)
	Geo.box(keeper,Vector3(0.16,0.62,0.18),Vector3(-0.34,0.82,0),cloth)
	Geo.box(keeper,Vector3(0.16,0.62,0.18),Vector3(0.34,0.82,0),cloth)
	Geo.box(keeper,Vector3(0.42,0.20,0.06),Vector3(0,0.94,-0.22),trim)
	var label := Label3D.new()
	label.text = label_text
	label.font_size = 34
	label.pixel_size = 0.0034
	label.modulate = Color("f0d7a2")
	label.outline_size = 6
	label.position = Vector3(0,2.18,0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	keeper.add_child(label)
	_box_collision(keeper,Vector3(0.62,1.8,0.62),Vector3(0,0.9,0))
	var counter_at := local_at + Vector3(0,0,-1.0)
	_solid_box(house,Vector3(2.9,0.95,0.72),counter_at,_wood)
	Geo.box(house,Vector3(3.0,0.08,0.82),counter_at + Vector3(0,0.51,0),trim)
	var open_at := house.to_global(counter_at + Vector3(0,0,-0.92))
	interactables.append({
		"id": "vendor_%d" % vendor_index,
		"name": display_name,
		"kind": "vendor", "vendor": vendor_index,
		"position": open_at, "node": keeper,
	})


func _build_stash_chest() -> void:
	var root := _root_at("TownStash", _ground(-7, 29.2))
	_solid_box(root,Vector3(1.2,0.72,0.72),Vector3(0,0.36,0),_wood)
	Geo.box(root,Vector3(1.24,0.12,0.76),Vector3(0,0.74,0),_stone)
	for x in [-0.38,0.38]:
		Geo.box(root,Vector3(0.10,0.76,0.78),Vector3(x,0.38,0),_timber)
	Geo.box(root,Vector3(0.22,0.24,0.10),Vector3(0,0.44,-0.40),_gold)
	var label := Label3D.new()
	label.text = "TOWN STASH"
	label.font_size = 34
	label.pixel_size = 0.0034
	label.modulate = Color("e9d8a8")
	label.outline_size = 6
	label.position = Vector3(0,1.32,0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	interactables.append({
		"id": "stash", "name": "Town Stash", "kind": "stash",
		"position": root.global_position + Vector3(0,0,0.9), "node": root,
	})


func _build_arena_portal() -> void:
	var root := _root_at("ArenaPortal", _ground(7, 44))
	var rune := Geo.material(Color("6f4fa1"),0.2)
	rune.emission_enabled = true
	rune.emission = Color("9b6cff")
	rune.emission_energy_multiplier = 1.4
	var veil := StandardMaterial3D.new()
	veil.albedo_color = Color(0.36,0.22,0.62,0.62)
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0,1.0]:
		_solid_box(root,Vector3(0.46,3.4,0.5),Vector3(side*1.55,1.7,0),_stone)
		Geo.box(root,Vector3(0.20,3.0,0.24),Vector3(side*1.55,1.8,0.28),rune)
	_solid_box(root,Vector3(3.8,0.46,0.54),Vector3(0,3.55,0),_stone)
	Geo.box(root,Vector3(2.35,2.9,0.06),Vector3(0,1.62,0),veil)
	Geo.cylinder(root,1.7,1.7,0.035,Vector3(0,0.03,0),rune,32)
	var light := OmniLight3D.new()
	light.position = Vector3(0,1.7,0.5)
	light.light_color = Color("a37bff")
	light.light_energy = 1.3
	light.omni_range = 6.0
	root.add_child(light)
	var label := Label3D.new()
	label.text = "ARENA"
	label.font_size = 40
	label.pixel_size = 0.0036
	label.modulate = Color("d9c8ff")
	label.outline_size = 6
	label.position = Vector3(0,4.05,0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
	interactables.append({
		"id": "arena_portal", "name": "Arena Portal", "kind": "portal",
		"position": root.global_position + Vector3(0,0,1.0), "node": root,
	})


func is_over_delve_hatch(point: Vector3) -> bool:
	return absf(point.x - 16.0) < 0.92 and absf(point.z - 42.0) < 0.92


func _build_delve_hatch(inn: Node3D) -> void:
	# A real opening in the inn floor: the terrain cell underneath is omitted
	# from the shared visual/collision mesh, so the ranger can jump in. The
	# shaft is walled down to a dark bottom; main.gd changes scenes on the fall.
	var root := Node3D.new()
	root.name = "SunkenDelveHatch"
	root.position = Vector3(1, 0.06, 0)
	inn.add_child(root)
	var well := Geo.material(Color("05090a"), 0.0, 0.95)
	well.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var iron := Geo.material(Color("3a444b"), 0.72, 0.44)
	var teal_rune := Geo.material(Color("4a8d86"), 0.15)
	teal_rune.emission_enabled = true
	teal_rune.emission = Color("3fd6c0")
	teal_rune.emission_energy_multiplier = 0.9
	for i in range(8):
		var angle: float = TAU * float(i) / 8.0
		var block := Geo.box(root, Vector3(0.66, 0.16, 0.36), Vector3(cos(angle) * 1.35, 0.08, sin(angle) * 1.35), _stone)
		block.rotation.y = -angle
		if i in [2, 6]:
			var rune := Geo.box(root, Vector3(0.24, 0.02, 0.09), Vector3(cos(angle) * 1.35, 0.17, sin(angle) * 1.35), teal_rune)
			rune.rotation.y = -angle
	var ring := TorusMesh.new()
	ring.inner_radius = 1.18
	ring.outer_radius = 1.28
	ring.rings = 32
	ring.ring_segments = 8
	Geo.mesh_node(root, ring, iron, Vector3(0, 0.17, 0))
	# Shaft walls below the floor keep a falling ranger inside the opening.
	for side in [-1.0, 1.0]:
		_solid_box(root, Vector3(0.3, 5.2, 2.3), Vector3(side * 1.15, -2.72, 0), _stone)
		_solid_box(root, Vector3(2.3, 5.2, 0.3), Vector3(0, -2.72, side * 1.15), _stone)
	Geo.box(root, Vector3(2.0, 0.02, 2.0), Vector3(0, -3.15, 0), well)
	Geo.cylinder(root, 0.44, 0.0, 2.6, Vector3(0, -1.4, 0), teal_rune, 10)
	# The trapdoor leaf stands open on its north hinges, clear of the walk in.
	var leaf := Node3D.new()
	leaf.position = Vector3(0, 0.15, -1.15)
	leaf.rotation.x = deg_to_rad(-105.0)
	root.add_child(leaf)
	for i in range(4):
		Geo.box(leaf, Vector3(0.3, 0.05, 1.55), Vector3(-0.45 + float(i) * 0.3, 0.0, 0.775), _wood)
	for z in [0.24, 1.31]:
		Geo.box(leaf, Vector3(1.56, 0.06, 0.1), Vector3(0, 0.03, z), iron)
	Geo.box(root, Vector3(2.6, 0.14, 0.16), Vector3(0, 3.2, 0.05), _timber)
	for side in [-1.0, 1.0]:
		Geo.box(root, Vector3(0.03, 0.82, 0.03), Vector3(side * 0.55, 2.78, 0.05), iron)
	Geo.box(root, Vector3(1.5, 0.34, 0.06), Vector3(0, 2.3, 0.08), _wood)
	var label := Label3D.new()
	label.text = "THE SUNKEN DELVE"
	label.font_size = 40
	label.pixel_size = 0.0036
	label.modulate = Color("bde8df")
	label.outline_size = 6
	label.position = Vector3(0, 2.3, 0.02)
	label.rotation.y = PI
	root.add_child(label)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.15, 0.1)
	light.light_color = Color("55e0cd")
	light.light_energy = 1.6
	light.omni_range = 4.2
	root.add_child(light)
	# Kept as a map marker only; the fall itself is the entrance.
	interactables.append({"id": "delve", "name": "The Sunken Delve", "kind": "delve", "position": root.global_position, "node": root})


func _build_house(point: Vector2, angle: float, label: String) -> Node3D:
	var house := _root_at(label, _ground(point.x, point.y))
	house.rotation.y = angle
	# An actual 1.8m doorway, open interior, and walkable terrain floor.
	_solid_box(house, Vector3(7, 3.7, 0.32), Vector3(0, 1.85, 3), _plaster)
	for x in [-3.5, 3.5]:
		_solid_box(house, Vector3(0.32, 3.7, 6), Vector3(x, 1.85, 0), _plaster)
	for x in [-2.2, 2.2]:
		_solid_box(house, Vector3(2.6, 3.7, 0.32), Vector3(x, 1.85, -3), _plaster)
	_solid_box(house, Vector3(1.8, 1.1, 0.32), Vector3(0, 3.15, -3), _plaster)
	for x in [-3.5, -0.95, 0.95, 3.5]:
		Geo.box(house, Vector3(0.18, 3.7, 0.42), Vector3(x, 1.85, -3.02), _timber)
	for y in [0.25, 2.65, 3.65]:
		Geo.box(house, Vector3(7.3, 0.18, 0.42), Vector3(0, y, 3.02), _timber)
		for x in [-3.52, 3.52]:
			Geo.box(house, Vector3(0.22, 0.18, 6.2), Vector3(x, y, 0), _timber)
		if y > 2.6:
			Geo.box(house, Vector3(7.3, 0.18, 0.42), Vector3(0, y, -3.02), _timber)
		else:
			for x in [-2.2, 2.2]:
				Geo.box(house, Vector3(2.6, 0.18, 0.42), Vector3(x, y, -3.02), _timber)
	for side in [-1.0, 1.0]:
		var roof_panel := Geo.box(house, Vector3(4.35, 0.22, 7.0), Vector3(side * 1.85, 4.5, 0), _roof)
		roof_panel.rotation.z = -side * 0.45
		var shape := BoxShape3D.new()
		shape.size = Vector3(4.35, 0.22, 7.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = house.transform * roof_panel.transform
		_add_solid(collision)
	_solid_box(house, Vector3(0.85, 2.0, 0.85), Vector3(2.1, 4.9, 1.1), _stone)
	for x in [-2.2, 2.2]:
		Geo.box(house, Vector3(1.1, 1.15, 0.08), Vector3(x, 2.05, -3.19), _timber)
		Geo.box(house, Vector3(0.81, 0.87, 0.09), Vector3(x, 2.05, -3.24), _gold)
		Geo.box(house, Vector3(0.06, 0.95, 0.1), Vector3(x, 2.05, -3.3), _timber)
		Geo.box(house, Vector3(0.9, 0.06, 0.1), Vector3(x, 2.05, -3.3), _timber)
	# Door swung inward, never a solid slab across the entrance.
	Geo.box(house, Vector3(0.14, 2.55, 1.7), Vector3(-0.86, 1.275, -2.1), _wood)
	Geo.box(house, Vector3(1.8, 0.035, 2.0), Vector3(0, 0.025, -4.0), _stone)
	return house


func _build_water_and_bridge() -> void:
	var water := TextureLibrary.water_material()
	# Opaque water keeps Compatibility rendering stable; its shore is inside the carved bowl.
	var pond := Geo.cylinder(self, 1, 1, 0.045, Vector3(22, 0.25, -10), water, 64)
	pond.name = "Willowwater"
	pond.scale = Vector3(7.75, 1, 26.35)
	pond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bridge := _root_at("WillowBridge", Vector3(22, BRIDGE_HEIGHT, -10))
	_solid_box(bridge, Vector3(22, 0.35, 4.8), Vector3(0, -0.175, 0), _timber)
	for i in range(44):
		Geo.box(bridge, Vector3(0.475, 0.055, 4.7), Vector3(-10.75 + float(i) * 0.5, 0.025, 0), _wood)
	for side in [-1.0, 1.0]:
		_solid_box(bridge, Vector3(21.7, 0.18, 0.18), Vector3(0, 1.05, side * 2.3), _wood)
		_solid_box(bridge, Vector3(21.7, 0.16, 0.16), Vector3(0, 0.5, side * 2.3), _wood)
		for i in range(7):
			var x: float = -10.5 + float(i) * 3.5
			_solid_box(bridge, Vector3(0.22, 3.8, 0.22), Vector3(x, -0.65, side * 2.3), _timber)
	# Low entry thresholds are flush with the y=3 route, not raised stair obstacles.
	for x in [10.5, 33.5]:
		_solid_box(self, Vector3(1.5, 0.25, 5.2), Vector3(x, BRIDGE_HEIGHT - 0.125, -10), _stone)
	for i in range(18):
		var angle: float = TAU * float(i) / 18.0
		var point := _ground(22 + cos(angle) * 9.3, -10 + sin(angle) * 31.5)
		if absf(point.z + 10.0) < 4.0:
			continue
		for stem in range(3):
			Geo.cylinder(self, 0.035, 0.02, 1.25, point + Vector3(float(stem) * 0.16, 0.6, 0), _wood, 4)


func _build_fort() -> void:
	var fort := _root_at("WatchfallFortress", _ground(55, -60))
	# South gate is an unobstructed eight-metre gap aligned with the village road.
	for x in [-10.0, 10.0]:
		_solid_box(fort, Vector3(12, 4.5, 1.6), Vector3(x, 2.25, 15), _stone)
		_solid_box(fort, Vector3(12, 3.7, 1.6), Vector3(x, 1.85, -15), _stone)
	for x in [-16.0, 16.0]:
		_solid_box(fort, Vector3(1.6, 4.2, 30), Vector3(x, 2.1, 0), _stone)
	# North gap also leads directly onto the ridge trail.
	for z in [-15.0, 15.0]:
		for x in [-16.0, 16.0]:
			_solid_box(fort, Vector3(4, 8.2, 4), Vector3(x, 4.1, z), _stone)
			for corner in [-1.25, 1.25]:
				_solid_box(fort, Vector3(1.3, 1.0, 1.3), Vector3(x + corner, 8.7, z - 1.25), _stone)
				_solid_box(fort, Vector3(1.3, 1.0, 1.3), Vector3(x + corner, 8.7, z + 1.25), _stone)
	for x in [-5.0, 5.0]:
		_solid_box(fort, Vector3(2, 6.5, 2.8), Vector3(x, 3.25, 15), _stone)
	_solid_box(fort, Vector3(12, 1.2, 2.8), Vector3(0, 6.3, 15), _stone)
	for i in range(8):
		var x: float = -13.5 + float(i) * 3.8
		if absf(x) < 4.0:
			continue
		Geo.box(fort, Vector3(1.6, 0.8, 1.8), Vector3(x, 4.9, 15), _stone)
	for x in [-9.0, 9.0]:
		for z in [-6.0, 5.0]:
			_solid_box(fort, Vector3(1.2, 3.2, 1.2), Vector3(x, 1.6, z), _stone)
	Geo.box(fort, Vector3(7, 0.08, 7), Vector3(0, 0.04, 0), Geo.material(Color("a4a58f")))


func _build_shrine() -> void:
	var shrine := _root_at("SuncrestShrine", _ground(-15, -100))
	# No raised inaccessible dais: the shrine clearing and both approaches are continuous terrain.
	Geo.cylinder(shrine, 6.5, 6.5, 0.06, Vector3(0, 0.03, 0), _stone, 16)
	for i in range(7):
		var angle: float = PI + float(i) * PI / 6.0
		var point := Vector3(cos(angle) * 7.0, 0, sin(angle) * 7.0)
		_solid_box(shrine, Vector3(1.0, 5.7, 1.0), point + Vector3(0, 2.85, 0), _stone, -angle)
		Geo.box(shrine, Vector3(1.8, 0.45, 1.8), point + Vector3(0, 5.8, 0), _gold)
	var ring := TorusMesh.new()
	ring.inner_radius = 3.1
	ring.outer_radius = 3.5
	ring.rings = 24
	ring.ring_segments = 6
	var halo := Geo.mesh_node(shrine, ring, _gold, Vector3(0, 9.0, -3.5))
	halo.rotation.x = PI * 0.5
	_solid_box(shrine, Vector3(1.3, 10, 1.3), Vector3(0, 5, -7), _stone)


func _build_waystone(id: String, label: String, point: Vector2) -> void:
	var root := _root_at(label.replace(" ", ""), _ground(point.x, point.y))
	var material := Geo.material(Color("578a8c"), 0.3)
	material.emission_enabled = true
	material.emission = Color("326365")
	material.emission_energy_multiplier = 0.25
	_solid_box(root, Vector3(1.35, 4.2, 1.35), Vector3(0, 2.1, 0), _stone, PI * 0.25)
	for side in [-1.0, 1.0]:
		Geo.box(root, Vector3(0.09, 3.5, 0.1), Vector3(side * 0.57, 2.3, 0.72), material)
	var crown := Geo.cylinder(root, 0.72, 0.0, 2.0, Vector3(0, 4.75, 0), material, 5)
	crown.name = "WaystoneCrystal"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 1.12
	ring.rings = 20
	ring.ring_segments = 6
	Geo.mesh_node(root, ring, _gold, Vector3(0, 3.3, 0))
	var beacon_material := Geo.material(Color("80f5e4"))
	beacon_material.emission_enabled = true
	beacon_material.emission = Color("60f1de")
	beacon_material.emission_energy_multiplier = 1.6
	var beacon := Geo.cylinder(root, 0.13, 0.055, 21, Vector3(0, 15.4, 0), beacon_material, 6)
	beacon.name = "AwakenedBeacon"
	beacon.visible = false
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "WaystoneLight"
	light.position = Vector3(0, 4, 0)
	light.light_color = Color("67e8d9")
	light.omni_range = 11.0
	light.light_energy = 0.15
	root.add_child(light)
	root.set_meta("crystal_material", material)
	interactables.append({"id": id, "name": label, "kind": "waystone", "position": root.position, "node": root})


func activate_interactable(id: String) -> void:
	if _activated.has(id):
		return
	for entry in interactables:
		if String(entry["id"]) != id:
			continue
		_activated[id] = true
		if String(entry["kind"]) == "camp":
			return
		var root: Node3D = entry["node"]
		var material: StandardMaterial3D = root.get_meta("crystal_material")
		material.albedo_color = Color("a0fff0")
		material.emission = Color("70ffe4")
		material.emission_energy_multiplier = 1.6
		var beacon := root.get_node("AwakenedBeacon") as MeshInstance3D
		beacon.visible = true
		var light := root.get_node("WaystoneLight") as OmniLight3D
		light.light_energy = 2.0
		return


func _build_enemy_spawns() -> void:
	# Clear ground near roads; objective defenders, wilderness hunters and devil packs.
	# The Watchfall Ruins, Suncrest shrine and northern approach guards are wolves:
	# the Ruin sentinel they used to place was retired with the imported cinder
	# devil cutover, and the objectives stay defended.
	for entry in [
		Vector3(-49, 0, -20), Vector3(-61, 0, -30),
		Vector3(49, 0, -56), Vector3(61, 0, -65),
		Vector3(-9, 0, -96), Vector3(-21, 0, -98),
		Vector3(-27, 0, -1), Vector3(-39, 0, -16), Vector3(-62, 0, -48),
		Vector3(-48, 0, -68), Vector3(-35, 0, -82),
		Vector3(40, 0, -23), Vector3(62, 0, -33), Vector3(75, 0, -48),
		Vector3(35, 0, -80), Vector3(8, 0, -91)
	]:
		enemy_spawns.append({"position": _ground(entry.x, entry.z), "kind": int(entry.y)})
	# Cinder devil packs. The village glade pack sits just outside the camp's
	# 19 m safe ring; the others hunt the woods, the south meadow and the ridge.
	_add_devil_pack(Vector2(-20, 21), ["claw","dagger","sword","bow","claw"], 0)
	_add_devil_pack(Vector2(-46, -30), ["bow","sword","dagger"], 5)
	_add_devil_pack(Vector2(-20, -45), ["claw","sword","bow","dagger"], 8)
	_add_devil_pack(Vector2(22, 58), ["claw","bow","dagger","sword"], 12)
	_add_devil_pack(Vector2(-10, -70), ["bow","sword","claw","dagger"], 16)


func _add_devil_pack(center: Vector2, weapons: Array, first_index: int) -> void:
	for index in weapons.size():
		var angle := TAU * float(index) / float(weapons.size()) + float(first_index) * 0.37
		var point := center + Vector2(cos(angle), sin(angle)) * 2.6
		enemy_spawns.append({"position": _ground(point.x, point.y), "kind": 2,
			"pack_index": first_index + index, "weapon": str(weapons[index])})


func _build_devil_spawns() -> void:
	# Starting court: one of each species inside the town's 19 m safe ring, in a
	# readable arc about 10 m ahead of the south-gate spawn. They idle (no aggro)
	# until the player leaves the ring, so the new mobs are inspectable at once.
	for record in [
		{"mob": "hell_goat", "at": Vector2(7, 40)},
		{"mob": "succubus", "at": Vector2(3.5, 38)},
		{"mob": "spawn", "at": Vector2(0, 37)},
		{"mob": "beast", "at": Vector2(-3.5, 38)},
		{"mob": "gargoyle", "at": Vector2(-7, 40)},
	]:
		var point: Vector2 = record.at
		devil_spawns.append({"mob": str(record.mob),
			"position": _ground(point.x, point.y)})
	# The rest of the court is distributed along the existing roads and
	# clearings so each species is encountered in a distinct habitat: goat
	# sentries near the gate road, a spawn nest at the eastern crossroads, a
	# beast in the western woods, a succubus on the open meadow and gargoyles on
	# the northern ridge.
	for record in [
		{"mob": "hell_goat", "at": Vector2(-6, 14)},
		{"mob": "hell_goat", "at": Vector2(-38, -18)},
		{"mob": "succubus", "at": Vector2(24, -2)},
		{"mob": "succubus", "at": Vector2(-12, -32)},
		{"mob": "spawn", "at": Vector2(10, -16)},
		{"mob": "spawn", "at": Vector2(14, -19)},
		{"mob": "spawn", "at": Vector2(7, -20)},
		{"mob": "beast", "at": Vector2(-28, -10)},
		{"mob": "beast", "at": Vector2(44, -44)},
		{"mob": "gargoyle", "at": Vector2(30, -72)},
		{"mob": "gargoyle", "at": Vector2(-20, -64)},
	]:
		var point: Vector2 = record.at
		devil_spawns.append({"mob": str(record.mob),
			"position": _ground(point.x, point.y)})


## The Unholy Forest owns the woodland. Three mobs hold it: the hollow warden
## on the lanes, the ossuary stalker in the deep stands, and the gallowsroot
## standing over the clearings like felled timber that got up again.
##
## The threshold trio sits inside the town's 19 m safe ring beside the devil
## court, in an arc about 12 m ahead of the south gate, so the new mobset is
## inspectable at once and stays idle until the ranger leaves the ring.
func _build_forest_spawns() -> void:
	# Offsets from the south gate, so the trio stays ~14 m ahead of the spawn
	# inside the 19 m safe ring no matter how the terrain is sampled.
	for record in [
		{"mob": "hollow_warden", "at": Vector2(town_entry.x + 6.5, town_entry.z - 13.5)},
		{"mob": "ossuary_stalker", "at": Vector2(town_entry.x, town_entry.z - 14.5)},
		{"mob": "gallowsroot", "at": Vector2(town_entry.x - 6.5, town_entry.z - 13.5)},
	]:
		var point: Vector2 = record.at
		forest_spawns.append({"mob": str(record.mob), "position": _ground(point.x, point.y)})
	# The rest are distributed by habitat: stalkers hunt the deep western
	# stands, wardens and roots hold the meadows, the eastern fringe and the
	# northern shoulder where the woodland is densest.
	for record in [
		{"mob": "ossuary_stalker", "at": Vector2(-34, 6)},
		{"mob": "ossuary_stalker", "at": Vector2(-46, -4)},
		{"mob": "hollow_warden", "at": Vector2(-58, -16)},
		{"mob": "ossuary_stalker", "at": Vector2(-30, -22)},
		{"mob": "gallowsroot", "at": Vector2(-44, -34)},
		{"mob": "hollow_warden", "at": Vector2(-58, -44)},
		{"mob": "gallowsroot", "at": Vector2(-20, 62)},
		{"mob": "ossuary_stalker", "at": Vector2(-34, 70)},
		{"mob": "hollow_warden", "at": Vector2(-48, 58)},
		{"mob": "ossuary_stalker", "at": Vector2(26, 16)},
		{"mob": "gallowsroot", "at": Vector2(38, 4)},
		{"mob": "hollow_warden", "at": Vector2(50, -8)},
		{"mob": "gallowsroot", "at": Vector2(20, 64)},
		{"mob": "hollow_warden", "at": Vector2(34, 58)},
		{"mob": "ossuary_stalker", "at": Vector2(-24, 24)},
		{"mob": "gallowsroot", "at": Vector2(-8, 74)},
	]:
		var point: Vector2 = record.at
		forest_spawns.append({"mob": str(record.mob), "position": _ground(point.x, point.y)})


## Four crimson clone patrols hold the outer trails, away from the town's safe
## ring so the gate and the keepers stay a safe haven.
func _build_ranger_spawns() -> void:
	for point in [Vector2(-34, -8), Vector2(28, -52), Vector2(-12, -62), Vector2(46, 22)]:
		ranger_spawns.append({"position": _ground(point.x, point.y)})


func _reserved(point: Vector2, margin: float) -> bool:
	if maxf(absf(point.x), absf(point.y)) > 124.0:
		return true
	if _route_sample(point.x, point.y).x < margin:
		return true
	if point.distance_to(Vector2(0, 32)) < 29.0:
		return true
	if absf(point.x - 55.0) < 21.0 and absf(point.y + 60.0) < 21.0:
		return true
	if Vector2((point.x - 22.0) / 13.0, (point.y + 10.0) / 38.0).length() < 1.0:
		return true
	for entry in interactables:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 11.0:
			return true
	for entry in enemy_spawns:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 3.0:
			return true
	for entry in devil_spawns:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 4.5:
			return true
	for entry in forest_spawns:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 4.5:
			return true
	return false


func _build_woodland() -> void:
	_tree_variants.clear()
	_tree_species.clear()
	var species_list: Array = style.trees
	var total_weight := 0.0
	for species in species_list:
		total_weight += maxf(0.0, float(species.get("weight", 1.0)))
		_tree_species[String(species.get("id", ""))] = species
	var trunks: Dictionary = {}
	var leaves: Dictionary = {}
	var tree_count := 0
	for i in range(TREE_CANDIDATES):
		var point := Vector2(_rng.randf_range(-126, 126), _rng.randf_range(-126, 124))
		if _reserved(point, 6.5):
			continue
		# More open meadow in the south; dense woodland on the west and northern shoulders.
		if point.y > 45.0 and i % 3 != 0:
			continue
		var species: Dictionary = _pick_species(species_list, total_weight)
		if species.is_empty():
			continue
		var variants: Array = _variants_for(species)
		if variants.is_empty():
			continue
		var variant_index := _rng.randi_range(0, variants.size() - 1)
		var variant: Dictionary = variants[variant_index]
		var base := _ground(point.x, point.y)
		var scale_at := _rng.randf_range(0.86, 1.14)
		var xform := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_at), base)
		var key := "%s|%d" % [String(species["id"]), variant_index]
		if not trunks.has(key):
			trunks[key] = [] as Array[Dictionary]
			leaves[key] = [] as Array[Dictionary]
		(trunks[key] as Array[Dictionary]).append({
			"transform": xform,
			"color": _pick_color(species.get("bark_tints", []), Color.WHITE),
		})
		if variant.get("leaves") != null:
			(leaves[key] as Array[Dictionary]).append({
				"transform": xform,
				"color": _pick_color(species.get("tints", []), Color.WHITE),
			})
		# Trunk collision follows the authored trunk; crowns never block arrows.
		var tree_height: float = float(variant.get("height", 8.0)) * scale_at
		var trunk_spec: Vector2 = species.get("trunk", Vector2(0.04, 0.62))
		var trunk_height := maxf(1.4, tree_height * float(trunk_spec.y) * 0.95)
		var trunk_radius := maxf(0.16, tree_height * float(trunk_spec.x) * 1.04)
		var shape := CylinderShape3D.new()
		shape.radius = trunk_radius
		shape.height = trunk_height
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = base + Vector3(0, trunk_height * 0.5, 0)
		_add_solid(collision)
		tree_count += 1
	# Batch each species/variant pair once; WorldScatter splits it into 44 m chunks.
	var variant_total := 0
	for key in trunks.keys():
		var parts := String(key).split("|")
		var species: Dictionary = _tree_species.get(parts[0], {})
		var variants: Array = _tree_variants.get(parts[0], [])
		if species.is_empty() or variants.is_empty():
			continue
		var variant: Dictionary = variants[int(parts[1])]
		var label := String(parts[0]) + "_" + String(parts[1])
		WorldScatter.batch(self, "TreeTrunk_" + label, variant["trunk"],
			TextureLibrary.bark_material(String(variant["bark"])), trunks[key], TREE_CHUNK,
			{"cast_shadow": true})
		if variant.get("leaves") != null and not (leaves[key] as Array).is_empty():
			WorldScatter.batch(self, "TreeLeaves_" + label, variant["leaves"],
				TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]), variant["wind"]),
				leaves[key], TREE_CHUNK, {"cast_shadow": true})
	for values in _tree_variants.values():
		variant_total += (values as Array).size()
	generation_stats["trees"] = tree_count
	generation_stats["tree_instances"] = tree_count
	generation_stats["tree_variants"] = variant_total


func _build_backdrop_trees() -> void:
	# A high, uncollidable treeline closes the horizon above the enclosing hills.
	var pine: Dictionary = style.species_by_id("briar_pine")
	var oak: Dictionary = style.species_by_id("ironoak")
	if pine.is_empty() or oak.is_empty():
		return
	var pine_variants := _variants_for(pine)
	var oak_variants := _variants_for(oak)
	var pine_buckets: Dictionary = {}
	var oak_buckets: Dictionary = {}
	var placed := 0
	for i in range(BACKDROP_TREES):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(120.0, 143.0)
		var point := Vector2(cos(angle) * distance, sin(angle) * distance)
		var base := _ground(point.x, point.y)
		if base.y > 40.0 and i % 2 == 0:
			continue
		var use_oak := i % 3 == 0
		var variants: Array = oak_variants if use_oak else pine_variants
		if variants.is_empty():
			continue
		var variant_index := _rng.randi_range(0, variants.size() - 1)
		var bucket: Dictionary = oak_buckets if use_oak else pine_buckets
		if not bucket.has(variant_index):
			bucket[variant_index] = [] as Array[Dictionary]
		var species: Dictionary = oak if use_oak else pine
		var scale_at := _rng.randf_range(1.05, 1.55)
		var xform := Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_at), base)
		(bucket[variant_index] as Array[Dictionary]).append({
			"transform": xform,
			"color": _pick_color(species.get("tints", []), Color.WHITE),
		})
		placed += 1
	for bucket_info in [[pine, pine_variants, pine_buckets], [oak, oak_variants, oak_buckets]]:
		var species: Dictionary = bucket_info[0]
		var variants: Array = bucket_info[1]
		var buckets: Dictionary = bucket_info[2]
		for variant_index in buckets.keys():
			var variant: Dictionary = variants[int(variant_index)]
			var label := "%s_%d" % [String(species["id"]), int(variant_index)]
			WorldScatter.batch(self, "BackdropTrunk_" + label, variant["trunk"],
				TextureLibrary.bark_material(String(variant["bark"])), buckets[variant_index],
				TREE_CHUNK, {"cast_shadow": false})
			if variant.get("leaves") != null:
				WorldScatter.batch(self, "BackdropLeaves_" + label, variant["leaves"],
					TextureLibrary.foliage_material_tuned(String(variant["leaves_texture"]), variant["wind"]),
					buckets[variant_index], TREE_CHUNK, {"cast_shadow": false})
	generation_stats["backdrop_trees"] = placed


func _build_ground_cover() -> void:
	var counts: Dictionary = GrassField.build(self, style, _ground_point, _grass_reserved, GRASS_SEED)
	generation_stats["grass_instances"] = int(counts.get("grass", 0))
	generation_stats["flower_instances"] = int(counts.get("flowers", 0))
	generation_stats["fern_instances"] = int(counts.get("ferns", 0))
	generation_stats["ground_cover_chunks"] = int(counts.get("chunks", 0))


func _ground_point(point: Vector2) -> Vector3:
	return _ground(point.x, point.y)


func _grass_reserved(point: Vector2) -> bool:
	if maxf(absf(point.x), absf(point.y)) > 119.0:
		return true
	if _route_sample(point.x, point.y).x < 2.1:
		return true
	if Vector2((point.x - 22.0) / 11.5, (point.y + 10.0) / 35.5).length() < 1.02:
		return true
	if point.distance_to(Vector2(4, 35)) < 3.4:
		return true
	if point.distance_to(Vector2(-7, 28)) < 3.6:
		return true
	for house in [Vector2(-15, 42), Vector2(15, 42), Vector2(-15, 16), Vector2(15, 16)]:
		if point.distance_to(house) < 5.4:
			return true
	if absf(point.x - 55.0) < 18.0 and absf(point.y + 60.0) < 18.0:
		return true
	if point.distance_to(Vector2(-15, -100)) < 8.5:
		return true
	for entry in interactables:
		var location: Vector3 = entry["position"]
		if point.distance_to(Vector2(location.x, location.z)) < 2.6:
			return true
	return false


func _build_rocks() -> void:
	var variants: Array = []
	for index in range(3):
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 1.65
		mesh.radial_segments = 7
		mesh.rings = 4
		variants.append(mesh)
	var boulders: Array = [ [] as Array[Dictionary], [] as Array[Dictionary], [] as Array[Dictionary] ]
	var tints: Array = style.ground_cover.get("rocks", {}).get("tints", [])
	for i in range(72):
		var point := Vector2(_rng.randf_range(-124, 124), _rng.randf_range(-124, 112))
		if _reserved(point, 7.0):
			continue
		var base := _ground(point.x, point.y)
		var radius: float = _rng.randf_range(0.7, 2.1)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(
			radius * _rng.randf_range(0.95, 1.3),
			radius * _rng.randf_range(0.55, 0.9),
			radius * _rng.randf_range(0.95, 1.3)))
		var scale_y := basis.get_scale().y
		var xform := Transform3D(basis, base + Vector3(0, scale_y * 0.825, 0))
		var bucket: Array[Dictionary] = boulders[i % 3]
		bucket.append({"transform": xform, "color": _pick_color(tints, Color.WHITE)})
		var shape := SphereShape3D.new()
		shape.radius = maxf(basis.get_scale().x, basis.get_scale().z) * 0.92
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = xform.origin
		_add_solid(collision)
	for index in range(3):
		WorldScatter.batch(self, "Boulder_%d" % index, variants[index], _rock_material, boulders[index], 48.0,
			{"cast_shadow": true})
	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radius = 1.0
	pebble_mesh.height = 1.25
	pebble_mesh.radial_segments = 6
	pebble_mesh.rings = 3
	var pebble_tints: Array = style.ground_cover.get("pebbles", {}).get("tints", [])
	var pebbles: Array[Dictionary] = []
	for i in range(220):
		var point := Vector2(_rng.randf_range(-118, 118), _rng.randf_range(-118, 112))
		if _reserved(point, 4.5):
			continue
		var base := _ground(point.x, point.y)
		var size_at := _rng.randf_range(0.09, 0.28)
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(size_at, size_at * 0.7, size_at))
		pebbles.append({
			"transform": Transform3D(basis, base + Vector3(0, size_at * 0.44, 0)),
			"color": _pick_color(pebble_tints, Color.WHITE),
		})
	WorldScatter.batch(self, "Pebbles", pebble_mesh, _rock_material, pebbles, 32.0,
		{"visible_end": 52.0, "cast_shadow": false})
	generation_stats["rocks"] = 72


func _build_signposts() -> void:
	for entry in [
		[Vector2(3.8, 5), "HEARTWOOD  ←\nWATCHFALL  →"],
		[Vector2(-50, -57), "SUNCREST  ↑"],
		[Vector2(36, -13), "HEARTHSTEAD  ←"]
	]:
		var point: Vector2 = entry[0]
		var root := _root_at("TrailSign", _ground(point.x, point.y))
		_solid_box(root, Vector3(0.16, 2.8, 0.16), Vector3(0, 1.4, 0), _wood)
		Geo.box(root, Vector3(3.4, 1.0, 0.16), Vector3(0, 2.45, 0), _timber)
		var label := Label3D.new()
		label.text = String(entry[1])
		label.font_size = 34
		label.pixel_size = 0.0045
		label.modulate = Color("f6e4b0")
		label.position = Vector3(0, 2.45, 0.095)
		root.add_child(label)


func _variants_for(species: Dictionary) -> Array:
	var species_id := String(species.get("id", ""))
	if _tree_variants.has(species_id):
		return _tree_variants[species_id]
	var variants: Array = TreeKit.build_variants(species, TREE_SEED + _stable_seed(species_id))
	_tree_variants[species_id] = variants
	return variants


func _pick_species(species_list: Array, total_weight: float) -> Dictionary:
	if species_list.is_empty():
		return {}
	var roll := _rng.randf() * maxf(total_weight, 0.0001)
	for species in species_list:
		roll -= maxf(0.0, float(species.get("weight", 1.0)))
		if roll <= 0.0:
			return species
	return species_list[species_list.size() - 1]


func _pick_color(pool: Array, fallback: Color) -> Color:
	if pool.is_empty():
		return fallback
	return pool[_rng.randi_range(0, pool.size() - 1)]


static func _stable_seed(text: String) -> int:
	var value := 17
	for i in range(text.length()):
		value = (value * 31 + text.unicode_at(i)) & 0x7fffffff
	return value


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


## Records an obstacle's footprint. Every solid in the frontier is added
## through here, so the field cannot drift from the colliders the player feels.
func _add_solid(collision: CollisionShape3D) -> void:
	_solids.add_child(collision)
	_mark_nav(collision)


## Marks the cells covered by one solid, skipping anything a walking body would
## step under or over.
func _mark_nav(collision: CollisionShape3D) -> void:
	var shape := collision.shape
	if shape == null:
		return
	if _nav.is_empty():
		_nav.resize(NAV_SIDE * NAV_SIDE)
	var box: AABB = collision.transform * _shape_bounds(shape)
	if box.size == Vector3.ZERO:
		return
	var min_x := maxi(int(floor(box.position.x)) + NAV_HALF, 0)
	var max_x := mini(int(ceil(box.end.x)) + NAV_HALF, NAV_SIDE - 1)
	var min_z := maxi(int(floor(box.position.z)) + NAV_HALF, 0)
	var max_z := mini(int(ceil(box.end.z)) + NAV_HALF, NAV_SIDE - 1)
	for iz in range(min_z, max_z + 1):
		var z := float(iz - NAV_HALF) + 0.5
		for ix in range(min_x, max_x + 1):
			var x := float(ix - NAV_HALF) + 0.5
			var ground := terrain_height(x, z)
			if box.end.y <= ground + NAV_STEP_UP or box.position.y >= ground + NAV_HEAD:
				continue
			_nav[iz * NAV_SIDE + ix] = 1


## True when a body of `radius` centred here would overlap a marked cell.
func is_blocked(x: float, z: float, radius: float = 0.34) -> bool:
	if _nav.is_empty():
		return false
	var ix := int(floor(x)) + NAV_HALF
	var iz := int(floor(z)) + NAV_HALF
	if ix < 0 or iz < 0 or ix >= NAV_SIDE or iz >= NAV_SIDE:
		return true
	if _nav[iz * NAV_SIDE + ix] != 0:
		return true
	var reach := int(ceil(radius))
	# How far the body's centre sits from the centre of its own cell, so the
	# neighbour test is plain arithmetic: this runs a few times per mob per
	# second, and a `Vector2` per candidate cell is the difference between a
	# cheap test and an allocation.
	var span := (radius + 0.71) * (radius + 0.71)
	var offset_x := float(ix - NAV_HALF) + 0.5 - x
	var offset_z := float(iz - NAV_HALF) + 0.5 - z
	for dz in range(-reach, reach + 1):
		var near_z := offset_z + float(dz)
		for dx in range(-reach, reach + 1):
			if dx == 0 and dz == 0:
				continue
			var nx := ix + dx
			var nz := iz + dz
			if nx < 0 or nz < 0 or nx >= NAV_SIDE or nz >= NAV_SIDE:
				return true
			if _nav[nz * NAV_SIDE + nx] == 0:
				continue
			# Only a cell the body's disc actually reaches blocks it.
			var near_x := offset_x + float(dx)
			if near_x * near_x + near_z * near_z <= span:
				return true
	return false


## Local-space bounds of the shapes this world builds. `Shape3D` has no public
## `get_rect`, so each type answers for itself; anything else is skipped rather
## than guessed at.
func _shape_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var half := Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
		return AABB(-half, half * 2.0)
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		return AABB(-Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var reach := Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
		return AABB(-reach, reach * 2.0)
	return AABB()
