extends Node
class_name HologramHUD

# Was: applied a holo ShaderMaterial to the entire HUD tree and drove its
# uniforms from player state. Holo pass stripped 2026-05-16 (Roman: "strip
# out the holo effect"). What remains:
#   - Damage shake on the HUD CanvasLayer offset
#   - Camera trauma on damage
#   - flicker_in/out as a plain alpha tween on the HUD root
#   - Death overlay (fade-to-black ColorRect on player death)
# Player state signals still bind so we can pulse the shake; nothing else
# reads from the player.

@export var hud_root_path: NodePath
var _hud_root: Control = null
var _canvas_layer: CanvasLayer = null
var _canvas_layer_base_offset: Vector2 = Vector2.ZERO

var _player: Node = null

# Damage shake — preserved from the holo era because it sells hits.
const DAMAGE_SHAKE_PER_HP := 22.0
const DAMAGE_SHAKE_DECAY := 5.5
const DAMAGE_SHAKE_FREQ := 38.0
var _shake_amp: float = 0.0
var _shake_dir: Vector2 = Vector2.ZERO
var _shake_t: float = 0.0

# Flicker / death state.
var _flicker_tween: Tween = null
var _dying: bool = false
var _dissolve_tween: Tween = null
var _death_overlay: ColorRect = null


func _ready() -> void:
	if hud_root_path != NodePath(""):
		_hud_root = get_node_or_null(hud_root_path) as Control
	if _hud_root == null and get_parent() is Control:
		_hud_root = get_parent() as Control
	if _hud_root:
		var n: Node = _hud_root.get_parent()
		while n != null and not (n is CanvasLayer):
			n = n.get_parent()
		_canvas_layer = n as CanvasLayer
	if _canvas_layer:
		_canvas_layer_base_offset = _canvas_layer.offset


# ---- Public API ---------------------------------------------------------

func bind_player(player: Node) -> void:
	if _player == player:
		return
	if _player and is_instance_valid(_player):
		_disconnect_player(_player)
	_player = player
	if _player == null:
		return
	if _player.has_signal("damaged"):
		if not _player.damaged.is_connected(_on_damage):
			_player.damaged.connect(_on_damage)
	if _player.has_signal("died"):
		if not _player.died.is_connected(_on_player_died):
			_player.died.connect(_on_player_died)


# Environmental disruption hook — kept as a no-op so existing callers don't
# need to be touched. Without a shader, there's no "disruption" to apply.
func add_disruption(_strength: float, _duration: float) -> void:
	pass


func flicker_in(duration: float = 0.45) -> void:
	if _hud_root == null:
		return
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_hud_root.modulate.a = 0.0
	_flicker_tween = create_tween()
	_flicker_tween.tween_property(_hud_root, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func flicker_out(duration: float = 0.35) -> void:
	if _hud_root == null:
		return
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_flicker_tween = create_tween()
	_flicker_tween.tween_property(_hud_root, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


# ---- Signal handlers ----------------------------------------------------

func _on_damage(amount: int) -> void:
	var hit_amp: float = float(amount) * DAMAGE_SHAKE_PER_HP
	_shake_amp = max(_shake_amp, hit_amp)
	_shake_t = 0.0
	var main := get_tree().get_current_scene()
	if main and main.has_node("Camera2D"):
		var cam = main.get_node("Camera2D")
		if cam.has_method("add_trauma"):
			cam.add_trauma(min(0.25 + 0.15 * float(amount), 0.9))


func _on_player_died() -> void:
	if _dying:
		return
	_dying = true
	_spawn_death_overlay()
	if _dissolve_tween and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	_dissolve_tween = create_tween().set_parallel(true)
	if _hud_root:
		_dissolve_tween.tween_property(_hud_root, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _death_overlay:
		_dissolve_tween.tween_property(_death_overlay, "color:a", 1.0, 1.2)


# ---- Per-frame ----------------------------------------------------------

func _process(delta: float) -> void:
	if _shake_amp <= 0.0:
		if _canvas_layer:
			_canvas_layer.offset = _canvas_layer_base_offset
		return
	_shake_amp = max(_shake_amp - DAMAGE_SHAKE_DECAY * _shake_amp * delta, 0.0)
	_shake_t += delta
	if _shake_t >= 1.0 / DAMAGE_SHAKE_FREQ:
		_shake_t = 0.0
		_shake_dir = Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0)
	if _canvas_layer:
		_canvas_layer.offset = _canvas_layer_base_offset + _shake_dir * _shake_amp


# ---- Helpers ------------------------------------------------------------

func _spawn_death_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 100
	if not tree_exiting.is_connected(_cleanup_death_overlay):
		tree_exiting.connect(_cleanup_death_overlay)
	get_tree().root.add_child(cl)
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0, 0, 0, 0)
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.anchor_right = 1.0
	_death_overlay.anchor_bottom = 1.0
	cl.add_child(_death_overlay)


func _cleanup_death_overlay() -> void:
	if _death_overlay == null or not is_instance_valid(_death_overlay):
		_death_overlay = null
		return
	var cl: Node = _death_overlay.get_parent()
	_death_overlay = null
	if cl != null and is_instance_valid(cl):
		cl.queue_free()


func _disconnect_player(p: Node) -> void:
	if p.has_signal("damaged") and p.damaged.is_connected(_on_damage):
		p.damaged.disconnect(_on_damage)
	if p.has_signal("died") and p.died.is_connected(_on_player_died):
		p.died.disconnect(_on_player_died)
