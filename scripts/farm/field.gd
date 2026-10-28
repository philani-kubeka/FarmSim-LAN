extends Node2D
## The plot: a grid of crop tiles, plus the aggregate numbers a scenario needs.
##
## The grid itself is authored in field.tscn - one instance of crop_tile.tscn per
## cell - so the plot can be opened in the editor, a tile moved, or the whole
## field re-skinned by editing the tile scene once. build() adopts those authored
## tiles and names them by their grid coordinate; it only creates or removes
## tiles if Config's grid size has been changed since the scene was saved, so
## retuning FIELD_COLUMNS / FIELD_ROWS still works without re-authoring.

const CropTile := preload("res://scripts/farm/crop_tile.gd")
const TILE_SCENE := preload("res://scenes/farm/crop_tile.tscn")

var tiles: Array = []          # flat array, row-major
var columns := 0
var rows := 0


func build(tile_columns: int = Config.FIELD_COLUMNS, tile_rows: int = Config.FIELD_ROWS) -> void:
	tiles.clear()
	columns = tile_columns
	rows = tile_rows
	var size := float(Config.TILE_SIZE)
	var authored := get_children()
	var index := 0
	for row in range(rows):
		for column in range(columns):
			var tile: Node2D
			if index < authored.size():
				tile = authored[index] as Node2D
			else:
				tile = TILE_SCENE.instantiate()
				add_child(tile)
			tile.setup(column, row)
			tile.position = Vector2((column + 0.5) * size, (row + 0.5) * size)
			tiles.append(tile)
			index += 1
	# Anything left over is a tile the authored scene has but the configured
	# grid no longer needs.
	for surplus in range(index, authored.size()):
		authored[surplus].queue_free()


func tile_at(column: int, row: int) -> Node2D:
	if column < 0 or column >= columns or row < 0 or row >= rows:
		return null
	return tiles[row * columns + column]


## Pixel rectangle the field occupies, in this node's local space.
func local_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(columns, rows) * float(Config.TILE_SIZE))


## Nearest tile to a global point, or null if nothing is within `max_distance`.
func tile_near(global_point: Vector2, max_distance: float) -> Node2D:
	var local_point := to_local(global_point)
	var size := float(Config.TILE_SIZE)
	var column := int(floor(local_point.x / size))
	var row := int(floor(local_point.y / size))
	var best: Node2D = null
	var best_distance := max_distance
	# Check the containing cell and its neighbours, so standing on an edge still
	# reaches the tile the player is clearly next to.
	for row_offset in range(-1, 2):
		for column_offset in range(-1, 2):
			var candidate := tile_at(column + column_offset, row + row_offset)
			if candidate == null:
				continue
			var distance := candidate.global_position.distance_to(global_point)
			if distance <= best_distance:
				best_distance = distance
				best = candidate
	return best


func simulate(delta: float, context: Dictionary) -> void:
	for tile in tiles:
		tile.simulate(delta, context)


# ------------------------------------------------------------------ counts --

func count_where(predicate: Callable) -> int:
	var total := 0
	for tile in tiles:
		if predicate.call(tile):
			total += 1
	return total


func planted_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.is_planted())


func tilled_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.state == CropTile.State.TILLED)


func mature_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.state == CropTile.State.MATURE)


func harvested_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.state == CropTile.State.HARVESTED)


func dead_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.state == CropTile.State.DEAD)


func stressed_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.is_stressed())


func infested_count() -> int:
	return count_where(func(tile: Node2D) -> bool: return tile.infested)


## Everything the field produced this season, across every cycle.
func total_yield() -> float:
	var total := 0.0
	for tile in tiles:
		total += tile.lifetime_yield
	return total


## Number of harvests taken, which can exceed the tile count if tiles were
## re-worked during a long season.
func total_harvests() -> int:
	var total := 0
	for tile in tiles:
		total += tile.harvest_count
	return total


## Crops that were taken off dead. Standing dead tiles are counted separately.
func total_failed_cycles() -> int:
	var total := 0
	for tile in tiles:
		total += tile.failed_cycles
	return total


## Distinct tiles that were sown at least once.
func sown_tiles() -> int:
	var total := 0
	for tile in tiles:
		if tile.ever_sown:
			total += 1
	return total


## Average condition across every crop that reached an outcome this season -
## harvested, or dead. A crop that died counts as zero rather than being left out
## of the average, otherwise a season that lost three tiles scores the same as
## one that saved them. Crops still in the ground are not counted: they have not
## finished yet.
func average_condition_at_harvest() -> float:
	var outcomes := 0
	var condition := 0.0
	for tile in tiles:
		outcomes += tile.harvest_count + tile.failed_cycles
		condition += tile.lifetime_condition_sum
		if tile.state == CropTile.State.DEAD:
			outcomes += 1
	if outcomes > 0:
		return condition / float(outcomes)
	return average_health_of_crops()


## Average condition across every tile that was sown this season, including the
## ones already harvested. Harvested tiles keep the condition they were in when
## they were taken off, so the number still means something at the end of a
## season where everything has been brought in.
func average_health_of_crops() -> float:
	var total := 0.0
	var count := 0
	for tile in tiles:
		var was_sown: bool = tile.is_planted() \
			or tile.state == CropTile.State.DEAD \
			or (tile.state == CropTile.State.HARVESTED and tile.crop != Config.CropType.NONE)
		if was_sown:
			total += tile.health
			count += 1
	return 0.0 if count == 0 else total / float(count)


## Planted tiles that could still be infested, used by the pest event.
func plantable_targets() -> Array:
	var out: Array = []
	for tile in tiles:
		if tile.is_planted() and not tile.infested:
			out.append(tile)
	return out


## Orthogonal neighbours of a tile, used when a pest outbreak spreads.
func neighbours_of(tile: Node2D) -> Array:
	var out: Array = []
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour := tile_at(tile.column + offset.x, tile.row + offset.y)
		if neighbour != null:
			out.append(neighbour)
	return out


func records() -> Array:
	var out: Array = []
	for tile in tiles:
		if tile.state != CropTile.State.GRASS:
			out.append(tile.to_record())
	return out
