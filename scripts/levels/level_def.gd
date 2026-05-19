extends Resource

# Ordered set of waves making up one Combat Level. Once all waves have spawned
# and all enemies cleared, the level is considered complete.

@export var waves: Array = []  # Array of WaveSpec resources
@export var level_name: String = "Sector Alpha"
