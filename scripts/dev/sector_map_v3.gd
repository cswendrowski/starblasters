extends Node2D

# Sector Map V3 — blank canvas with a labelled 16×16 px grid.
# 480×270 viewport → 30 cols × 16 rows of full cells.
# Columns: 0–29 (left→right). Rows: 0–15 (top→bottom).
# Every 4th line is drawn heavier to create visible 64×64 px blocks.
# Escape → dev menu.

const FONT           = preload("res://graphics/fonts/PixelOperator.ttf")
const SceneTransition = preload("res://scripts/scene_transition.gd")

const CELL     := 16
const COLS     := 30   # 480 / 16
const ROWS     := 16   # 270 / 16  (last row ends exactly at y=256; 14px stub below)

const BG_COLOR    := Color(0.06, 0.07, 0.10, 1.0)
const GRID_MINOR  := Color(0.22, 0.27, 0.35, 0.55)
const GRID_MAJOR  := Color(0.35, 0.43, 0.58, 0.85)  # every 4 cells
const LABEL_COLOR := Color(0.32, 0.42, 0.58, 0.50)
const FONT_SIZE   := 5


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 480, 270), BG_COLOR)

	# Vertical lines
	for col in range(COLS + 1):
		var x := col * CELL
		var major := col % 4 == 0
		draw_line(Vector2(x, 0), Vector2(x, 270),
			GRID_MAJOR if major else GRID_MINOR, 1.0)

	# Horizontal lines
	for row in range(ROWS + 1):
		var y := row * CELL
		var major := row % 4 == 0
		draw_line(Vector2(0, y), Vector2(480, y),
			GRID_MAJOR if major else GRID_MINOR, 1.0)

	# Cell coordinate labels — drawn at top-left corner of each cell
	for col in COLS:
		for row in ROWS:
			var pos := Vector2(col * CELL + 2, row * CELL + FONT_SIZE + 1)
			draw_string(FONT, pos, "%d,%d" % [col, row],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneTransition.change_scene(get_tree(), "res://scenes/dev_menu.tscn")
