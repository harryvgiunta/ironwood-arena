class_name WorldStyle
extends RefCounted
## Presentation-only description of a world region (frontier / arena).
##
## Everything the world-art framework needs to build scenery is data: sky, ground
## blending, tree species, grass, ground cover and building materials. It is
## deliberately free of nodes and resources so a scene can clone/modify a style
## without touching the builders.
##
## Extending:
## - Add a species to `default_trees()` (or append one in a scene). Required keys are
##   documented on `_species()` below; `TreeKit` only reads those keys.
## - Add texture ids here; `TextureLibrary` resolves `res://assets/world/textures/<id>.png`.
## - Per-region tweaks belong in `frontier()` / `arena()` rather than in builders.

var id: String = ""
var sky: Dictionary = {}
var ground: Dictionary = {}
var trees: Array[Dictionary] = []
var grass: Dictionary = {}
var ground_cover: Dictionary = {}
var props: Dictionary = {}


## Returns the built-in species library. Scenes may copy this array and append
## custom species; weights are relative spawn weights, not percentages.
static func default_trees() -> Array[Dictionary]:
	return [
		_species({
			"id": "ironoak",
			"form": "broadleaf",
			"bark": "bark_oak",
			"leaves": "leaves_broadleaf",
			"height": Vector2(10.0, 15.0),
			# trunk = (base radius / height, trunk height / total height)
			"trunk": Vector2(0.046, 0.60),
			# crown = (crown radius / height, crown height / total height)
			"crown": Vector2(0.30, 0.50),
			"weight": 1.35,
			"tints": [Color("e8f2c0"), Color("d3e6a4"), Color("f8fae0"), Color("c6df98")],
			"bark_tints": [Color.WHITE, Color("f5eadc"), Color("e8d8c2")],
			"wind": Vector2(0.20, 1.0),
			"variants": 4,
		}),
		_species({
			"id": "briar_pine",
			"form": "conifer",
			"bark": "bark_pine",
			"leaves": "needles_pine",
			"height": Vector2(9.0, 16.0),
			"trunk": Vector2(0.034, 0.97),
			"crown": Vector2(0.24, 0.74),
			"weight": 1.15,
			"tints": [Color("cbe2ac"), Color("b6d49a"), Color("dcebc0"), Color("a6c78e")],
			"bark_tints": [Color("e8d3c0"), Color.WHITE, Color("d6bfa9")],
			"wind": Vector2(0.08, 0.8),
			"variants": 4,
		}),
		_species({
			"id": "silver_birch",
			"form": "birch",
			"bark": "bark_birch",
			"leaves": "leaves_birch",
			"height": Vector2(7.0, 11.0),
			"trunk": Vector2(0.024, 0.78),
			"crown": Vector2(0.20, 0.42),
			"weight": 0.75,
			"tints": [Color("eaf6c6"), Color("d8eab4"), Color("f6fae0"), Color("c9e6a2")],
			"bark_tints": [Color.WHITE, Color("f4f0e6"), Color("e6e2d6")],
			"wind": Vector2(0.24, 1.15),
			"variants": 3,
		}),
		_species({
			"id": "amber_rowan",
			"form": "broadleaf",
			"bark": "bark_oak",
			"leaves": "leaves_amber",
			"height": Vector2(6.0, 9.5),
			"trunk": Vector2(0.042, 0.56),
			"crown": Vector2(0.32, 0.54),
			"weight": 0.62,
			"tints": [Color("f8dca4"), Color("f0c88c"), Color("fcebc0"), Color("eab470")],
			"bark_tints": [Color("f1dfca"), Color.WHITE, Color("e5d0b8")],
			"wind": Vector2(0.18, 1.05),
			"variants": 3,
		}),
		_species({
			"id": "hollow_snag",
			"form": "snag",
			"bark": "bark_dead",
			"leaves": "",
			"height": Vector2(5.0, 9.0),
			"trunk": Vector2(0.052, 0.92),
			"crown": Vector2(0.12, 0.20),
			"weight": 0.38,
			"tints": [],
			"bark_tints": [Color("e8e6dc"), Color("d6d4ca"), Color.WHITE],
			"wind": Vector2(0.05, 0.7),
			"variants": 3,
		}),
	]


