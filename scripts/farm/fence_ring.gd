@tool
extends Node2D
## The fence round the farm: four sides of rails with posts at even spacing.
##
## The fence used to be four tiled strips, one per side. Tiling a strip leaves
## its posts wherever the 64-pixel pattern happens to fall, so the sides never
## met cleanly at the corners. Here the corners are posts by definition: each
## side gets the whole number of gaps closest to POST_SPACING, and the posts are
## spaced evenly between its two corner posts. The rail sprites are centred on
## pixel (32, 32) and the post stands on the same point, so a horizontal side, a
## vertical side and their shared corner post all line up exactly.
##
## Drawn in the editor too (@tool), so moving the corners is a drag in the
## Inspector.

const RAIL_H := preload("res://assets/environment/fence_horizontal.png")
const RAIL_V := preload("res://assets/environment/fence_vertical.png")
const POST := preload("res://assets/environment/fence_post.png")
## Half the sprite size: every fence sprite is drawn centred on its point.
const HALF := Vector2(32, 32)

## Centre of the top-left corner post, in farm pixels.
@export var top_left := Vector2(112, 192):
	set(value):
		top_left = value
		queue_redraw()
## Centre of the bottom-right corner post.
@export var bottom_right := Vector2(1172, 576):
	set(value):
		bottom_right = value
		queue_redraw()
## Roughly how far apart the posts stand.
@export var post_spacing := 64.0:
	set(value):
		post_spacing = maxf(value, 16.0)
		queue_redraw()


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


## Every post position, corners included, top side first so posts further
## down the screen are drawn over the ones behind them.
func post_positions() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var top_right := Vector2(bottom_right.x, top_left.y)
	var bottom_left := Vector2(top_left.x, bottom_right.y)
	_add_side(points, top_left, top_right)
	_add_side(points, top_left, bottom_left)
	_add_side(points, top_right, bottom_right)
	_add_side(points, bottom_left, bottom_right)
	var unique: Array[Vector2] = []
	for point in points:
		if not unique.any(func(other: Vector2) -> bool: return other.is_equal_approx(point)):
			unique.append(point)
	unique.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return unique


func _add_side(points: Array[Vector2], from: Vector2, to: Vector2) -> void:
	var gaps := maxi(1, int(round(from.distance_to(to) / post_spacing)))
	for index in range(gaps + 1):
		points.append(from.lerp(to, float(index) / gaps).round())


func _draw() -> void:
	var left := top_left.x
	var right := bottom_right.x
	var top := top_left.y
	var bottom := bottom_right.y
	# Rails first: the back (top) side, both sides, then the front (bottom).
	draw_texture_rect(RAIL_H, Rect2(Vector2(left, top) - HALF + Vector2(HALF.x, 0),
		Vector2(right - left, HALF.y * 2.0)), true)
	for x in [left, right]:
		draw_texture_rect(RAIL_V, Rect2(Vector2(x, top) - HALF + Vector2(0, HALF.y),
			Vector2(HALF.x * 2.0, bottom - top)), true)
	draw_texture_rect(RAIL_H, Rect2(Vector2(left, bottom) - HALF + Vector2(HALF.x, 0),
		Vector2(right - left, HALF.y * 2.0)), true)
	for point in post_positions():
		draw_texture(POST, point - HALF)
