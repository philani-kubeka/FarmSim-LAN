extends "res://tests/farm_sim_test.gd"
## Every sprite the prototype asks for has to exist and import. A missing
## texture is silent at runtime except for a warning, so it gets its own test.

const AssetLibrary := preload("res://scripts/farm/asset_library.gd")


func run() -> void:
	AssetLibrary.reset()
	var placeholder := AssetLibrary.placeholder()

	for key in AssetLibrary.PATHS.keys():
		var path: String = AssetLibrary.PATHS[key]
		check(ResourceLoader.exists(path), "asset file exists and is imported: %s" % path)
		var texture: Texture2D = AssetLibrary.texture(key)
		check(texture != null, "texture loads for key '%s'" % key)
		check(texture != placeholder, "key '%s' resolves to a real sprite, not the placeholder" % key)
		if texture != null and texture != placeholder:
			check(texture.get_width() > 0 and texture.get_height() > 0,
				"sprite '%s' has a non-zero size" % key)

	# Ground tiles must match the tile size the field is laid out with, otherwise
	# the grid will not line up.
	for key in ["grass", "soil", "tilled", "tile_border"]:
		var texture: Texture2D = AssetLibrary.texture(key)
		if texture == null:
			continue
		check_equal(texture.get_width(), Config.TILE_SIZE, "'%s' is one tile wide" % key)
		check_equal(texture.get_height(), Config.TILE_SIZE, "'%s' is one tile tall" % key)

	# Every tool a role can carry needs an icon.
	for role in Config.ROLE_TOOLS.keys():
		for tool_id in (Config.ROLE_TOOLS[role] as Array):
			var key := AssetLibrary.tool_key(tool_id)
			check(AssetLibrary.PATHS.has(key),
				"tool '%s' carried by the %s has an icon" % [Config.tool_label(tool_id), role])

	# Every crop growth stage the tile can display needs a sprite.
	for crop in [Config.CropType.MAIZE, Config.CropType.BEANS]:
		for stage in range(1, 5):
			var key := AssetLibrary.crop_stage_key(crop, stage)
			check(AssetLibrary.PATHS.has(key),
				"%s growth stage %d has a sprite" % [Config.crop_name(crop), stage])

	# The generator that produced the pack ships with the project, so the pack
	# can be audited and regenerated.
	check(FileAccess.file_exists("res://tools/generate_assets.py"),
		"the asset generator is committed alongside the sprites")
	check(FileAccess.file_exists("res://ASSET_SOURCES.md"),
		"the asset source record exists")