## Warm, sunlit woodland frontier. The palette pushes yellow-green grass and
## amber accents under a natural blue sky with a pale horizon haze.
static func frontier() -> WorldStyle:
	var style := WorldStyle.new()
	style.id = "frontier"
	style.sky = {
		"texture": "sky_frontier",
		"energy": 0.8,
		"sun_rotation": Vector3(-48.0, -32.0, 0.0),
		"sun_color": Color("ffe2b3"),
		"sun_energy": 1.05,
		"sun_shadow_distance": 60.0,
		"ambient_color": Color("c6d3dd"),
		"ambient_energy": 0.52,
		"use_sky_ambient": true,
		"fog_color": Color("c9d2d8"),
		"fog_density": 0.0022,
		"fog_sun_scatter": 0.25,
		"fog_sky_affect": 0.12,
		"fog_aerial_perspective": 0.35,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"exposure": 0.85,
		"saturation": 1.28,
		"contrast": 1.07,
	}
	style.ground = {
		"grass_texture": "terrain_grass",
		"dirt_texture": "terrain_dirt",
		"rock_texture": "terrain_rock",
		"macro_texture": "terrain_macro",
		"tile": 7.0,
		"dirt_tile": 6.0,
		"rock_tile": 5.0,
		"macro_tile": 27.0,
		"grass_tint": Color("b9c98a"),
		"dirt_tint": Color("c9ae86"),
		"rock_tint": Color("a9a89c"),
		"detail_strength": 1.0,
		"detail_fade": Vector2(95.0, 150.0),
	}
	style.trees = default_trees()
	style.grass = {
		"texture": "grass_meadow",
		"count": 18000,
		"range": 72.0,
		"chunk_size": 20.0,
		"radius": 118.0,
		"tints": [Color("c8dc96"), Color("b6d086"), Color("dde8aa"), Color("a5c47c"), Color("d5d58e")],
		"shade_tint": Color("6f8b4e"),
		"wind": Vector2(0.10, 1.2),
		"density_falloff": Vector2(1.0, 0.42),
		"max_slope": 30.0,
		"height_range": Vector2(-0.6, 400.0),
		"scale": Vector2(0.75, 1.4),
		"clump_variants": 3,
	}
	style.ground_cover = {
		"flowers": {
			"texture": "flowers", "count": 1400, "range": 62.0, "chunk_size": 16.0,
			"radius": 116.0, "scale": Vector2(0.6, 1.15), "wind": Vector2(0.07, 1.1),
			"max_slope": 26.0, "height_range": Vector2(-0.4, 400.0),
			"tints": [Color("f0e2a6"), Color("e8b4c6"), Color("b9c7ef"), Color("f3c98f"), Color.WHITE],
			"shade_tint": Color("80906a"),
		},
		"ferns": {
			"texture": "fern", "count": 900, "range": 56.0, "chunk_size": 20.0,
			"radius": 118.0, "scale": Vector2(0.7, 1.35), "wind": Vector2(0.06, 1.0),
			"max_slope": 34.0, "height_range": Vector2(-0.3, 400.0),
			"tints": [Color("c4dda0"), Color("a9c985"), Color("dcebb8")],
			"shade_tint": Color("5f7b48"),
		},
		# Rocks/pebbles are presentation-only props: scenes place them through
		# WorldScatter with TextureLibrary.rock_material(). GrassField intentionally
		# ignores these entries so it only returns grass/flower/fern counts.
		"rocks": {
			"texture": "rock", "count": 90, "range": 80.0, "chunk_size": 24.0,
			"radius": 120.0, "scale": Vector2(0.6, 2.0), "y_scale": Vector2(0.4, 0.9),
			"tints": [Color.WHITE, Color("cfd6c8"), Color("bcc4b6")],
		},
		"pebbles": {
			"texture": "rock", "count": 150, "range": 45.0, "chunk_size": 16.0,
			"radius": 118.0, "scale": Vector2(0.12, 0.34), "y_scale": Vector2(0.5, 0.8),
			"tints": [Color("ded8c8"), Color("c4beac"), Color.WHITE],
		},
	}
	style.props = {
		"kinds": {
			"wood": "wood_planks",
			"timber": "timber",
			"plaster": "plaster",
			"roof": "roof_shingles",
			"stone": "stone_blocks",
		},
		# Triplanar repeats per metre for each kind.
		"scale": {"wood": 0.6, "timber": 0.75, "plaster": 0.4, "roof": 0.9, "stone": 0.55},
		"tints": {
			"wood": Color("d9c39d"),
			"timber": Color("b9a58a"),
			"plaster": Color("f4edcf"),
			"roof": Color("d8b8a4"),
			"stone": Color("d7d9cd"),
		},
	}
	return style


