extends Node2D

# Annotated grid overlay extracted from the deleted dev/sector_map_v3 scene
# (commit b62eebb visual polish, deleted 2026-05-26 dev cleanup). Draws a
# pixel-grid over the 480×270 viewport with optional per-cell "col,row"
# labels. Major lines every 4 cells. Reusable by any dev tool that wants
# to lay out a screen against a known grid (UI plotter, future HUD layout
# tweaks). Drop into a CanvasLayer at a high layer index for live overlay
# on top of an arbitrary scene.

const FONT       = preload("res://graphics/fonts/PixelOperator.ttf")
const FONT_SIZE  = 6
const GRID_MINOR = Color(1.0, 1.0, 1.0, 0.10)
const GRID_MAJOR = Color(1.0, 1.0, 1.0, 0.25)
const LABEL_COL  = Color(1.0, 1.0, 1.0, 0.55)

# Per-call viewport target. Keeps the helper viewport-agnostic so a 480×270
# plotter can share with a hypothetical 1920×1080 layout test later.
const VIEW_W: float = 480.0
const VIEW_H: float = 270.0

# Mutable knobs the host scene tweaks via setters; trigger queue_redraw.
@export var cell_size: int = 16 :
	set(v):
		cell_size = max(1, v)
		queue_redraw()
@export var show_labels: bool = true :
	set(v):
		show_labels = v
		queue_redraw()
@export var line_alpha: float = 1.0 :
	set(v):
		line_alpha = clampf(v, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	if line_alpha <= 0.001:
		return
	var cols: int = int(VIEW_W / float(cell_size))
	var rows: int = int(VIEW_H / float(cell_size))
	var minor := Color(GRID_MINOR.r, GRID_MINOR.g, GRID_MINOR.b, GRID_MINOR.a * line_alpha)
	var major := Color(GRID_MAJOR.r, GRID_MAJOR.g, GRID_MAJOR.b, GRID_MAJOR.a * line_alpha)
	for col in range(cols + 1):
		var x: float = col * cell_size
		var c: Color = major if col % 4 == 0 else minor
		draw_line(Vector2(x, 0), Vector2(x, VIEW_H), c, 1.0)
	for row in range(rows + 1):
		var y: float = row * cell_size
		var c: Color = major if row % 4 == 0 else minor
		draw_line(Vector2(0, y), Vector2(VIEW_W, y), c, 1.0)
	if not show_labels:
		return
	var label_col := Color(LABEL_COL.r, LABEL_COL.g, LABEL_COL.b, LABEL_COL.a * line_alpha)
	# Labels only fit cleanly at cell_size >= 16. Below that the "c,r" text
	# overlaps adjacent cells; bail to avoid visual noise.
	if cell_size < 16:
		return
	for col in cols:
		for row in rows:
			var pos := Vector2(col * cell_size + 2, row * cell_size + FONT_SIZE + 1)
			draw_string(FONT, pos, "%d,%d" % [col, row],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, label_col)


# Cycle through 8 → 16 → 32 → off → 8. "off" rides on alpha=0 instead of
# a fourth state so the size always represents a real grid the user just saw.
func cycle_cell_size() -> void:
	if line_alpha <= 0.001:
		line_alpha = 1.0
		cell_size = 8
		return
	match cell_size:
		8:  cell_size = 16
		16: cell_size = 32
		_:  line_alpha = 0.0
