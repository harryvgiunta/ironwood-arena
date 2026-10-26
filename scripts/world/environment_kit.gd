class_name WorldEnvironmentKit
extends RefCounted
## Builds the authored sky, global environment and shadow-casting sun for a style.
##
## The panorama is a photorealistic equirectangular sky whose sun disc and
## aureole are authored at the key light's actual direction, so shadows and the
## visible sun agree. Fog is tinted to the same horizon haze. All values come
## from `style.sky` so frontier and arena share one code path.
##
## Compatibility note: sky ambient was probed on this project's GL Compatibility
## build (panorama sky, ambient source SKY): a white rough probe sphere is lit and
## tinted, so styles that ask for sky ambient get it. The authored
## `ambient_color`/`ambient_energy` always travel with the environment as a
## fallback for styles that opt out (or a renderer where sky radiance is black).

static func build(parent: Node3D, style: WorldStyle) -> Dictionary:
	var result := {"world_environment": null, "environment": null, "sun": null}
	if parent == null or style == null:
		return result
	var sky_values: Dictionary = style.sky

	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = TextureLibrary.texture(String(sky_values.get("texture", "sky_frontier")))
	panorama.energy_multiplier = float(sky_values.get("energy", 1.0))
	var sky := Sky.new()
	sky.sky_material = panorama
	# Static panorama: automatic processing refreshes radiance only when the
	# material changes, which is exactly what a fixed sky needs.
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.background_energy_multiplier = 1.0
	# Sky reflections are neither needed nor cheap for matte world art; the water
	# shader fakes its sky fresnel from colour.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED

	var use_sky_ambient := bool(sky_values.get("use_sky_ambient", true))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if use_sky_ambient else Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = sky_values.get("ambient_color", Color("bed1d1"))
	environment.ambient_light_energy = float(sky_values.get("ambient_energy", 0.5))
	environment.ambient_light_sky_contribution = 1.0 if use_sky_ambient else 0.0

	var fog_density := float(sky_values.get("fog_density", 0.0))
	if fog_density > 0.0:
		environment.fog_enabled = true
		environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		environment.fog_light_color = sky_values.get("fog_color", Color("c5d0bd"))
		environment.fog_light_energy = 0.9
		environment.fog_density = fog_density
		environment.fog_sun_scatter = float(sky_values.get("fog_sun_scatter", 0.25))
		environment.fog_sky_affect = float(sky_values.get("fog_sky_affect", 0.12))
		environment.fog_aerial_perspective = float(sky_values.get("fog_aerial_perspective", 0.35))

	environment.tonemap_mode = sky_values.get("tonemap", Environment.TONE_MAPPER_FILMIC)
	environment.tonemap_exposure = float(sky_values.get("exposure", 1.0))
	environment.adjustment_enabled = true
	environment.adjustment_saturation = float(sky_values.get("saturation", 1.0))
	environment.adjustment_contrast = float(sky_values.get("contrast", 1.0))
	environment.adjustment_brightness = 1.0

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "WorldSun"
	sun.rotation_degrees = sky_values.get("sun_rotation", Vector3(-48.0, -32.0, 0.0))
	sun.light_color = sky_values.get("sun_color", Color("ffe2b3"))
	sun.light_energy = float(sky_values.get("sun_energy", 1.0))
	sun.shadow_enabled = true
	# Four splits give crisp trunk shadows near the player and still cover the
	# whole draw distance; the visibility budget only shadows trees/props.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Four splits over this range. It used to reach a hundred and ten metres,
	# which cost a fifth of the frame's draw calls on shadow pass geometry
	# nobody can pick out past the treeline; sixty still covers every weapon's
	# useful range and the whole town square.
	sun.directional_shadow_max_distance = float(sky_values.get("sun_shadow_distance", 60.0))
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.0
	parent.add_child(sun)

	result["world_environment"] = world_environment
	result["environment"] = environment
	result["sun"] = sun
	return result