## Arena: the same painted palette, lifted a stop brighter with a clearer,
## cooler haze so duels read against the field.
static func arena() -> WorldStyle:
	var style := WorldStyle.new()
	style.id = "arena"
	style.sky = {
		"texture": "sky_frontier",
		"energy": 0.85,
		"sun_rotation": Vector3(-50.0, -30.0, 0.0),
		"sun_color": Color("ffe8c2"),
		"sun_energy": 1.12,
		"sun_shadow_distance": 55.0,
		"ambient_color": Color("cfdae1"),
		"ambient_energy": 0.54,
		"use_sky_ambient": true,
		"fog_color": Color("d2dbe0"),
		"fog_density": 0.0014,
		"fog_sun_scatter": 0.2,
		"fog_sky_affect": 0.08,
		"fog_aerial_perspective": 0.25,
		"tonemap": Environment.TONE_MAPPER_FILMIC,
		"exposure": 0.9,
		"saturation": 1.24,
		"contrast": 1.06,
	}
	style.ground = {
		"grass_texture": "terrain_grass",
		"dirt_texture": "terrain_dirt",
		"rock_texture": "terrain_rock",
		"macro_texture": "terrain_macro",
		"tile": 6.0,
		"dirt_tile": 6.0,
		"rock_tile": 5.0,
		"macro_tile": 22.0,
		"grass_tint": Color("c2d492"),
		"dirt_tint": Color("d2b78c"),
		"rock_tint": Color("b4b3a6"),
		"detail_strength": 0.9,
		"detail_fade": Vector2(70.0, 120.0),
	}
	style.trees = default_trees()
	style.grass = {
		"texture": "grass_meadow",
		"count": 2600,
		"range": 64.0,
		"chunk_size": 16.0,
		"radius": 34.0,
		"tints": [Color("d2e29e"), Color("bedc8e"), Color("e6f0b4"), Color("afd082")],
		"shade_tint": Color("7b9558"),
		"wind": Vector2(0.09, 1.15),
		"density_falloff": Vector2(1.0, 0.55),
		"max_slope": 12.0,
		"height_range": Vector2(-0.6, 40.0),
		"scale": Vector2(0.8, 1.35),
		"clump_variants": 3,
	}
	style.ground_cover = {
		"flowers": {
			"texture": "flowers", "count": 240, "range": 48.0, "chunk_size": 16.0,
			"radius": 32.0, "scale": Vector2(0.6, 1.0), "wind": Vector2(0.06, 1.0),
			"max_slope": 12.0, "height_range": Vector2(-0.4, 40.0),
			"tints": [Color("f0e2a6"), Color("e8b4c6"), Color("b9c7ef"), Color.WHITE],
			"shade_tint": Color("80906a"),
		},
		"ferns": {
			"texture": "fern", "count": 140, "range": 44.0, "chunk_size": 16.0,
			"radius": 33.0, "scale": Vector2(0.7, 1.1), "wind": Vector2(0.05, 0.9),
			"max_slope": 12.0, "height_range": Vector2(-0.4, 40.0),
			"tints": [Color("c4dda0"), Color("a9c985")],
			"shade_tint": Color("5f7b48"),
		},
		"rocks": {
			"texture": "rock", "count": 26, "range": 60.0, "chunk_size": 24.0,
			"radius": 34.0, "scale": Vector2(0.6, 1.8), "y_scale": Vector2(0.4, 0.8),
			"tints": [Color.WHITE, Color("cfd6c8")],
		},
		"pebbles": {
			"texture": "rock", "count": 60, "range": 40.0, "chunk_size": 16.0,
			"radius": 33.0, "scale": Vector2(0.12, 0.3), "y_scale": Vector2(0.5, 0.8),
			"tints": [Color("ded8c8"), Color.WHITE],
		},
	}
	style.props = {
		"kinds": {
			"wood": "wood_planks",
			"timber": "timber",
			"plaster": "plaster",
			"roof": "roof_shingles",
			"stone": "stone_blocks",
		},
		"scale": {"wood": 0.6, "timber": 0.75, "plaster": 0.4, "roof": 0.9, "stone": 0.55},
		"tints": {
			"wood": Color("e2cda8"),
			"timber": Color("c4b097"),
			"plaster": Color("f7f0d6"),
			"roof": Color("dfc2ad"),
			"stone": Color("e0e2d6"),
		},
	}
	return style


## Convenience lookup for scenes that spawn by species id.
func species_by_id(species_id: String) -> Dictionary:
	for entry in trees:
		if String(entry.get("id", "")) == species_id:
			return entry
	return {}


static func _species(values: Dictionary) -> Dictionary:
	var entry := {
		"id": "",
		"form": "broadleaf",
		"bark": "bark_oak",
		"leaves": "",
		"height": Vector2(8.0, 12.0),
		"trunk": Vector2(0.04, 0.62),
		"crown": Vector2(0.28, 0.5),
		"weight": 1.0,
		"tints": [] as Array[Color],
		"bark_tints": [] as Array[Color],
		"wind": Vector2(0.15, 1.0),
		"variants": 3,
	}
	entry.merge(values, true)
	entry["tints"] = _colours(entry["tints"])
	entry["bark_tints"] = _colours(entry["bark_tints"])
	return entry


static func _colours(values: Array) -> Array[Color]:
	var result: Array[Color] = []
	for value in values:
		result.append(value as Color)
	return result
