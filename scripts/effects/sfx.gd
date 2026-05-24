extends Node
class_name Sfx

# Generic one-shot / polyphony helpers for transient SFX.
#
# Two patterns this module supports:
#
# 1. play_one_shot(stream, world_pos, volume_db)
#    Spawns a transient AudioStreamPlayer2D parented under the scene root,
#    plays the stream, frees itself on `finished`. Use this when the
#    sound's emitter (an enemy, a bullet) is about to queue_free — if the
#    AudioStreamPlayer2D is a child of the emitter, it gets freed mid-
#    playback and the audio clips. Death sounds are the main offender
#    (Roman feedback 2026-05-23: "make sure all audio plays to completion
#    so they can overlay, rather than clipping").
#
# 2. ensure_polyphony(player, n)
#    Bumps an existing AudioStreamPlayer2D's `max_polyphony`. Use for
#    scene-embedded SFX nodes whose parent is NOT about to die (e.g.
#    player ship's fire sound). Default Godot polyphony is 1; subsequent
#    play() calls clip the previous. n=4 lets up to 4 simultaneous voices
#    overlap freely.

const DEFAULT_POLYPHONY: int = 4


static func play_one_shot(stream: AudioStream, world_pos, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return
	var root: Node = (tree as SceneTree).root
	if root == null:
		return
	if world_pos is Vector2:
		var p := AudioStreamPlayer2D.new()
		p.stream = stream
		p.volume_db = volume_db
		p.pitch_scale = pitch_scale
		p.global_position = world_pos
		root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.pitch_scale = pitch_scale
		root.add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


# Convenience: emit a node's stream as a root-parented one-shot. Useful
# when you have a scene-embedded AudioStreamPlayer2D whose parent is
# about to queue_free (death SFX). Reads stream/volume off the node, then
# the node can free without taking the audio with it.
static func play_node_detached(node) -> void:
	if node == null:
		return
	var stream: AudioStream = node.stream if "stream" in node else null
	if stream == null:
		return
	var vol: float = node.volume_db if "volume_db" in node else 0.0
	var pos = null
	if node is Node2D:
		pos = (node as Node2D).global_position
	play_one_shot(stream, pos, vol)


static func ensure_polyphony(player, n: int = DEFAULT_POLYPHONY) -> void:
	if player == null:
		return
	if "max_polyphony" in player:
		player.max_polyphony = max(player.max_polyphony, n)
