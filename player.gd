extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003   # Make sensitivity finer

@onready var head = $Head
@onready var camera = $Head/Camera3D

var gravity = 9.8
var sprint_multiplier = 1.5
var pitch := 0.0  # For clamping camera rotation

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Rotate head (yaw)
		head.rotate_y(-event.relative.x * SENSITIVITY)
		
		# Clamp camera rotation (pitch)
		pitch = clamp(pitch - event.relative.y * SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = pitch

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0  # Reset Y velocity on floor

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		if Input.is_action_pressed("sprint"):
			velocity.x = direction.x * SPEED * sprint_multiplier
			velocity.z = direction.z * SPEED * sprint_multiplier
		else:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Move the character
	move_and_slide()
