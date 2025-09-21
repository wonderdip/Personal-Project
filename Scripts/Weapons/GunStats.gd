extends Node3D

@export var Spread : float = 0
@export_range(1, 20, 1) var Damage : int = 0
@export_range(1, 10, 0.5) var Weight : float = 0

func _ready() -> void:
	add_to_group("Weapons")
