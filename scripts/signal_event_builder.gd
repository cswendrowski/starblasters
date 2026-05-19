extends RefCounted
class_name SignalEventBuilder

# Builder helpers for Unknown Signal events. Each event in signal_event.gd
# is a Dictionary `{title, body, choices}` where each choice is
# `{label, action: Callable(self)}`. This file collects the common
# outcome callables so adding a new event is "pick a title + body + a
# few prebuilt outcomes" instead of authoring every callable inline.
#
# Roman, 2026-05-16: "see if there's any standardization you can do to
# make their presentation more consistent, and make creating future
# events simpler".
#
# Example usage from signal_event.gd:
#
#   const SEB = preload("res://scripts/signal_event_builder.gd")
#   return SEB.event("Static Burst",
#       "A jammed transponder chirps your callsign.",
#       [
#           SEB.choice("Hail back (+10 bounty)", SEB.give_bounty(10)),
#           SEB.choice("Ignore", SEB.finish("Static fades.")),
#       ])


# Build an event dict.
static func event(title: String, body: String, choices: Array) -> Dictionary:
	return {"title": title, "body": body, "choices": choices}


# Build a choice dict.
static func choice(label: String, action: Callable) -> Dictionary:
	return {"label": label, "action": action}


# ---- Outcome action builders ------------------------------------------
# Each returns a Callable taking the signal_event scene `s` and using its
# helpers (_apply_bounty / _apply_hull_delta / _finish_to_sector_map).

static func give_bounty(amount: int, result_text: String = "") -> Callable:
	return func(s):
		s._apply_bounty(amount)
		var t: String = result_text
		if t == "":
			t = "+%d bounty" % amount
		s._finish_to_sector_map(t)


static func take_bounty(amount: int, result_text: String = "") -> Callable:
	return func(s):
		s._apply_bounty(-amount)
		s._finish_to_sector_map(result_text if result_text != "" else "-%d bounty" % amount)


static func change_hull(delta: int, result_text: String = "") -> Callable:
	return func(s):
		s._apply_hull_delta(delta)
		var t: String = result_text
		if t == "":
			t = "+%d hull" % delta if delta >= 0 else "-%d hull" % -delta
		s._finish_to_sector_map(t)


static func give_ammo(amount: int, result_text: String = "") -> Callable:
	return func(s):
		if s.has_node("/root/Run"):
			var run = s.get_node("/root/Run")
			if int(run.ammo) >= 0:
				run.ammo = int(run.ammo) + amount
				s._finish_to_sector_map(result_text if result_text != "" else "+%d rounds" % amount)
				return
		s._finish_to_sector_map("No ammo-fed weapon to refill.")


static func finish(result_text: String = "") -> Callable:
	return func(s):
		s._finish_to_sector_map(result_text)


# Launch combat with an optional intro flag (used by Ambush for the
# fly-up parallax beat).
static func launch_combat(intro: String = "") -> Callable:
	return func(s):
		if s.has_node("/root/Run"):
			s.get_node("/root/Run").combat_intro = intro
		s._do_ambush_combat()  # reuses the existing transition path


# Launch a hazard run (used by Freespace Miner). subtype: "asteroid_field"
# or "minefield". bonus_bounty applies to asteroid_field's per-rock value.
static func launch_hazard(subtype: String, bonus_bounty: int = 0) -> Callable:
	return func(s):
		if s.has_node("/root/Run"):
			var run = s.get_node("/root/Run")
			run.current_node_type = 5  # SectorNode.NodeType.HAZARD
			run.current_hazard_subtype = subtype
			run.asteroid_bonus_bounty = bonus_bounty
		var SceneTransition = load("res://scripts/scene_transition.gd")
		SceneTransition.change_scene(s.get_tree(), "res://scenes/main.tscn")
