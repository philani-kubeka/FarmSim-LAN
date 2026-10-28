extends RefCounted
## Single lookup point for every sprite in the prototype.
##
## Textures are fetched by key rather than by literal path, so a missing or
## unimported image produces one clear warning and a visible magenta placeholder
## instead of a null texture that silently draws nothing. The test suite walks
## every key in PATHS and asserts that each one resolves.

const PATHS := {
	# environment
	"grass": "res://assets/environment/grass.png",
	"soil": "res://assets/environment/soil.png",
	"tilled": "res://assets/environment/tilled.png",
	"tile_border": "res://assets/environment/tile_border.png",
	"well": "res://assets/environment/well.png",
	"fence_h": "res://assets/environment/fence_horizontal.png",
	"fence_v": "res://assets/environment/fence_vertical.png",
	"fence_post": "res://assets/environment/fence_post.png",

	# crops
	"maize_1": "res://assets/crops/maize_1.png",
	"maize_2": "res://assets/crops/maize_2.png",
	"maize_3": "res://assets/crops/maize_3.png",
	"maize_4": "res://assets/crops/maize_4.png",
	"beans_1": "res://assets/crops/beans_1.png",
	"beans_2": "res://assets/crops/beans_2.png",
	"beans_3": "res://assets/crops/beans_3.png",
	"beans_4": "res://assets/crops/beans_4.png",
	"stubble": "res://assets/crops/stubble.png",

	# characters
	"player_1": "res://assets/characters/player_1.png",
	"player_2": "res://assets/characters/player_2.png",

	# tools
	"tool_hoe": "res://assets/tools/hoe.png",
	"tool_seed": "res://assets/tools/seed.png",
	"tool_water": "res://assets/tools/water.png",
	"tool_inspect": "res://assets/tools/inspect.png",
	"tool_treat": "res://assets/tools/treat.png",
	"tool_harvest": "res://assets/tools/harvest.png",

	# effects and indicators
	"pest": "res://assets/effects/pest.png",
	"warning": "res://assets/effects/warning.png",
	"alert": "res://assets/effects/alert.png",
	"drop": "res://assets/effects/drop.png",
	"drought": "res://assets/effects/drought.png",
}

static var _cache: Dictionary = {}
static var _placeholder: Texture2D = null


static func texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path: String = PATHS.get(key, "")
	var result: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		result = load(path) as Texture2D
	if result == null:
		push_warning("AssetLibrary: no texture for key '%s' (%s)" % [key, path])
		result = placeholder()
	_cache[key] = result
	return result


## Bright magenta square, so a missing sprite is impossible to miss on screen.
static func placeholder() -> Texture2D:
	if _placeholder != null:
		return _placeholder
	var image := Image.create(Config.TILE_SIZE, Config.TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 1.0, 1.0))
	_placeholder = ImageTexture.create_from_image(image)
	return _placeholder


static func crop_stage_key(crop: int, stage: int) -> String:
	var stem := "maize" if crop == Config.CropType.MAIZE else "beans"
	return "%s_%d" % [stem, clampi(stage, 1, 4)]


static func tool_key(tool_id: int) -> String:
	match tool_id:
		Config.Tool.HOE:
			return "tool_hoe"
		Config.Tool.SEED:
			return "tool_seed"
		Config.Tool.WATER:
			return "tool_water"
		Config.Tool.INSPECT:
			return "tool_inspect"
		Config.Tool.TREAT:
			return "tool_treat"
		Config.Tool.HARVEST:
			return "tool_harvest"
		_:
			return "tool_hoe"


## Clears the cache. Only used by tests.
static func reset() -> void:
	_cache.clear()
