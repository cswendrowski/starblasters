extends Node2D
# Test host for the BeamEmitter host-state guard: exposes _dying / _cycling so the
# emitter's suppress-while-dying/cycling guard (review P0) can be exercised.
var _dying: bool = false
var _cycling: bool = false
