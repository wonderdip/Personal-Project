extends Node3D

const SPEED = 120.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var ray: RayCast3D = $MeshInstance3D/RayCast3D

func _ready():
	pass
	
func _physics_process(delta: float) -> void:
	position += transform.basis * Vector3(-SPEED, 0, 0) * delta
	
