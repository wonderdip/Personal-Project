extends CharacterBody3D


const SENSITIVITY = 0.003
const GRAVITY = 9.8

@onready var head = $Head
@onready var camera = $Head/Camera3D

#Player vars
@export_range(1.0, 10, 0.5) var SPEED = 5.0
@export_range(1.0, 10, 0.5) var JUMP_VELOCITY = 6.0
@export_range(1.0, 3.0, 0.1) var sprint_multiplier = 1.5
@export_range(60, 120, 1) var Base_FOV = 75
@export var ACCELERATION = 15.0
@export var DEACCELERATION = 13.0
@export_range(0.1, 0.5, 0.02) var COYOTE_TIME = 0.2
@export_range(1.0, 3.0, 0.1) var FALL_MULTIPLIER = 1.5
@export_range(1.0, 3.0, 0.1) var LOW_JUMP_MULTIPLIER = 2.0

var Jump_buffer = 0.2
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var FOV_multiplier = 12

#headbob vars
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

var pitch := 0.0

var mouse_unlocked := false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and !mouse_unlocked:
		# Rotate head (yaw)
		head.rotate_y(-event.relative.x * SENSITIVITY)
		
		# Clamp camera rotation (pitch)
		pitch = clamp(pitch - event.relative.y * SENSITIVITY, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = pitch
		
	if event is InputEventKey and event.pressed:
		if event.keycode == Key.KEY_ESCAPE:
			if mouse_unlocked:
				mouse_unlocked = false
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				mouse_unlocked = true
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			
func _input(event: InputEvent) -> void:
	if mouse_unlocked and event is InputEventMouseButton and event.pressed:
		mouse_unlocked = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
func _physics_process(delta: float) -> void:
	
	# Apply gravity
	if not is_on_floor():
		if velocity.y < 0:
			velocity.y -= GRAVITY * FALL_MULTIPLIER * delta
		elif not Input.is_action_pressed("jump"):
			velocity.y -= GRAVITY * LOW_JUMP_MULTIPLIER * delta
		else:
			velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0  # Reset Y velocity on floor
	
	#Checking Coyote Time
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = max(coyote_timer - delta, 0)
	
	#Jump Buffer For instant jumps
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = Jump_buffer
	else:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0)
		
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		
	# Movement
	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		if direction != Vector3.ZERO:
			var target_speed = SPEED
			if Input.is_action_pressed("sprint"):
				target_speed *= sprint_multiplier
			
			#Smooth Acceleration
			velocity.x = move_toward(velocity.x, direction.x * target_speed, ACCELERATION * delta)
			velocity.z = move_toward(velocity.z, direction.z * target_speed, ACCELERATION * delta)
		else:
			#Smooth Deceleration
			velocity.x = move_toward(velocity.x, 0, DEACCELERATION * delta)
			velocity.z = move_toward(velocity.z, 0, DEACCELERATION * delta)
	else:
		var air_control_factor = 4.0  # higher = more control in air
		velocity.x = lerp(velocity.x, direction.x * SPEED, delta * air_control_factor)
		velocity.z = lerp(velocity.z, direction.z * SPEED, delta * air_control_factor)
		
	#headbob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = headbob(t_bob)
	

	# Move the character
	move_and_slide()
	
	#FOV
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var speed_fraction = clamp(horizontal_speed / SPEED, 0.0, 1.0)

	# Increase FOV for sprinting
	var sprint_factor = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var target_fov = Base_FOV + FOV_multiplier * speed_fraction * sprint_factor

	camera.fov = lerp(camera.fov, target_fov, delta * 12.0)
	
func headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos
